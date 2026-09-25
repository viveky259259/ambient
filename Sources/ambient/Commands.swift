import AmbientCore
import Foundation

/// Everything except `hook`: setup, diagnostics and demos.
struct Commands {
    let paths: AmbientPaths
    private let out = Terminal()

    func run(_ args: [String]) -> Int32 {
        guard let command = args.first else { return usage() }
        let rest = Array(args.dropFirst())
        switch command {
        case "install": return install(rest)
        case "uninstall": return uninstall(rest)
        case "status": return status(rest)
        case "doctor": return doctor()
        case "emit": return emit(rest)
        case "demo": return demo()
        case "ack": return ack()
        case "link": return link() ? 0 : 1
        case "version", "--version", "-v": print("ambient \(AmbientVersion.current)"); return 0
        case "help", "--help", "-h": return usage()
        default:
            out.error("Unknown command '\(command)'.")
            return usage(code: 64)
        }
    }

    private func usage(code: Int32 = 0) -> Int32 {
        print("""
        \(out.bold("ambient")) \(AmbientVersion.current) — ambient desktop status for coding agents

        \(out.bold("Usage"))
          ambient install [claude|codex|gemini ...] [--dry-run]   Add Ambient's hooks (default: every agent found)
          ambient uninstall [claude|codex|gemini ...] [--dry-run] Remove Ambient's hooks, leaving others alone
          ambient status [--json]                                 Show the sessions Ambient is tracking
          ambient doctor                                          Check the app, the hooks and the connection
          ambient emit <working|waiting|done|error|idle>          Send a demo event
                 [--agent claude|codex|gemini] [--project NAME] [--message TEXT]
          ambient demo                                            Walk through every state
          ambient ack                                             Mark every finished session as seen
          ambient version

        Hooks call `ambient hook <agent>`; set AMBIENT_DEBUG=1 to log them to \(tilde(paths.logs.path))/hook.log.
        """)
        return code
    }

    // MARK: - Install

    private func agents(from args: [String]) -> [AgentKind]? {
        let names = args.filter { !$0.hasPrefix("--") }
        if names.isEmpty || names == ["all"] { return AgentKind.allCases }
        var result: [AgentKind] = []
        for name in names {
            guard let agent = AgentKind(rawValue: name.lowercased()) else {
                out.error("Unknown agent '\(name)'. Use claude, codex or gemini.")
                return nil
            }
            result.append(agent)
        }
        return result
    }

    private func install(_ args: [String]) -> Int32 {
        guard let agents = agents(from: args) else { return 64 }
        let dryRun = args.contains("--dry-run")
        let explicit = !args.filter { !$0.hasPrefix("--") && $0 != "all" }.isEmpty
        let installer = HookInstaller(paths: paths)
        if !dryRun, !link() { return 1 }

        var failed = false
        for agent in agents {
            do {
                let report = try installer.install(agent, dryRun: dryRun)
                let file = tilde(report.config.path)
                if dryRun {
                    out.line(report.changed ? "•" : "✓", "\(agent.displayName): \(report.changed ? "would update" : "already up to date") \(file)")
                    if let preview = report.preview { print(preview) }
                    continue
                }
                let backup = report.backup.map { " (backup: \(tilde($0.path)))" } ?? ""
                out.success("\(agent.displayName): \(report.changed ? "hooks installed in" : "already set up in") \(file)\(backup)")
                if agent == .codex {
                    out.note("Codex asks you to trust new hooks: run /hooks in Codex once and approve Ambient's.")
                }
            } catch InstallerError.agentNotFound where !explicit {
                out.skip("\(agent.displayName): not found, skipped")
            } catch {
                failed = true
                out.error("\(agent.displayName): \(error)")
            }
        }
        if !dryRun, !UnixSocketServer.isListening(paths.socket.path) {
            out.note("Open Ambient.app to see sessions light up.")
        }
        return failed ? 1 : 0
    }

    private func uninstall(_ args: [String]) -> Int32 {
        guard let agents = agents(from: args) else { return 64 }
        let dryRun = args.contains("--dry-run")
        let installer = HookInstaller(paths: paths)
        var failed = false
        for agent in agents {
            do {
                let report = try installer.uninstall(agent, dryRun: dryRun)
                let verb = dryRun ? "would remove hooks from" : "hooks removed from"
                if report.changed { out.success("\(agent.displayName): \(verb) \(tilde(report.config.path))") }
                else { out.skip("\(agent.displayName): nothing to remove") }
                if dryRun, let preview = report.preview { print(preview) }
            } catch InstallerError.agentNotFound {
                out.skip("\(agent.displayName): not found, skipped")
            } catch {
                failed = true
                out.error("\(agent.displayName): \(error)")
            }
        }
        return failed ? 1 : 0
    }

    /// Points ~/.ambient/bin/ambient at this executable, so hooks find it.
    @discardableResult
    private func link() -> Bool {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return false }
        do {
            try paths.ensureHome()
            let fm = FileManager.default
            let link = paths.cliLink
            if let current = try? fm.destinationOfSymbolicLink(atPath: link.path), current == exe.path { return true }
            if (try? fm.attributesOfItem(atPath: link.path)) != nil { try fm.removeItem(at: link) }
            try fm.createSymbolicLink(at: link, withDestinationURL: exe)
            return true
        } catch {
            out.error("Couldn't link \(tilde(paths.cliLink.path)): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Status

    private func request(_ message: WireMessage) -> WireMessage? {
        guard let data = try? Wire.encode(message),
              let reply = try? UnixSocket.send(data, to: paths.socket.path, timeout: 1, expectReply: true),
              !reply.isEmpty else { return nil }
        return try? Wire.decode(reply)
    }

    private func status(_ args: [String]) -> Int32 {
        guard case let .status(sessions, mood)? = request(.statusRequest) else {
            out.error("Ambient isn't running. Open Ambient.app, then try again.")
            return 1
        }
        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(sessions) { print(String(decoding: data, as: UTF8.self)) }
            return 0
        }
        let count = sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"
        print("\(out.bold("Ambient")) · \(count) · \(out.mood(mood, Describe.mood(mood)))")
        let now = Date()
        for s in sessions {
            let elapsed = s.elapsed(now: now).map(Describe.duration) ?? ""
            let title = Trim.truncate(Describe.title(s), max: 18).padding(toLength: 18, withPad: " ", startingAt: 0)
            let agent = s.agent.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            print("  \(out.mood(s.mood, "●")) \(agent) \(title) \(Describe.activity(s.activity))  \(out.dim(elapsed))")
        }
        return 0
    }

    private func ack() -> Int32 {
        guard request(.acknowledgeAll) != nil else {
            out.error("Ambient isn't running.")
            return 1
        }
        return 0
    }

    // MARK: - Doctor

    private func doctor() -> Int32 {
        var problems = 0
        print(out.bold("Ambient doctor"))

        if case let .pong(version)? = request(.ping) {
            out.success("App is running (\(version))")
        } else {
            problems += 1
            out.error("App isn't running — open Ambient.app")
        }

        let fm = FileManager.default
        if fm.isExecutableFile(atPath: paths.cliLink.path) {
            let target = (try? fm.destinationOfSymbolicLink(atPath: paths.cliLink.path)) ?? paths.cliLink.path
            out.success("Hook command: \(tilde(paths.cliLink.path)) → \(tilde(target))")
        } else {
            problems += 1
            out.error("Hook command missing at \(tilde(paths.cliLink.path)) — open Ambient.app or run `ambient install`")
        }

        if paths.socket.path.utf8.count >= 104 {
            problems += 1
            out.error("Socket path is too long for macOS: \(paths.socket.path). Set AMBIENT_HOME to a shorter path.")
        }

        let installer = HookInstaller(paths: paths)
        let states = AgentKind.allCases.map { ($0, installer.status($0)) }
        if !states.contains(where: { $0.1 == .installed || $0.1 == .partial }) {
            problems += 1
            out.error("No agent is connected — run `ambient install`")
        }
        for (agent, state) in states {
            let name = agent.displayName
            switch state {
            case .installed:
                out.success("\(name): hooks installed")
                if agent == .codex { out.note("Codex runs new hooks only after you approve them with /hooks.") }
            case .partial:
                problems += 1
                out.warn("\(name): hooks are incomplete or outdated — run `ambient install \(agent.rawValue)`")
            case .notInstalled:
                out.warn("\(name): hooks not installed — run `ambient install \(agent.rawValue)`")
            case .agentMissing:
                out.skip("\(name): not found")
            case let .unreadable(reason):
                problems += 1
                out.error("\(name): can't read \(tilde(installer.configURL(agent).path)): \(reason)")
            }
        }

        print(problems == 0 ? out.dim("Everything looks good.") : out.dim("\(problems) problem\(problems == 1 ? "" : "s") found."))
        return problems == 0 ? 0 : 1
    }

    // MARK: - Demo

    private func option(_ name: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private func send(_ events: [AgentEvent]) -> Bool {
        for event in events {
            do { try UnixSocket.send(Wire.encode(.event(event)), to: paths.socket.path, timeout: 0.5) } catch {
                out.error("Ambient isn't running. Open Ambient.app, then try again.")
                return false
            }
        }
        return true
    }

    private func emit(_ args: [String]) -> Int32 {
        guard let name = args.first, let mood = Demo.mood(named: name) else {
            out.error("Usage: ambient emit <working|waiting|done|error|idle> [--agent A] [--project P] [--message M]")
            return 64
        }
        let agent = option("--agent", in: args).flatMap { AgentKind(rawValue: $0.lowercased()) } ?? .claude
        let project = option("--project", in: args) ?? "ambient-demo"
        let events = Demo.events(for: mood, agent: agent, project: project, message: option("--message", in: args),
                                 host: HostCapture.current())
        return send(events) ? 0 : 1
    }

    private func demo() -> Int32 {
        let host = HostCapture.current()
        print(out.bold("Ambient demo") + out.dim(" — watch the notch, the Dock and the menu bar"))
        for step in Demo.tour {
            print("  \(out.mood(step.mood, "●")) \(step.title)")
            let events = Demo.events(for: step.mood, agent: step.agent, project: step.project, message: step.message, host: host)
            guard send(events) else { return 1 }
            Thread.sleep(forTimeInterval: 3)
        }
        print(out.dim("Clearing the demo sessions in 15 seconds…"))
        Thread.sleep(forTimeInterval: 15)
        return send(Demo.tourCleanup(host: host)) ? 0 : 1
    }

    private func tilde(_ path: String) -> String {
        let home = paths.userHome.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Minimal styled output that degrades to plain text when piped or with NO_COLOR.
struct Terminal {
    let color: Bool = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    private func style(_ code: String, _ s: String) -> String { color ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    func bold(_ s: String) -> String { style("1", s) }
    func dim(_ s: String) -> String { style("2", s) }

    func mood(_ m: Mood, _ s: String) -> String {
        switch m {
        case .waiting: style("33", s)
        case .error: style("31", s)
        case .done: style("32", s)
        case .working: style("38;5;173", s)
        case .idle: dim(s)
        }
    }

    func line(_ mark: String, _ s: String) { print("\(mark) \(s)") }
    func success(_ s: String) { print("\(style("32", "✓")) \(s)") }
    func warn(_ s: String) { print("\(style("33", "!")) \(s)") }
    func skip(_ s: String) { print("\(dim("–")) \(dim(s))") }
    func note(_ s: String) { print("  \(dim(s))") }
    func error(_ s: String) {
        FileHandle.standardError.write(Data("\(style("31", "✗")) \(s)\n".utf8))
    }
}
