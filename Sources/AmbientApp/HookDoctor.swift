import AmbientCore
import AppKit
import Combine
import os

/// Keeps connected agents' hooks working. Re-checks them at launch, every ten minutes, and as soon as an agent
/// updates or its settings file changes; quietly rewrites out-of-date hooks (with the usual backup); and reports
/// what it can't fix, including a session whose hooks don't fire, for the menu bar to offer a fix.
final class HookDoctor: ObservableObject {
    @Published private(set) var problems: [HookProblem] = []

    private let paths: AmbientPaths
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "hooks")
    private let started = Date()
    private let scanQueue = DispatchQueue(label: "com.viveky259259.Ambient.hookdoctor", qos: .utility)
    private var detector = SilenceDetector()
    private var silent: Set<AgentKind> = []
    private var statuses: [AgentKind: InstallState] = [:]
    private var connected: Set<AgentKind> = []
    private var configDates: [AgentKind: Date] = [:]
    private var fingerprints: [AgentKind: String] = [:]
    private var lastCheck = Date.distantPast
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    static let checkInterval: TimeInterval = 600

    init(paths: AmbientPaths, model: AppModel) {
        self.paths = paths
        cancellable = model.transitions.sink { [weak self] t in self?.detector.heard(from: t.session.agent, host: t.session.host) }
    }

    func start() {
        check()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-reads every agent's hooks, repairs the out-of-date ones and republishes what's left.
    func check() {
        lastCheck = Date()
        let installer = HookInstaller(paths: paths)
        statuses = Dictionary(uniqueKeysWithValues: AgentKind.hooked.map { ($0, installer.status($0)) })
        var record = AgentRecord.load(paths) ?? AgentRecord(connected: HookHealth.seed(statuses: statuses))
        for agent in HookHealth.outdated(statuses: statuses) {
            do {
                try installer.install(agent)
                statuses[agent] = installer.status(agent)
                log.notice("Updated \(agent.rawValue, privacy: .public) hooks")
            } catch {
                log.error("Couldn't update \(agent.rawValue, privacy: .public) hooks: \(String(describing: error), privacy: .public)")
            }
        }
        // Installing records the agent as connected; keep that.
        record.connected.formUnion(AgentRecord.load(paths)?.connected ?? [])
        fingerprints = currentFingerprints()
        connected = record.connected
        try? record.save(paths)
        configDates = currentConfigDates()
        publish()
    }

    /// The menu bar's one click: what `ambient doctor` would suggest, done where it can be. Returns advice to show
    /// when the rest is up to the user.
    func fix(_ problem: HookProblem) -> String? {
        let installer = HookInstaller(paths: paths)
        defer { check() }
        switch problem {
        case let .removed(agent):
            do { try installer.install(agent) } catch { return String(describing: error) }
            return nil
        case let .unreadable(agent):
            if let url = installer.configURL(agent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            return nil
        case let .silent(agent):
            // Rewriting can't hurt and fixes a hook that was edited; the rest happens in the agent.
            let rewrote = (try? installer.install(agent)) != nil
            silent.remove(agent)
            return problem.remedy + "." + (rewrote ? " Ambient also rewrote its hooks, in case they'd been changed." : "")
        }
    }

    private func tick() {
        if Date().timeIntervalSince(lastCheck) >= Self.checkInterval || currentFingerprints() != fingerprints
            || currentConfigDates() != configDates {
            check()
        }
        scanForSilence()
    }

    /// Looks for silent sessions off the main thread; the process list is cheap but not free.
    private func scanForSilence() {
        let watched = Set(connected.filter { statuses[$0] == .installed })
        guard !watched.isEmpty else { return }
        let since = Dictionary(uniqueKeysWithValues: watched.map { agent in
            // Agents read their hooks when a session starts: only sessions started since then, and since Ambient
            // began listening, should have reported.
            (agent, max(started, configDates[agent] ?? started))
        })
        let detector = self.detector
        scanQueue.async { [weak self] in
            let processes = ProcessTree.interactiveAgents()
            let found = detector.silent(processes, now: Date(), since: since)
            DispatchQueue.main.async {
                guard let self else { return }
                self.detector.keep(only: Set(processes.map(\.pid)))
                guard found != self.silent else { return }
                for agent in found.subtracting(self.silent) {
                    self.log.notice("\(agent.rawValue, privacy: .public) runs in a terminal but its hooks don't fire")
                }
                self.silent = found
                self.publish()
            }
        }
    }

    private func publish() {
        let next = HookHealth.problems(statuses: statuses, connected: connected)
            + silent.sorted { $0.rawValue < $1.rawValue }.map(HookProblem.silent)
        if next != problems { problems = next }
    }

    private func currentFingerprints() -> [AgentKind: String] {
        let home = paths.userHome.path
        return Dictionary(uniqueKeysWithValues: AgentKind.hooked.compactMap { agent in
            AgentExecutable.fingerprint(agent, home: home).map { (agent, $0) }
        })
    }

    private func currentConfigDates() -> [AgentKind: Date] {
        let installer = HookInstaller(paths: paths)
        return Dictionary(uniqueKeysWithValues: AgentKind.hooked.compactMap { agent in
            guard let url = installer.configURL(agent) else { return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.modificationDate] as? Date).map { (agent, $0) }
        })
    }
}
