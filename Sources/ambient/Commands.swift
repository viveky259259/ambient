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
        case "open": return open(rest)
        case "tasks": return tasks(rest)
        case "task": return task(rest)
        case "link": return link() ? 0 : 1
        case "version", "--version", "-v": print("ambient \(AmbientVersion.current)"); return 0
        // Undocumented, for scripts/fetch-voice-pack.sh: the offline voice's model files, one "path url sha256" per line.
        case "voice-files":
            for f in VoicePackManifest.current.files { print("\(f.path) \(f.url.absoluteString) \(f.sha256)") }
            return 0
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
          ambient install [claude|codex|gemini|antigravity|cursor|copilot|opencode ...] [--dry-run]   Add Ambient's hooks (default: every agent found)
          ambient uninstall [claude|codex|gemini|antigravity|cursor|copilot|opencode ...] [--dry-run] Remove Ambient's hooks, leaving others alone
          ambient status [--json]                                 Show the sessions Ambient is tracking
          ambient tasks [--json]                                  Show the agent task board
          ambient task upsert --title TEXT [--id ID] [--status STATUS] [--project NAME] [--session SID]
                                                                  Create or update a board task (STATUS: backlog|inProgress|blocked|done|cancelled)
          ambient task open ID                                    Jump to a task's linked session
          ambient task skill-bootstrap                            Once: learn a local skill pack via Anthropic (Keychain), then local LLM uses it
          ambient task skill-status                               Show whether ~/.ambient/task-skill.json is present
          ambient doctor                                          Check the app, the hooks and the connection
          ambient emit <working|waiting|done|error|idle>          Send a demo event
                 [--agent claude|codex|gemini|antigravity|cursor|copilot|opencode] [--project NAME] [--message TEXT]
          ambient emit <start|working|waiting|done|error|end> --session ID
                 [--agent NAME] [--cwd PATH] [--tool NAME] [--detail TEXT] [--message TEXT]
                                                                  Drive Ambient from any agent or script
          ambient demo                                            Walk through every state
          ambient open [PROJECT|SESSION]                          Jump to a session's chat, tab or window (default: the most urgent)
          ambient ack                                             Mark every finished session as seen
          ambient version

        Hooks call `ambient hook <agent>`; set AMBIENT_DEBUG=1 to log them to \(tilde(paths.logs.path))/hook.log.
        """)
        return code
    }

    // MARK: - Install

    private func agents(from args: [String]) -> [AgentKind]? {
        let names = args.filter { !$0.hasPrefix("--") }
        if names.isEmpty || names == ["all"] { return AgentKind.hooked }
        var result: [AgentKind] = []
        for name in names {
            guard let agent = AgentKind(rawValue: name.lowercased()), agent != .custom else {
                out.error("Unknown agent '\(name)'. Use \(AgentKind.hooked.map(\.rawValue).joined(separator: ", ")).")
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
            let clock = Describe.clock(s, now: now) ?? ""
            let title = Trim.truncate(Describe.title(s), max: 28).padding(toLength: 28, withPad: " ", startingAt: 0)
            let agent = s.agent.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
            print("  \(out.mood(s.mood, "●")) \(agent) \(title) \(Describe.activity(s.activity))  \(out.dim(clock))")
        }
        return 0
    }

    private func open(_ args: [String]) -> Int32 {
        let query = args.first { !$0.hasPrefix("--") }
        guard case let .opened(id)? = request(.open(query: query)) else {
            out.error("Ambient isn't running. Open Ambient.app, then try again.")
            return 1
        }
        guard id != nil else {
            out.error(query.map { "No session matches '\($0)'. Try `ambient status`." } ?? "No sessions to open.")
            return 1
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

    // MARK: - Tasks

    private func tasks(_ args: [String]) -> Int32 {
        guard case let .tasks(list)? = request(.listTasks) else {
            out.error("Ambient isn't running. Open Ambient.app, then try again.")
            return 1
        }
        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(list) { print(String(decoding: data, as: UTF8.self)) }
            return 0
        }
        if list.isEmpty {
            print("\(out.bold("Board")) · no tasks")
            return 0
        }
        print("\(out.bold("Board")) · \(list.count) task\(list.count == 1 ? "" : "s")")
        for t in list {
            let status = t.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            let project = (t.project ?? "—").padding(toLength: 16, withPad: " ", startingAt: 0)
            let agents = t.agents.map(\.rawValue).joined(separator: ",")
            print("  \(status) \(project) \(Trim.truncate(t.title, max: 40))  \(out.dim(agents.isEmpty ? "—" : agents))  \(out.dim(t.id))")
        }
        return 0
    }

    private func task(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            out.error("Usage: ambient task upsert … | ambient task open ID | ambient task skill-bootstrap")
            return 64
        }
        let rest = Array(args.dropFirst())
        switch sub {
        case "upsert": return taskUpsert(rest)
        case "open":
            guard let id = rest.first else {
                out.error("Usage: ambient task open ID")
                return 64
            }
            guard case let .opened(session)? = request(.openTask(id)) else {
                out.error("Ambient isn't running.")
                return 1
            }
            guard session != nil else {
                out.error("No live session linked to task '\(id)'.")
                return 1
            }
            return 0
        case "skill-bootstrap": return taskSkillBootstrap(rest)
        case "skill-status": return taskSkillStatus()
        default:
            out.error("Unknown task command '\(sub)'. Use upsert, open, skill-bootstrap or skill-status.")
            return 64
        }
    }

    /// One-shot Anthropic learn → writes `~/.ambient/task-skill.json`. Live board stays on local MCP.
    private func taskSkillBootstrap(_ args: [String]) -> Int32 {
        if args.contains("--help") || args.contains("-h") {
            print("""
            ambient task skill-bootstrap

            Reads Anthropic from the login Keychain (service \(SecretStore.service), account anthropic)
            or ANTHROPIC_API_KEY, generates a few-shot skill pack, writes \(tilde(paths.taskSkill.path)) (0600).
            The Board local LLM loads that file; cloud is not used at runtime.
            """)
            return 0
        }
        guard SecretStore.hasKey(for: .anthropic) else {
            out.error("No Anthropic key in Keychain or ANTHROPIC_API_KEY. Stash it first, then re-run.")
            out.note("security add-generic-password -s \(SecretStore.service) -a anthropic -w")
            return 1
        }
        out.line("•", "Bootstrapping local task skill pack (Anthropic once)…")
        do {
            let pack = try TaskSkillBootstrap.runSync(paths: paths)
            out.success("Wrote \(tilde(paths.taskSkill.path)) · \(pack.examples.count) examples · source \(pack.source)")
            out.note("Enable Settings › Board › Summarize tasks with local LLM. Runtime stays on local-agent MCP.")
            return 0
        } catch {
            out.error(error.localizedDescription)
            return 1
        }
    }

    private func taskSkillStatus() -> Int32 {
        if TaskSkillStore.exists(paths: paths) {
            let pack = TaskSkillStore.load(paths: paths)
            out.success("Skill pack: \(tilde(paths.taskSkill.path))")
            out.note("source=\(pack.source) examples=\(pack.examples.count) hints=\(pack.hints.count)")
            return 0
        }
        out.warn("No \(tilde(paths.taskSkill.path)) yet — using bundled seed. Run ambient task skill-bootstrap once.")
        return 0
    }

    private func taskUpsert(_ args: [String]) -> Int32 {
        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        guard let title = option("--title"), !title.isEmpty else {
            out.error("Usage: ambient task upsert --title TEXT [--id ID] [--status STATUS] [--project NAME] [--session SID]")
            return 64
        }
        let statusName = option("--status") ?? "backlog"
        guard let status = TaskStatus(rawValue: statusName) else {
            out.error("Unknown status '\(statusName)'. Use backlog, inProgress, blocked, done or cancelled.")
            return 64
        }
        var draft = AgentTask(id: option("--id") ?? AgentTask.makeID(), title: title, status: status,
                              project: option("--project"), manual: true)
        if let sid = option("--session") {
            draft.sessionIds = [sid]
            draft.lastSessionId = sid
        }
        guard case let .upsertTaskResult(saved)? = request(.upsertTask(draft)) else {
            out.error("Ambient isn't running. Open Ambient.app, then try again.")
            return 1
        }
        out.success("Task \(saved.id): \(saved.status.rawValue) — \(saved.title)")
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
        let states = AgentKind.hooked.map { ($0, installer.status($0)) }
        let connected = AgentRecord.load(paths)?.connected ?? []
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
            case .notInstalled where connected.contains(agent):
                // Connected through Ambient, then removed: usually an agent update rewrote its settings.
                problems += 1
                out.error("\(name): its hooks were removed since you connected it — run `ambient install \(agent.rawValue)`")
            case .notInstalled:
                out.warn("\(name): hooks not installed — run `ambient install \(agent.rawValue)`")
            case .agentMissing:
                out.skip("\(name): not found")
            case let .unreadable(reason):
                problems += 1
                out.error("\(name): can't read \(tilde(installer.configURL(agent)?.path ?? "")): \(reason)")
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
        if let session = option("--session", in: args) { return emitReal(args, session: session) }
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

    /// A real session's event from any agent or script, through the same adapter as `ambient hook custom`.
    /// The return address is wherever the command runs: its terminal tab, tmux pane or app.
    private func emitReal(_ args: [String], session: String) -> Int32 {
        guard let event = args.first, CustomAdapter.events.contains(event) else {
            out.error("Usage: ambient emit <\(CustomAdapter.events.joined(separator: "|"))> --session ID [--agent NAME] [--cwd PATH] [--tool NAME] [--detail TEXT] [--message TEXT]")
            return 64
        }
        var payload: [String: Any] = ["session_id": session, "event": event,
                                      "cwd": option("--cwd", in: args) ?? FileManager.default.currentDirectoryPath]
        for (flag, key) in [("--agent", "agent"), ("--tool", "tool"), ("--detail", "detail"), ("--message", "message"), ("--reason", "reason")] {
            if let value = option(flag, in: args) { payload[key] = value }
        }
        guard let e = AdapterRegistry.event(agent: .custom, payload: HookPayload(payload), eventHint: nil, host: HostCapture.current()) else {
            out.error("That event has no effect.")
            return 64
        }
        return send([e]) ? 0 : 1
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
