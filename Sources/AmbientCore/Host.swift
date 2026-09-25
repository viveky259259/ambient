import Darwin
import Foundation

/// Walks the process tree via sysctl.
public enum ProcessTree {
    public struct Entry: Equatable, Sendable {
        public let pid: Int32
        public let name: String

        public init(pid: Int32, name: String) {
            self.pid = pid
            self.name = name
        }
    }

    /// The parent, grandparent, … of `pid`, nearest first, stopping before launchd.
    public static func ancestors(of pid: Int32, max: Int = 12) -> [Entry] {
        var chain: [Entry] = []
        var current = info(pid)?.ppid ?? 0
        while current > 1, chain.count < max, let i = info(current) {
            chain.append(Entry(pid: current, name: i.name))
            current = i.ppid
        }
        return chain
    }

    /// The controlling terminal of `pid`, e.g. "/dev/ttys004", or nil when it has none.
    public static func tty(of pid: Int32) -> String? {
        kinfo(pid).flatMap { ttyName(device: $0.kp_eproc.e_tdev) }
    }

    static func ttyName(device: dev_t) -> String? {
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let s = String(cString: name)
        return s.isEmpty || s == "??" ? nil : "/dev/" + s
    }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        return kp
    }

    private static func info(_ pid: Int32) -> (ppid: Int32, name: String)? {
        guard let kp = kinfo(pid) else { return nil }
        let name = withUnsafeBytes(of: kp.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (kp.kp_eproc.e_ppid, name)
    }
}

/// Figures out where a hook is running: the GUI app hosting the agent, and the agent process.
public enum HostCapture {
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "tcsh", "env", "nohup"]

    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> HostInfo {
        let chain = ProcessTree.ancestors(of: getpid())
        let tty = ProcessTree.tty(of: agentPid(in: chain) ?? getpid())
        return host(environment: environment, chain: chain, tty: tty)
    }

    static func host(environment: [String: String], chain: [ProcessTree.Entry], tty: String? = nil) -> HostInfo {
        func env(_ key: String) -> String? { environment[key].flatMap { $0.isEmpty ? nil : $0 } }
        return HostInfo(bundleId: env("__CFBundleIdentifier"),
                        termProgram: env("TERM_PROGRAM"),
                        pids: chain.map(\.pid),
                        agentPid: agentPid(in: chain),
                        tty: tty,
                        hostSessionId: env("CLAUDE_CODE_HOST_SESSION_ID"),
                        // TMUX is "socket,server-pid,session".
                        tmuxSocket: env("TMUX").flatMap { $0.split(separator: ",").first.map(String.init) },
                        tmuxPane: env("TMUX_PANE"),
                        cmuxWorkspace: env("CMUX_WORKSPACE_ID"),
                        cmuxSurface: env("CMUX_SURFACE_ID"),
                        cmuxSocket: env("CMUX_SOCKET_PATH"))
    }

    /// Agents run hooks through a shell (or directly), so the agent is the first ancestor that isn't a shell.
    static func agentPid(in chain: [ProcessTree.Entry]) -> Int32? {
        chain.first { !shells.contains($0.name) && $0.name != "launchd" }?.pid
    }
}
