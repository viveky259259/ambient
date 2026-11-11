import AmbientCore
import AppKit
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
        case working
        case failed(String)
    }

    enum Stream: Equatable {
        case off
        case connecting(String)
        case playing(device: String, lateMs: Int?, videoWaitsMs: Int?)
        /// It stopped, and starts again shortly.
        case waiting(String)
        /// It can't play until something changes: the driver is installed, say.
        case stopped(String)
    }

    @Published private(set) var driver: Driver = .missing
    @Published private(set) var stream: Stream = .off

    private let prefs: Preferences
    private let paths: AmbientPaths
    private var process: Process?
    private var input: Pipe?
    /// Bumped by every start and stop, so a stopped stream's late callbacks change nothing.
    private var generation = 0
    private var retries = 0
    private var lastError: String?

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

    init(prefs: Preferences, paths: AmbientPaths = .current()) {
        self.prefs = prefs
        self.paths = paths
        refresh()
    }

    // MARK: - The driver

    func refresh() {
        if driver != .working { driver = Self.driverState() }
    }

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

    private func changeDriver(install: Bool) {
        guard driver != .working else { return }
        let bundled = Self.bundledDriver
        if install, bundled == nil { return }
        driver = .working
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
                self.driver = Self.driverState()
                if let result { self.driver = .failed(result) }
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
                return "Couldn't prepare the speaker: \(error.localizedDescription)"
            }
            stage = folder
            steps += " && cp -R '\(folder.path)/AmbientSpeaker.driver' '\(installed.deletingLastPathComponent().path)/'"
                + " && chown -R root:wheel '\(hal)'"
        }
        // Core Audio looks for drivers only when it starts, and launchd starts it again at once.
        steps += " && (killall coreaudiod || true)"
        defer { if let stage { try? FileManager.default.removeItem(at: stage) } }
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", "do shell script \"\(steps)\" with administrator privileges"]
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

    /// The ssh host a paired machine is reached at, when it's reached by plain ssh.
    static func host(of machine: Machine) -> String? {
        guard let command = machine.transport.first, URL(fileURLWithPath: command).lastPathComponent == "ssh",
              machine.transport.count > 1, let host = machine.transport.last, !host.hasPrefix("-") else { return nil }
        return host
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
        guard let id = prefs.speakerDestination,
              let machine = MachineFile.load(from: paths.machinesFile).first(where: { $0.id == id }) else {
            stream = .stopped("The Mac it played on isn't paired any more.")
            return
        }
        guard let host = Self.host(of: machine) else {
            stream = .stopped("\(machine.label) isn't reached by ssh, so the speaker can't play there.")
            return
        }
        guard let helper = Self.helper else {
            stream = .stopped("This build of Ambient doesn't carry the speaker's stream.")
            return
        }
        // Without the speaker there's nothing to play; installing it starts this again.
        guard CoreAudioDevices.device(uid: Self.speakerUID) != nil else {
            stream = .stopped("Install the Ambient speaker on this Mac first.")
            return
        }
        stream = .connecting(machine.label)
        DispatchQueue.global(qos: .userInitiated).async {
            let reason: String
            if let remote = Self.copy(helper, to: host) {
                if self.run(helper, host: host, remote: remote, label: machine.label, generation: current) { return }
                reason = "The speaker's stream couldn't start."
            } else {
                reason = "Couldn't reach \(machine.label)."
            }
            DispatchQueue.main.async { self.stopped(generation: current, reason: reason) }
        }
    }

    /// Copies the helper to the other Mac, named by its contents, unless it's there already. Never over a running copy:
    /// replacing a program while it runs can stop it. Returns where it is.
    private static func copy(_ helper: URL, to host: String) -> String? {
        guard let data = try? Data(contentsOf: helper) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12)
        let remote = "/tmp/ambient-speaker-\(digest)"
        let options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
        if run("/usr/bin/ssh", options + [host, "test", "-x", remote]) == 0 { return remote }
        return run("/usr/bin/scp", ["-q"] + options + [helper.path, "\(host):\(remote)"]) == 0 ? remote : nil
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Starts the helper, on a background queue. False if it couldn't start; true if it did, or was stopped meanwhile.
    private func run(_ helper: URL, host: String, remote: String, label: String, generation current: Int) -> Bool {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["send", host, "--udp", "--app", "--remote-path", remote]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.stopped(generation: current, reason: nil) }
        }
        var started = false, superseded = false
        DispatchQueue.main.sync {
            guard current == generation else { superseded = true; return }
            do { try process.run() } catch { return }
            self.process = process
            self.input = input
            started = true
        }
        guard started else { return superseded }
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
            lastError = nil
            stream = .playing(device: "\(label)'s \(event["device"] as? String ?? "speakers")", lateMs: nil, videoWaitsMs: nil)
        case "status":
            if case .playing(let device, _, _) = stream {
                stream = .playing(device: device, lateMs: number("lateMs"), videoWaitsMs: number("videoWaitsMs"))
            }
        case "error":
            lastError = (event["message"] as? String).map { message in
                // The helper names the ssh host; people know the Mac by its label.
                message.contains("doesn't let other Macs play sound")
                    ? "\(label) doesn't let other Macs play sound on it. Turn on Play sound from other Macs there."
                    : message.prefix(1).uppercased() + message.dropFirst() + "."
            }
            // Its output can be read after it has exited: say why it stopped, then.
            if case .waiting = stream, let lastError { stream = .waiting(lastError) }
        default:
            break
        }
    }

    /// The helper stopped: it starts again after a pause that grows, up to a minute, while it keeps failing.
    private func stopped(generation current: Int, reason: String?) {
        guard current == generation, prefs.speakerOn else { return }
        process = nil
        input = nil
        retries += 1
        let wait = min(60, 5 << min(retries - 1, 4))
        stream = .waiting(reason ?? lastError ?? "The stream stopped.")
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

    private static func uid(of id: AudioObjectID) -> String? {
        var place = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &place, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static let outputSelectors = [kAudioHardwarePropertyDefaultOutputDevice,
                                          kAudioHardwarePropertyDefaultSystemOutputDevice]

    /// The device sound and alerts go to, by UID.
    static func defaultOutputs() -> [AudioObjectPropertySelector: String] {
        var found: [AudioObjectPropertySelector: String] = [:]
        for selector in outputSelectors {
            var place = address(selector)
            var id = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place, 0, nil, &size, &id) == noErr,
               let uid = uid(of: id) { found[selector] = uid }
        }
        return found
    }

    /// Puts back the outputs `defaultOutputs` found, if they changed and are still there.
    static func restore(_ outputs: [AudioObjectPropertySelector: String]) {
        let now = defaultOutputs()
        for (selector, uid) in outputs where now[selector] != uid {
            guard var id = device(uid: uid) else { continue }
            var place = address(selector)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &place, 0, nil,
                                       UInt32(MemoryLayout<AudioObjectID>.size), &id)
        }
    }
}
