import AmbientCore
import AppKit
import AVFoundation
import CoreAudio
import CryptoKit
import Foundation

/// The Ambient speaker: the driver that adds "Ambient" to this Mac's outputs, and the stream that plays what goes to it
/// on another Mac. The stream runs in `Contents/Helpers/ambient-speaker` (built from scripts/speaker-pipe.swift), which
/// this starts with `--app`, reads, and starts again when it stops. The helper copies itself to the other Mac, where it
/// plays only if that Mac's own settings let other Macs play sound there (`Preferences.speakerReceive`).
final class SpeakerController: ObservableObject {
    enum Driver: Equatable {
        /// This build doesn't carry the driver: `swift run`, say.
        case unavailable
        case missing
        case installed
        /// An older one than this build carries.
        case outdated
        case installing
        case removing
        /// What went wrong, and whether it was installing (or removing), to try that again.
        case failed(String, installing: Bool)

        var isBusy: Bool { self == .installing || self == .removing }
        var isInstalled: Bool { self == .installed || self == .outdated }
    }

    enum Stream: Equatable {
        case off
        case connecting(String)
        /// The other Mac's player is ready. Sound reaches it once this Mac's output is Ambient.
        case connected(label: String, device: String, lateMs: Int?, videoWaitsMs: Int?)
        /// It stopped, and starts again in `retryIn` seconds.
        case waiting(String, retryIn: Int)
        /// It can't play until something here changes: the driver is installed, say, or the microphone allowed. It
        /// starts again by itself once it has.
        case stopped(String)
    }

    @Published private(set) var driver: Driver = .missing
    @Published private(set) var stream: Stream = .off
    /// The helper's own words for the last problem, for Details.
    @Published private(set) var detail: String?
    /// Whether this Mac's sound goes to the Ambient speaker, and if not, where.
    @Published private(set) var outputIsAmbient = false
    @Published private(set) var outputName = ""

    private let prefs: Preferences
    private let paths: AmbientPaths
    private var process: Process?
    private var input: Pipe?
    /// Bumped by every start and stop, so a stopped stream's late callbacks change nothing.
    private var generation = 0
    private var retries = 0
    private var problem: (text: String, retries: Bool)?

    static let speakerUID = "com.viveky259259.Ambient.speaker"
    private static let installed = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/AmbientSpeaker.driver")
    private static var bundledDriver: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/AmbientSpeaker.driver")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var helper: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ambient-speaker")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var microphoneAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    init(prefs: Preferences, paths: AmbientPaths = .current()) {
        self.prefs = prefs
        self.paths = paths
        refresh()
    }

    /// Looks again at the driver and the output, and starts a stream that was waiting for something here to change.
    func refresh() {
        if !driver.isBusy { driver = Self.driverState() }
        refreshOutput()
        if case .stopped = stream, prefs.speakerOn { launch() }
    }

    // MARK: - The output

    private func refreshOutput() {
        let output = CoreAudioDevices.defaultOutput()
        let isAmbient = output?.uid == Self.speakerUID
        if outputIsAmbient != isAmbient { outputIsAmbient = isAmbient }
        let name = output?.name ?? "another output"
        if outputName != name { outputName = name }
    }

    /// Makes the Ambient speaker this Mac's output.
    func useAmbient() {
        CoreAudioDevices.setDefaultOutput(uid: Self.speakerUID)
        refreshOutput()
    }

    // MARK: - The driver

    private static func driverState() -> Driver {
        guard let bundled = bundledDriver else { return CoreAudioDevices.device(uid: speakerUID) != nil ? .installed : .unavailable }
        guard CoreAudioDevices.device(uid: speakerUID) != nil else { return .missing }
        let ours = buildNumber(bundled), theirs = buildNumber(installed)
        return ours > theirs ? .outdated : .installed
    }

    private static func buildNumber(_ bundle: URL) -> Int {
        let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Installs this build's driver, behind macOS's administrator prompt. Core Audio restarts, which cuts the Mac's
    /// sound for a moment and can switch its output, so the output it had is put back.
    func install() { changeDriver(install: true) }

    func remove() {
        stop()
        changeDriver(install: false)
    }

    /// After a failure: whatever failed, again.
    func tryAgain() {
        if case .failed(_, let installing) = driver { changeDriver(install: installing) }
    }

    private func changeDriver(install: Bool) {
        guard !driver.isBusy else { return }
        let bundled = Self.bundledDriver
        if install, bundled == nil { return }
        driver = install ? .installing : .removing
        // Core Audio's restart would cut the stream off anyway: it stops first, and starts again after.
        let resumes = install && prefs.speakerOn
        halt()
        let outputs = CoreAudioDevices.defaultOutputs()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runPrivileged(install: install, bundled: bundled)
            // Core Audio takes a moment to come back and list the speaker, or stop listing it.
            for _ in 0..<40 where (CoreAudioDevices.device(uid: Self.speakerUID) != nil) != install {
                Thread.sleep(forTimeInterval: 0.25)
            }
            CoreAudioDevices.restore(outputs)
            DispatchQueue.main.async {
                self.driver = result.map { .failed($0, installing: install) } ?? Self.driverState()
                self.refreshOutput()
                if resumes { self.launch() }
            }
        }
    }

    /// Nil when it worked, or the user cancelled; otherwise what went wrong.
    private static func runPrivileged(install: Bool, bundled: URL?) -> String? {
        let hal = installed.path
        var steps = "rm -rf '\(hal)'"
        var stage: URL?
        if install, let bundled {
            // Root can't read every folder of the user's, so it copies from a temporary one.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-speaker-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: folder.appendingPathComponent("AmbientSpeaker.driver"))
            } catch {
                return "Couldn't get the Ambient speaker ready to install: \(error.localizedDescription)"
            }
            stage = folder
            steps += " && cp -R '\(folder.path)/AmbientSpeaker.driver' '\(installed.deletingLastPathComponent().path)/'"
                + " && chown -R root:wheel '\(hal)'"
        }
        // Core Audio looks for drivers only when it starts, and launchd starts it again at once.
        steps += " && (killall coreaudiod || true)"
        defer { if let stage { try? FileManager.default.removeItem(at: stage) } }
        let why = install
            ? "Ambient needs your password to add the Ambient speaker to this Mac's sound outputs."
            : "Ambient needs your password to remove the Ambient speaker from this Mac's sound outputs."
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", "do shell script \"\(steps)\" with prompt \"\(why)\" with administrator privileges"]
        let errors = Pipe()
        osascript.standardError = errors
        osascript.standardOutput = FileHandle.nullDevice
        do { try osascript.run() } catch { return error.localizedDescription }
        osascript.waitUntilExit()
        guard osascript.terminationStatus != 0 else { return nil }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return message.contains("-128") ? nil : "macOS didn't let Ambient \(install ? "install" : "remove") the speaker."
    }

    // MARK: - The stream

    /// How a paired machine is reached, when it's by ssh: the pairing's own command and options, so its port, key and
    /// jump hosts apply, and its host.
    struct Route: Equatable {
        let ssh: [String]
        let host: String
    }

    static func route(to machine: Machine) -> Route? {
        guard let command = machine.transport.first, URL(fileURLWithPath: command).lastPathComponent == "ssh",
              machine.transport.count > 1, let host = machine.transport.last, !host.hasPrefix("-") else { return nil }
        var ssh = Array(machine.transport.dropLast())
        if !ssh[0].hasPrefix("/") { ssh[0] = "/usr/bin/ssh" }
        return Route(ssh: ssh, host: host)
    }

    /// Plays on the machine chosen, starting again at login, until stopped.
    func start(on machineID: String) {
        prefs.speakerDestination = machineID
        prefs.speakerOn = true
        retries = 0
        launch()
    }

    func stop() {
        prefs.speakerOn = false
        halt()
        stream = .off
        detail = nil
    }

    /// At launch: plays where it played when the app quit.
    func resume() {
        if prefs.speakerOn { launch() }
    }

    /// The app is quitting: the helper stops as its input closes, and the setting stays, to resume next time.
    func quit() { halt() }

    private func halt() {
        generation += 1
        // Its input closing stops it cleanly: the player plays what it holds, and the speaker's delay goes back to none.
        try? input?.fileHandleForWriting.close()
        let stopping = process
        process = nil
        input = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if stopping?.isRunning == true { stopping?.terminate() } }
    }

    private func launch() {
        halt()
        let current = generation
        problem = nil
        guard let id = prefs.speakerDestination,
              let machine = MachineFile.load(from: paths.machinesFile).first(where: { $0.id == id }) else {
            stream = .stopped("The Mac it played on isn't paired any more. Choose another.")
            return
        }
        guard let route = Self.route(to: machine) else {
            stream = .stopped("\(machine.label) is paired with a custom command, so the speaker can't play there.")
            return
        }
        guard let helper = Self.helper else {
            stream = .stopped("This copy of Ambient doesn't come with the speaker.")
            return
        }
        // Problems only something here can fix: refresh() starts it again once they're fixed.
        guard CoreAudioDevices.device(uid: Self.speakerUID) != nil else {
            stream = .stopped("Install the Ambient speaker on this Mac first.")
            return
        }
        guard Self.microphoneAllowed else {
            stream = .stopped("Allow the microphone first. Ambient hears only the Ambient speaker.")
            return
        }
        stream = .connecting(machine.label)
        DispatchQueue.global(qos: .userInitiated).async {
            let reason: String
            if let remote = Self.copy(helper, via: route) {
                if self.run(helper, route: route, remote: remote, label: machine.label, generation: current) { return }
                reason = "The speaker's stream couldn't start."
            } else {
                reason = "Couldn't reach \(machine.label)."
            }
            DispatchQueue.main.async { self.stopped(generation: current, reason: reason) }
        }
    }

    /// Copies the helper to the other Mac, into a folder only this user can write to, named by its contents. It's
    /// copied only when the copy there isn't this exact helper, by its hash, and written beside it and renamed over it,
    /// so a copy that's running keeps going and a half-written one is never run. Returns where it is.
    private static func copy(_ helper: URL, via route: Route) -> String? {
        guard let data = try? Data(contentsOf: helper) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let folder = "~/.ambient/speaker", name = "ambient-speaker-\(digest.prefix(12))"
        let path = "\(folder)/\(name)"
        let check = "mkdir -p \(folder) && chmod 700 \(folder) && [ \"$(shasum -a 256 < \(path) 2>/dev/null)\" = \"\(digest)  -\" ]"
        if run(route, check) == 0 { return path }
        // Older helpers go once they've had a week to stop.
        let install = "cat > \(path).part && chmod 755 \(path).part && mv -f \(path).part \(path)"
            + " && find \(folder) -name 'ambient-speaker-*' ! -name '\(name)' -mtime +7 -delete"
        guard run(route, install, input: helper) == 0, run(route, check) == 0 else { return nil }
        return path
    }

    /// Runs a command on the other Mac over its route; `input` is its standard input.
    @discardableResult
    private static func run(_ route: Route, _ command: String, input: URL? = nil) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: route.ssh[0])
        process.arguments = Array(route.ssh.dropFirst()) + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", route.host, command]
        if let input, let file = try? FileHandle(forReadingFrom: input) {
            process.standardInput = file
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Starts the helper, on a background queue. False if it couldn't start; true if it did, or was stopped meanwhile.
    private func run(_ helper: URL, route: Route, remote: String, label: String, generation current: Int) -> Bool {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["send", route.host, "--udp", "--app", "--remote-path", remote, "--"] + route.ssh + [route.host]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        var started = false, superseded = false
        DispatchQueue.main.sync {
            guard current == generation else { superseded = true; return }
            do { try process.run() } catch { return }
            self.process = process
            self.input = input
            started = true
        }
        guard started else { return superseded }
        // Everything it says is heard before it's known to have stopped: it has stopped once its output ends.
        Thread {
            let reader = output.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    guard line.first == UInt8(ascii: "{"),
                          let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    DispatchQueue.main.async { self.heard(event, label: label, generation: current) }
                }
            }
            process.waitUntilExit()
            DispatchQueue.main.async { self.stopped(generation: current, reason: nil) }
        }.start()
        // Standard error isn't read for anything but has to be drained, or a chatty helper would block on it.
        Thread { _ = errors.fileHandleForReading.readDataToEndOfFile() }.start()
        return true
    }

    private func heard(_ event: [String: Any], label: String, generation current: Int) {
        guard current == generation else { return }
        let number = { (key: String) in (event[key] as? NSNumber).map { Int(truncating: $0) } }
        switch event["event"] as? String {
        case "playing":
            retries = 0
            problem = nil
            detail = nil
            refreshOutput()
            stream = .connected(label: label, device: "\(label)'s \(event["device"] as? String ?? "speakers")",
                                lateMs: nil, videoWaitsMs: nil)
        case "status":
            refreshOutput()
            if case .connected(let label, let device, _, _) = stream {
                stream = .connected(label: label, device: device, lateMs: number("lateMs"),
                                    videoWaitsMs: number("videoWaitsMs"))
            }
        case "error":
            let message = event["message"] as? String ?? ""
            detail = message.prefix(1).uppercased() + message.dropFirst()
            problem = Self.explain(message, label: label)
        default:
            break
        }
    }

    /// The helper's words, in a person's: what went wrong, and whether trying again can help.
    private static func explain(_ message: String, label: String) -> (text: String, retries: Bool) {
        if message.contains("has no Ambient speaker") { return ("Install the Ambient speaker on this Mac first.", false) }
        if message.contains("can't record the loopback") {
            return ("Allow the microphone first. Ambient hears only the Ambient speaker.", false)
        }
        if message.contains("doesn't let other Macs play sound") {
            return ("\(label) doesn't take sound from other Macs yet. On \(label), turn on Voice & Sound › Ambient Speaker › "
                    + "Play sound from other Macs.", true)
        }
        if message.contains("loopback") { return ("The Ambient speaker stopped.", true) }
        return ("Lost the connection to \(label).", true)
    }

    /// The helper stopped: it starts again after a pause that grows, up to a minute, while it keeps failing; unless
    /// only something here can fix it, which refresh() notices.
    private func stopped(generation current: Int, reason: String?) {
        guard current == generation, prefs.speakerOn else { return }
        process = nil
        input = nil
        let (text, retrying) = problem ?? (reason ?? "The stream stopped.", true)
        guard retrying else {
            stream = .stopped(text)
            return
        }
        retries += 1
        let wait = min(60, 5 << min(retries - 1, 4))
        stream = .waiting(text, retryIn: wait)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(wait)) { [weak self] in
            guard let self, current == self.generation, self.prefs.speakerOn else { return }
            self.launch()
        }
    }
}

/// The few Core Audio questions the speaker asks.
enum CoreAudioDevices {
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func device(uid: String) -> AudioObjectID? {
        var place = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var uid = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var place = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &place, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var place = address(selector)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func setDefault(_ selector: AudioObjectPropertySelector, to id: AudioObjectID) {
        var id = id
        var place = address(selector)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    /// Where this Mac's sound goes.
    static func defaultOutput() -> (uid: String, name: String)? {
        guard let id = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice),
              let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return (uid, string(id, kAudioObjectPropertyName) ?? uid)
    }

    static func setDefaultOutput(uid: String) {
        guard let id = device(uid: uid) else { return }
        setDefault(kAudioHardwarePropertyDefaultOutputDevice, to: id)
    }

    private static let outputSelectors = [kAudioHardwarePropertyDefaultOutputDevice,
                                          kAudioHardwarePropertyDefaultSystemOutputDevice]

    /// The device sound and alerts go to, by UID.
    static func defaultOutputs() -> [AudioObjectPropertySelector: String] {
        var found: [AudioObjectPropertySelector: String] = [:]
        for selector in outputSelectors {
            if let id = defaultDevice(selector), let uid = string(id, kAudioDevicePropertyDeviceUID) { found[selector] = uid }
        }
        return found
    }

    /// Puts back the outputs `defaultOutputs` found, if they changed and are still there.
    static func restore(_ outputs: [AudioObjectPropertySelector: String]) {
        let now = defaultOutputs()
        for (selector, uid) in outputs where now[selector] != uid {
            if let id = device(uid: uid) { setDefault(selector, to: id) }
        }
    }
}
