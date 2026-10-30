import Darwin
import Foundation

/// What Ambient remembers about the agents it connected, in ~/.ambient/agents.json, shared by the app and the
/// CLI: which agents the user connected, so hooks an agent update removed show up as a problem rather than as
/// "not connected", and a fingerprint of each agent's executable, so an update is noticed.
public struct AgentRecord: Codable, Equatable, Sendable {
    public var connected: Set<AgentKind> = []
    public var fingerprints: [AgentKind: String] = [:]

    public init(connected: Set<AgentKind> = [], fingerprints: [AgentKind: String] = [:]) {
        self.connected = connected
        self.fingerprints = fingerprints
    }

    /// Nil when nothing was ever recorded, as before Ambient kept this record.
    public static func load(_ paths: AmbientPaths) -> AgentRecord? {
        guard let data = try? Data(contentsOf: paths.agentRecord) else { return nil }
        return try? JSONDecoder().decode(AgentRecord.self, from: data)
    }

    public func save(_ paths: AmbientPaths) throws {
        try paths.ensureHome()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: paths.agentRecord, options: .atomic)
    }

    /// Notes that the user connected or disconnected an agent. The first time, `seed` names the agents already
    /// connected (before Ambient kept this record), so connecting one agent doesn't forget the others.
    static func update(_ paths: AmbientPaths, _ agent: AgentKind, connected: Bool, seed: () -> Set<AgentKind>) {
        var record = load(paths) ?? AgentRecord(connected: seed())
        if connected { record.connected.insert(agent) } else { record.connected.remove(agent) }
        try? record.save(paths)
    }
}

extension AmbientPaths {
    public var agentRecord: URL { home.appendingPathComponent("agents.json") }
}

/// Something wrong with a connected agent's hooks that Ambient can't silently repair.
public enum HookProblem: Equatable, Hashable, Sendable {
    /// Connected through Ambient, but its hooks are gone: an update or another tool rewrote its settings.
    case removed(AgentKind)
    /// Its settings can't be read, so Ambient can't check or repair them.
    case unreadable(AgentKind)
    /// Running in a terminal and busy, yet none of its hooks reach Ambient.
    case silent(AgentKind)

    public var agent: AgentKind {
        switch self {
        case let .removed(a), let .unreadable(a), let .silent(a): a
        }
    }

    public var summary: String {
        switch self {
        case let .removed(a): "\(a.displayName)'s hooks were removed"
        case let .unreadable(a): "Can't read \(a.displayName)'s settings"
        case let .silent(a): "\(a.displayName)'s hooks stopped firing"
        }
    }

    /// What fixes it, in the user's words.
    public var remedy: String {
        switch self {
        case .removed: "Reconnect"
        case .unreadable: "Show the file"
        case .silent(.codex): "Codex runs new hooks only after you approve them: type /hooks in Codex"
        case .silent: "Restart the session; agents read their hooks when they start"
        }
    }
}

public enum HookHealth {
    /// Problems with the agents the user connected. Out-of-date hooks aren't among them: Ambient repairs those
    /// (see `outdated`). Agents that were never connected, or are no longer installed, are nobody's problem.
    public static func problems(statuses: [AgentKind: InstallState], connected: Set<AgentKind>) -> [HookProblem] {
        AgentKind.hooked.compactMap { agent in
            guard connected.contains(agent), let state = statuses[agent] else { return nil }
            switch state {
            case .notInstalled: return .removed(agent)
            case .unreadable: return .unreadable(agent)
            case .installed, .partial, .agentMissing: return nil
            }
        }
    }

    /// Agents whose hooks need rewriting: an older Ambient's events or location, or a changed setting.
    public static func outdated(statuses: [AgentKind: InstallState]) -> [AgentKind] {
        AgentKind.hooked.filter { statuses[$0] == .partial }
    }

    /// The record for a Mac that has none yet: every agent with Ambient's hooks counts as connected.
    public static func seed(statuses: [AgentKind: InstallState]) -> Set<AgentKind> {
        Set(statuses.filter { $0.value == .installed || $0.value == .partial }.keys)
    }
}

// MARK: - Updates

/// Where each agent's executable usually lives, to notice when it's updated. Not exhaustive: an agent found
/// nowhere here simply isn't watched for updates, and Ambient still re-checks its hooks every few minutes.
public enum AgentExecutable {
    static func candidates(_ agent: AgentKind, home: String) -> [String] {
        let bins = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin"]
        switch agent {
        case .claude: return bins.map { "\($0)/claude" }
        case .codex: return bins.map { "\($0)/codex" }
        case .gemini: return bins.map { "\($0)/gemini" }
        case .antigravity: return bins.map { "\($0)/agy" } + ["/Applications/Antigravity.app/Contents/Info.plist"]
        case .cursor: return bins.map { "\($0)/cursor-agent" } + ["/Applications/Cursor.app/Contents/Info.plist"]
        case .copilot: return bins.map { "\($0)/copilot" }
        case .opencode: return bins.map { "\($0)/opencode" } + ["\(home)/.opencode/bin/opencode"]
        case .custom: return []
        }
    }

    /// The first executable found, resolved through symlinks, with its size and modification time. It changes
    /// when the agent updates: Claude Code links to a file named for its version, `agy` replaces itself.
    public static func fingerprint(_ agent: AgentKind, home: String) -> String? {
        let fm = FileManager.default
        for path in candidates(agent, home: home) where fm.fileExists(atPath: path) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard let attrs = try? fm.attributesOfItem(atPath: resolved) else { continue }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(resolved) \(size) \(Int(modified))"
        }
        return nil
    }
}

// MARK: - Silence

/// An agent process running on this Mac.
public struct AgentProcess: Equatable, Sendable {
    public let agent: AgentKind
    public let pid: Int32
    public let started: Date
    public let cpuSeconds: Double
    /// Attached to a terminal: an interactive session rather than an app's background helper.
    public let interactive: Bool

    public init(agent: AgentKind, pid: Int32, started: Date, cpuSeconds: Double, interactive: Bool) {
        self.agent = agent
        self.pid = pid
        self.started = started
        self.cpuSeconds = cpuSeconds
        self.interactive = interactive
    }
}

/// Notices an agent whose hooks don't fire: a session that runs in a terminal, has been busy for a while, and
/// started after its hooks were in place and Ambient was listening, yet not one of its hooks has reported.
/// Cautious on purpose: an idle session, an app's helper or an older session never counts.
public struct SilenceDetector: Sendable {
    public static let minimumAge: TimeInterval = 120
    /// Seconds of CPU a session spends only while it works: rendering, streaming, running tools.
    public static let minimumCPU: Double = 10

    private var heard: [AgentKind: Set<Int32>] = [:]

    public init() {}

    /// Notes the processes an agent's hook ran under.
    public mutating func heard(from agent: AgentKind, host: HostInfo?) {
        guard let host else { return }
        heard[agent, default: []].formUnion(host.pids + [host.agentPid].compactMap { $0 })
    }

    /// Agents with a silent session. `since` is when each agent's hooks could first have reached Ambient.
    public func silent(_ processes: [AgentProcess], now: Date, since: [AgentKind: Date]) -> Set<AgentKind> {
        Set(processes.filter { p in
            guard p.interactive, let since = since[p.agent], p.started >= since,
                  now.timeIntervalSince(p.started) >= Self.minimumAge, p.cpuSeconds >= Self.minimumCPU else { return false }
            return !(heard[p.agent]?.contains(p.pid) ?? false)
        }.map(\.agent))
    }

    /// Forgets processes that have exited.
    public mutating func keep(only live: Set<Int32>) {
        for agent in heard.keys { heard[agent]?.formIntersection(live) }
    }
}

extension ProcessTree {
    /// Which agent an executable belongs to, by its path. Claude Code's native build runs from a file named for
    /// its version, so its path tells more than its name.
    static func agent(forExecutable path: String) -> AgentKind? {
        let name = (path as NSString).lastPathComponent
        if name == "claude" || path.contains("/claude/versions/") { return .claude }
        if name == "codex" { return .codex }
        if name == "agy" { return .antigravity }
        return nil
    }

    /// Agent processes attached to a terminal, with when they started and the CPU they've used.
    public static func interactiveAgents() -> [AgentProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        procs.removeLast(procs.count - size / MemoryLayout<kinfo_proc>.stride)

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        var found: [AgentProcess] = []
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for kp in procs where ttyName(device: kp.kp_eproc.e_tdev) != nil {
            let pid = kp.kp_proc.p_pid
            let length = Int(proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)))
            guard length > 0,
                  let agent = agent(forExecutable: String(decoding: pathBuffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self))
            else { continue }
            let start = kp.kp_proc.p_starttime
            var usage = rusage_info_v2()
            let cpu: Double = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { raw in
                    guard proc_pid_rusage(pid, RUSAGE_INFO_V2, raw) == 0 else { return 0 }
                    let ticks = Double(pointer.pointee.ri_user_time + pointer.pointee.ri_system_time)
                    return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
                }
            }
            found.append(AgentProcess(agent: agent, pid: pid,
                                      started: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
                                      cpuSeconds: cpu, interactive: true))
        }
        return found
    }
}
