import AmbientCore
import CoreAudio
import Foundation

/// Ambient Microphone, both ways: another Mac's microphone as an input here, and this Mac's lent to other Macs.
///
/// Using one: while an app here records from Ambient Microphone, this runs the helper's `mic-receive`, which reaches the
/// other Mac over the pairing's ssh and plays its microphone to the driver's hidden feed. Once no app records from it,
/// the stream stops, and the other Mac's microphone with it. Lending: while it's on, this runs `mic-serve`, which
/// records this Mac's microphone only while another Mac is connected. macOS doesn't let a process ssh starts record the
/// microphone, so it has to be recorded here, in the app.
final class MicController: ObservableObject {
    enum Use: Equatable {
        case off
        /// Ready: it connects once an app here records from Ambient Microphone.
        case idle(String)
        case connecting(String)
        case receiving(label: String, device: String)
        /// It stopped while an app records, and starts again in `retryIn` seconds.
        case waiting(String, retryIn: Int)
        /// It can't work until something here changes, such as the driver being installed.
        case stopped(String)
    }

    enum Lend: Equatable {
        case off
        case ready
        case lending(to: String, device: String)
        case stopped(String)
    }

    @Published private(set) var use: Use = .off
    @Published private(set) var lend: Lend = .off
    /// The helper's own words for the last problem, for Details.
    @Published private(set) var detail: String?
    /// Whether Core Audio has Ambient Microphone: the driver is installed, and new enough to have it.
    @Published private(set) var available = false
    @Published private(set) var inputIsAmbient = false

    static let micUID = "com.viveky259259.Ambient.microphone"

    private let prefs: Preferences
    private let paths: AmbientPaths
    private var receiver: HelperRun?
    private var server: HelperRun?
    /// Bumped by every start and stop, so a stopped run's late callbacks change nothing.
    private var generation = 0, lendGeneration = 0
    private var retries = 0
    /// Where the helper was copied on the other Mac, by machine, so starting to record costs one ssh connection, not two.
    /// Forgotten after any problem, in case it went.
    private var copied: [String: String] = [:]
    private var problem: (text: String, retries: Bool)?
    /// Ambient Microphone, and the listener that hears an app start or stop recording from it.
    private var watched: (device: AudioObjectID, listener: AudioObjectPropertyListenerBlock)?

    init(prefs: Preferences, paths: AmbientPaths = .current()) {
        self.prefs = prefs
        self.paths = paths
        // The driver comes and goes as it's installed, and the input changes in Sound settings.
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var place = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &place, .main, changed)
        }
        devicesChanged()
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// At launch: uses and lends as it did when the app quit.
    func resume() {
        if prefs.micLend { startLending() }
        evaluate()
    }

    /// The app is quitting: both helpers stop as their input closes, and the settings stay, to resume next time.
    func quit() {
        halt()
        stopServer()
    }

    /// Looks again, and starts what was waiting for something here to change.
    func refresh() {
        devicesChanged()
        if case .stopped = use, prefs.micUse, recording { launch() }
        if case .stopped = lend, prefs.micLend { startLending() }
    }

    // MARK: - Using another Mac's

    /// Uses the machine chosen's microphone from now on, starting again at login.
    func startUsing(from machineID: String) {
        prefs.micSource = machineID
        prefs.micUse = true
        retries = 0
        halt()
        use = .off
        evaluate()
    }

    func stopUsing() {
        prefs.micUse = false
        halt()
        use = .off
        detail = nil
        devicesChanged()
    }

    /// Makes Ambient Microphone this Mac's input, which apps that use the input record from.
    func useAsInput() {
        CoreAudioDevices.setDefaultInput(uid: Self.micUID)
        devicesChanged()
    }

    private func devicesChanged() {
        var isAmbient = CoreAudioDevices.defaultInput()?.uid == Self.micUID
        // Not in use, Ambient Microphone is silent. macOS can still make it the input, as when the input before it goes
        // away, and then apps would record silence: another input takes its place, if there is one.
        if isAmbient, !prefs.micUse, let other = CoreAudioDevices.otherInput(than: Self.micUID) {
            CoreAudioDevices.setDefaultInput(other)
            isAmbient = false
        }
        if inputIsAmbient != isAmbient { inputIsAmbient = isAmbient }
        let device = CoreAudioDevices.device(uid: Self.micUID)
        if available != (device != nil) { available = device != nil }
        if device != watched?.device {
            if let watched {
                var place = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
                AudioObjectRemovePropertyListenerBlock(watched.device, &place, .main, watched.listener)
            }
            watched = nil
            if let device {
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
                var place = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
                AudioObjectAddPropertyListenerBlock(device, &place, .main, listener)
                watched = (device, listener)
            }
            evaluate()
        }
    }

    /// Whether an app here records from Ambient Microphone. This app's own helper only plays to the feed.
    private var recording: Bool { watched.map { CoreAudioDevices.isRunningSomewhere($0.device) } ?? false }

    /// Connects while an app here records from Ambient Microphone, and lets go once none does.
    private func evaluate() {
        guard prefs.micUse else { return }
        guard available else {
            halt()
            use = .stopped("Install the Ambient microphone on this Mac first.")
            return
        }
        guard recording else {
            if receiver != nil || use != .idle(sourceLabel) { halt() }
            retries = 0
            problem = nil
            use = .idle(sourceLabel)
            return
        }
        switch use {
        case .connecting, .receiving, .waiting: return
        default: launch()
        }
    }

    private var source: Machine? {
        prefs.micSource.flatMap { id in MachineFile.load(from: paths.machinesFile).first { $0.id == id } }
    }

    private var sourceLabel: String { source?.label ?? "The other Mac" }

    private func halt() {
        generation += 1
        receiver?.stop()
        receiver = nil
    }

    private func launch() {
        halt()
        let current = generation
        problem = nil
        guard let machine = source else {
            use = .stopped("The Mac whose microphone it used isn't paired any more. Choose another.")
            return
        }
        guard let route = SpeakerController.route(to: machine) else {
            use = .stopped("\(machine.label) is paired with a custom command, so its microphone can't be used here.")
            return
        }
        guard let helper = SpeakerController.helper else {
            use = .stopped("This copy of Ambient doesn't come with Ambient Microphone.")
            return
        }
        use = .connecting(machine.label)
        let known = copied[machine.id]
        DispatchQueue.global(qos: .userInitiated).async {
            guard let remote = known ?? SpeakerController.copy(helper, via: route) else {
                DispatchQueue.main.async { self.stopped(generation: current, reason: "Couldn't reach \(machine.label).") }
                return
            }
            let run = HelperRun(helper, ["mic-receive", route.host, "--app", "--remote-path", remote, "--"]
                                    + route.ssh + [route.host])
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                self.copied[machine.id] = remote
                guard run.start(onEvent: { self.heard($0, label: machine.label, generation: current) },
                                onExit: { self.stopped(generation: current, reason: nil) }) else {
                    self.stopped(generation: current, reason: "Ambient Microphone couldn't start.")
                    return
                }
                self.receiver = run
            }
        }
    }

    private func heard(_ event: [String: Any], label: String, generation current: Int) {
        guard current == generation else { return }
        switch event["event"] as? String {
        case "receiving":
            retries = 0
            problem = nil
            detail = nil
            use = .receiving(label: label, device: event["device"] as? String ?? "microphone")
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
        if message.contains("has no Ambient microphone") {
            return ("Install the Ambient microphone on this Mac first.", false)
        }
        if message.contains("doesn't lend its microphone") {
            return ("\(label) doesn't lend its microphone yet. On \(label), turn on Voice & Sound › Ambient Microphone › "
                    + "Lend this Mac's microphone.", true)
        }
        if message.contains("is in use by") { return ("Another Mac is using \(label)'s microphone.", true) }
        if message.contains("has no microphone") { return ("\(label) has no microphone to lend.", true) }
        return ("Lost the connection to \(label).", true)
    }

    /// The helper stopped while an app still records: it starts again after a pause that grows, up to a minute.
    private func stopped(generation current: Int, reason: String?) {
        guard current == generation, prefs.micUse else { return }
        receiver = nil
        if reason != nil || problem != nil { copied = [:] }
        let (text, retrying) = problem ?? (reason ?? "The microphone's stream stopped.", true)
        guard retrying else {
            use = .stopped(text)
            return
        }
        guard recording else {
            use = .idle(sourceLabel)
            return
        }
        retries += 1
        let wait = min(60, 5 << min(retries - 1, 4))
        use = .waiting(text, retryIn: wait)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(wait)) { [weak self] in
            guard let self, current == self.generation, self.prefs.micUse else { return }
            if self.recording { self.launch() } else { self.use = .idle(self.sourceLabel) }
        }
    }

    // MARK: - Lending this Mac's

    /// Lends this Mac's microphone to other Macs from now on, starting again at login.
    func startLending() {
        prefs.micLend = true
        stopServer()
        let current = lendGeneration
        guard let helper = SpeakerController.helper else {
            lend = .stopped("This copy of Ambient doesn't come with Ambient Microphone.")
            return
        }
        guard SpeakerController.microphoneAllowed else {
            lend = .stopped("Allow the microphone first.")
            return
        }
        let run = HelperRun(helper, ["mic-serve", "--app"])
        guard run.start(onEvent: { self.heardLending($0, generation: current) },
                        onExit: { self.serverStopped(generation: current) }) else {
            lend = .stopped("Couldn't lend the microphone.")
            return
        }
        server = run
        lend = .ready
    }

    func stopLending() {
        prefs.micLend = false
        stopServer()
        lend = .off
    }

    private func stopServer() {
        lendGeneration += 1
        server?.stop()
        server = nil
    }

    private func heardLending(_ event: [String: Any], generation current: Int) {
        guard current == lendGeneration else { return }
        switch event["event"] as? String {
        case "ready", "idle":
            lend = .ready
        case "lending":
            lend = .lending(to: event["to"] as? String ?? "Another Mac", device: event["device"] as? String ?? "microphone")
        case "error":
            let message = event["message"] as? String ?? ""
            lend = .stopped(message.contains("can't record the microphone") ? "Allow the microphone first."
                                : "Couldn't lend the microphone.")
        default:
            break
        }
    }

    /// The server stopped by itself: after a problem only something here can fix, it waits for refresh(); otherwise
    /// it starts again in 5 seconds.
    private func serverStopped(generation current: Int) {
        guard current == lendGeneration, prefs.micLend else { return }
        server = nil
        if case .stopped = lend { return }
        lend = .stopped("Lending stopped. Trying again…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, current == self.lendGeneration, self.prefs.micLend else { return }
            self.startLending()
        }
    }
}
