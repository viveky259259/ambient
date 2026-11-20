@testable import AmbientCore
import Foundation
import Testing
@testable import ambient

/// Waits up to `timeout` for `condition`, for messages a server handles on its own threads.
func eventually(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return condition()
}

/// A fake app that answers the common requests the way Ambient.app does.
func standardReplies(sessions: [Session] = [sampleSession()], tasks: [AgentTask] = [],
                     opened: String? = "s1") -> @Sendable (WireMessage) -> WireMessage? {
    { message in
        switch message {
        case .statusRequest: return .status(sessions: sessions, mood: .working)
        case .listTasks: return .tasks(tasks)
        case .open: return .opened(sessionID: opened)
        case .openTask: return .opened(sessionID: opened)
        case .acknowledgeAll: return .pong(version: "test")
        case let .upsertTask(task): return .upsertTaskResult(task)
        case .ping: return .pong(version: "9.9.9")
        default: return nil
        }
    }
}

// MARK: - Top-level dispatch

@Suite struct CommandDispatchTests {
    @Test(arguments: ["version", "--version", "-v"])
    func versionExitsZero(flag: String) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI([flag], paths: home.paths) == 0)
    }

    @Test(arguments: ["help", "--help", "-h"])
    func helpExitsZero(flag: String) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI([flag], paths: home.paths) == 0)
    }

    @Test func noArgumentsPrintsUsage() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI([], paths: home.paths) == 0)
    }

    @Test(arguments: ["bogus", "INSTALL", "statuss", "--json"])
    func unknownCommandIsAUsageError(command: String) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI([command], paths: home.paths) == 64)
    }

    @Test func voiceFilesListsTheManifest() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["voice-files"], paths: home.paths) == 0)
    }

    @Test func linkPointsTheHookCommandAtThisExecutable() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["link"], paths: home.paths) == 0)
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: home.paths.cliLink.path)
        #expect(target == Bundle.main.executableURL?.resolvingSymlinksInPath().path)
        // A second link is a no-op, and a stale file in the way is replaced.
        #expect(runCLI(["link"], paths: home.paths) == 0)
        try FileManager.default.removeItem(at: home.paths.cliLink)
        try Data("stale".utf8).write(to: home.paths.cliLink)
        #expect(runCLI(["link"], paths: home.paths) == 0)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: home.paths.cliLink.path)) != nil)
    }
}

// MARK: - Install / uninstall

@Suite struct InstallCommandTests {
    private func claudeSettings(_ home: TempHome) -> URL { home.root.appendingPathComponent(".claude/settings.json") }

    @Test(arguments: [["install", "nope"], ["uninstall", "nope"], ["install", "claude", "custom"], ["uninstall", "custom"]])
    func unknownAgentIsAUsageError(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
    }

    @Test func dryRunWritesNothing() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        #expect(runCLI(["install", "claude", "--dry-run"], paths: home.paths) == 0)
        #expect(!FileManager.default.fileExists(atPath: claudeSettings(home).path))
        #expect(!FileManager.default.fileExists(atPath: home.paths.cliLink.path))
    }

    @Test func dryRunForEveryAgentSkipsMissingOnes() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["install", "--dry-run"], paths: home.paths) == 0)
        #expect(runCLI(["install", "all", "--dry-run"], paths: home.paths) == 0)
    }

    @Test func installWithNoAgentsFoundSkipsThemAndLinksTheCLI() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["install"], paths: home.paths) == 0)
        #expect(FileManager.default.fileExists(atPath: home.paths.cliLink.path))
    }

    @Test func namingAMissingAgentFails() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["install", "claude"], paths: home.paths) == 1)
    }

    @Test func installThenUninstallRoundTrips() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        let installer = HookInstaller(paths: home.paths)

        #expect(runCLI(["install", "claude"], paths: home.paths) == 0)
        #expect(installer.status(.claude) == .installed)
        let text = try String(contentsOf: claudeSettings(home), encoding: .utf8)
        #expect(text.contains("hook claude"))

        // Installing again changes nothing.
        #expect(runCLI(["install", "claude"], paths: home.paths) == 0)
        #expect(try String(contentsOf: claudeSettings(home), encoding: .utf8) == text)

        // A dry-run uninstall leaves the hooks in place.
        #expect(runCLI(["uninstall", "claude", "--dry-run"], paths: home.paths) == 0)
        #expect(installer.status(.claude) == .installed)

        #expect(runCLI(["uninstall", "claude"], paths: home.paths) == 0)
        #expect(installer.status(.claude) == .notInstalled)
        // Nothing left to remove is still a success.
        #expect(runCLI(["uninstall", "claude"], paths: home.paths) == 0)
    }

    @Test func installKeepsOtherHooksAndBacksUpTheOriginal() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        let original = #"{"theme": "dark", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}"#
        try Data(original.utf8).write(to: claudeSettings(home))

        #expect(runCLI(["install", "claude"], paths: home.paths) == 0)
        let text = try String(contentsOf: claudeSettings(home), encoding: .utf8)
        #expect(text.contains("say done"))
        #expect(text.contains("\"theme\""))
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: home.paths.backups.path)) ?? []
        #expect(!backups.isEmpty)

        #expect(runCLI(["uninstall", "claude"], paths: home.paths) == 0)
        let after = try String(contentsOf: claudeSettings(home), encoding: .utf8)
        #expect(after.contains("say done"))
        #expect(!after.contains("hook claude"))
    }

    @Test func unreadableConfigFailsTheInstall() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        try Data("{ not json".utf8).write(to: claudeSettings(home))
        #expect(runCLI(["install", "claude"], paths: home.paths) == 1)
        #expect(try String(contentsOf: claudeSettings(home), encoding: .utf8) == "{ not json")
    }

    @Test func uninstallEverywhereWithNothingInstalledSucceeds() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["uninstall"], paths: home.paths) == 0)
    }
}

// MARK: - Commands that need the app

@Suite(.serialized) struct AppRequestCommandTests {
    @Test(arguments: [["status"], ["status", "--json"], ["open"], ["open", "api"], ["ack"], ["tasks"], ["tasks", "--json"],
                      ["task", "open", "t1"], ["task", "upsert", "--title", "x"], ["task", "model"]])
    func failsWhenTheAppIsNotRunning(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 1)
    }

    @Test func statusShowsSessionsFromTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        var waiting = sampleSession("s2", agent: .codex, cwd: "/src/web")
        waiting.activity = .waiting(reason: "permission", message: "Run tests?")
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(sessions: [sampleSession(), waiting]))
        defer { app.stop() }
        #expect(runCLI(["status"], paths: home.paths) == 0)
        #expect(runCLI(["status", "--json"], paths: home.paths) == 0)
        #expect(app.received.filter { $0 == .statusRequest }.count == 2)
    }

    @Test func statusWithNoSessions() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(sessions: []))
        defer { app.stop() }
        #expect(runCLI(["status"], paths: home.paths) == 0)
    }

    @Test func anUnexpectedReplyCountsAsNotRunning() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in .pong(version: "x") }
        defer { app.stop() }
        #expect(runCLI(["status"], paths: home.paths) == 1)
        #expect(runCLI(["tasks"], paths: home.paths) == 1)
        #expect(runCLI(["open"], paths: home.paths) == 1)
    }

    @Test func openSendsTheQueryAndReportsAMatch() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["open", "api", "--front"], paths: home.paths) == 0)
        #expect(runCLI(["open"], paths: home.paths) == 0)
        #expect(app.received == [.open(query: "api"), .open(query: nil)])
    }

    @Test func openWithNoMatchFails() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(opened: nil))
        defer { app.stop() }
        #expect(runCLI(["open", "nothing"], paths: home.paths) == 1)
        #expect(runCLI(["open"], paths: home.paths) == 1)
    }

    @Test func ackAcknowledgesEverything() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["ack"], paths: home.paths) == 0)
        #expect(app.received == [.acknowledgeAll])
    }

    @Test func tasksListsTheBoard() throws {
        let home = try TempHome(); defer { home.remove() }
        var task = AgentTask(id: "t1", title: "Fix the flaky socket test", status: .inProgress, project: "ambient")
        task.agents = [.claude, .codex]
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(tasks: [task, AgentTask(id: "t2", title: "Second")]))
        defer { app.stop() }
        #expect(runCLI(["tasks"], paths: home.paths) == 0)
        #expect(runCLI(["tasks", "--json"], paths: home.paths) == 0)
    }

    @Test func tasksWithAnEmptyBoard() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(tasks: []))
        defer { app.stop() }
        #expect(runCLI(["tasks"], paths: home.paths) == 0)
    }

    @Test func taskOpenAsksForTheTask() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["task", "open", "t-42"], paths: home.paths) == 0)
        #expect(app.received == [.openTask("t-42")])
    }

    @Test func taskOpenWithNoChatFails() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies(opened: nil))
        defer { app.stop() }
        #expect(runCLI(["task", "open", "t-42"], paths: home.paths) == 1)
    }

    @Test func taskUpsertSendsTheDraft() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        let args = ["task", "upsert", "--title", "Ship 1.0", "--id", "t-7", "--status", "blocked", "--project", "ambient",
                    "--session", "sess-1"]
        #expect(runCLI(args, paths: home.paths) == 0)
        guard case let .upsertTask(draft)? = app.received.first else {
            Issue.record("No upsert reached the app: \(app.received)")
            return
        }
        #expect(draft.id == "t-7")
        #expect(draft.title == "Ship 1.0")
        #expect(draft.status == .blocked)
        #expect(draft.project == "ambient")
        #expect(draft.sessionIds == ["sess-1"])
        #expect(draft.lastSessionId == "sess-1")
        #expect(draft.manual)
    }

    @Test func taskUpsertDefaultsToBacklogWithAFreshID() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["task", "upsert", "--title", "Plain"], paths: home.paths) == 0)
        guard case let .upsertTask(draft)? = app.received.first else {
            Issue.record("No upsert reached the app")
            return
        }
        #expect(draft.status == .backlog)
        #expect(!draft.id.isEmpty)
        #expect(draft.project == nil)
        #expect(draft.sessionIds.isEmpty)
    }

    @Test func taskModelShowsTheAppsReport() throws {
        let home = try TempHome(); defer { home.remove() }
        let report = TaskModelReport(config: TaskLLMConfig(), model: nil, resolution: .unavailable(.disabled))
        let app = try FakeAppSocket(paths: home.paths) { message in
            switch message {
            case .taskModelRequest, .setTaskModel: return .taskModelReport(report)
            default: return nil
            }
        }
        defer { app.stop() }
        #expect(runCLI(["task", "model"], paths: home.paths) == 0)
        #expect(runCLI(["task", "model", "--json"], paths: home.paths) == 0)
        #expect(runCLI(["task", "model", "--enable"], paths: home.paths) == 0)
        #expect(app.received == [.taskModelRequest, .taskModelRequest, .setTaskModel(TaskModelChange(enabled: true))])
    }

    @Test func taskModelTimeoutFails() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in .taskModelTimedOut }
        defer { app.stop() }
        #expect(runCLI(["task", "model"], paths: home.paths) == 1)
        #expect(runCLI(["task", "model", "--disable"], paths: home.paths) == 1)
    }

    @Test func doctorPassesWithTheAppRunningAndAnAgentConnected() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        #expect(runCLI(["install", "claude"], paths: home.paths) == 0)
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["doctor"], paths: home.paths) == 0)
        #expect(app.received.contains(.ping))
    }

    @Test func doctorFlagsHooksRemovedAfterConnecting() throws {
        let home = try TempHome(); defer { home.remove() }
        try home.addAgentFolder(".claude")
        #expect(runCLI(["install", "claude"], paths: home.paths) == 0)
        // An agent update rewrote its settings and dropped the hooks.
        try Data("{}".utf8).write(to: home.root.appendingPathComponent(".claude/settings.json"))
        let app = try FakeAppSocket(paths: home.paths, respond: standardReplies())
        defer { app.stop() }
        #expect(runCLI(["doctor"], paths: home.paths) == 1)
    }
}

// MARK: - Usage errors and offline commands

@Suite struct TaskCommandTests {
    @Test(arguments: [["task"], ["task", "frobnicate"], ["task", "open"], ["task", "upsert"], ["task", "upsert", "--title"],
                      ["task", "upsert", "--title", ""], ["task", "upsert", "--title", "x", "--status", "doing"],
                      ["task", "model", "--python"], ["task", "model", "a", "b"], ["task", "model", "--bogus"]])
    func usageErrors(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
    }

    @Test(arguments: [["task", "model", "--help"], ["task", "model", "-h"], ["task", "skill-bootstrap", "--help"]])
    func helpNeedsNoApp(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 0)
    }

    @Test func taskModelRefusesAPathWithNothingThere() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["task", "model", "/nonexistent/model.gguf"], paths: home.paths) == 1)
        #expect(runCLI(["task", "model", "relative/model"], paths: home.paths) == 1)
    }

    @Test func taskModelRefusesAMissingPython() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["task", "model", "--python", "/nonexistent/python3"], paths: home.paths) == 1)
    }

    @Test func skillStatusWithAndWithoutAPack() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["task", "skill-status"], paths: home.paths) == 0)
        try home.paths.ensureHome()
        try TaskSkillStore.save(TaskSkillPack.bundledSeed, paths: home.paths)
        #expect(TaskSkillStore.exists(paths: home.paths))
        #expect(runCLI(["task", "skill-status"], paths: home.paths) == 0)
    }

    @Test func parseTaskModelReadsEveryFlag() throws {
        let parsed = try #require(Commands.parseTaskModel(["/m/model.gguf", "--enable", "--json", "--python", "/usr/bin/python3"]))
        #expect(parsed.json)
        #expect(parsed.change.modelPath == "/m/model.gguf")
        #expect(parsed.change.enabled == true)
        #expect(parsed.change.pythonPath == "/usr/bin/python3")

        let clear = try #require(Commands.parseTaskModel(["--clear", "--disable"]))
        #expect(clear.change == TaskModelChange(modelPath: "", enabled: false))
        #expect(!clear.json)

        #expect(Commands.parseTaskModel([])?.change == TaskModelChange())
        #expect(Commands.parseTaskModel(["--python", ""])?.change.pythonPath == "")
    }

    @Test(arguments: [["--python"], ["a", "b"], ["--clear", "a"], ["--unknown"]])
    func parseTaskModelRejects(args: [String]) {
        #expect(Commands.parseTaskModel(args) == nil)
    }

    @Test func absoluteExpandsTildeAndResolvesRelativePaths() {
        #expect(Commands.absolute("") == "")
        #expect(Commands.absolute("   ") == "")
        #expect(Commands.absolute("~/models") == NSHomeDirectory() + "/models")
        #expect(Commands.absolute("/a/b/../c/") == "/a/c")
        #expect(Commands.absolute(" /x/y \n") == "/x/y")
        let cwd = FileManager.default.currentDirectoryPath
        #expect(Commands.absolute("rel/file") == URL(fileURLWithPath: cwd).appendingPathComponent("rel/file").standardizedFileURL.path)
    }

    @Test func problemWithAChange() {
        #expect(Commands.problem(with: TaskModelChange()) == nil)
        #expect(Commands.problem(with: TaskModelChange(modelPath: "")) == nil)
        #expect(Commands.problem(with: TaskModelChange(pythonPath: "")) == nil)
        #expect(Commands.problem(with: TaskModelChange(modelPath: "relative")) == "Use an absolute path.")
        #expect(Commands.problem(with: TaskModelChange(modelPath: "/nonexistent/m"))?.contains("Nothing at") == true)
        #expect(Commands.problem(with: TaskModelChange(pythonPath: "/nonexistent/python"))?.contains("No executable Python") == true)
        #expect(Commands.problem(with: TaskModelChange(pythonPath: "/bin/sh")) == nil)
    }
}

// MARK: - Doctor

@Suite struct DoctorCommandTests {
    @Test func failsWithNoAppAndNoAgents() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["doctor"], paths: home.paths) == 1)
    }

    @Test(arguments: [["doctor", "--remote"], ["doctor", "--remote", "a", "b"]])
    func remoteUsageErrors(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
    }

    @Test func remoteForAnUnknownMachineFails() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["doctor", "--remote", "devbox"], paths: home.paths) == 1)
    }

    @Test func socketPathTooLongIsAProblem() throws {
        let home = try TempHome(); defer { home.remove() }
        let long = AmbientPaths(userHome: home.root,
                                home: home.root.appendingPathComponent(String(repeating: "x", count: 110), isDirectory: true))
        #expect(long.socket.path.utf8.count >= 104)
        #expect(runCLI(["doctor"], paths: long) == 1)
    }
}

// MARK: - Remote

private let fingerprint = "id:" + String(repeating: "a", count: 32)

@Suite struct RemoteCommandTests {
    @Test(arguments: [["remote"], ["remote", "teleport"], ["remote", "add"], ["remote", "add", "--host", "x"],
                      ["remote", "add", "Bad Name"], ["remote", "add", "-leading"], ["remote", "add", "box", "--redaction", "secret"],
                      ["remote", "remove"], ["remote", "remove", "--uninstall"], ["remote", "purge"], ["remote", "purge", "--x"],
                      ["remote", "purge", "UPPER"]])
    func usageErrors(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
        #expect(MachineFile.load(from: home.paths.machinesFile).isEmpty)
    }

    @Test func addWithoutTheBundledShimFailsBeforeAnySSH() throws {
        // In a test run there's no Ambient.app around the binary, so pairing stops before touching the network.
        let home = try TempHome(); defer { home.remove() }
        #expect(RemoteShim.bundledURL() == nil)
        #expect(runCLI(["remote", "add", "devbox", "--host", "devbox.local"], paths: home.paths) == 1)
        #expect(MachineFile.load(from: home.paths.machinesFile).isEmpty)
    }

    @Test func listWithNoMachines() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["remote", "list"], paths: home.paths) == 0)
    }

    @Test func listShowsPairedMachines() throws {
        let home = try TempHome(); defer { home.remove() }
        try MachineFile.save([Machine(id: "devbox", label: "Dev Box", transport: ["ssh", "devbox"], fingerprint: fingerprint),
                              Machine(id: "studio", transport: ["ssh", "studio"], fingerprint: fingerprint)],
                             to: home.paths.machinesFile)
        #expect(runCLI(["remote", "list"], paths: home.paths) == 0)
    }

    @Test func removeAnUnknownMachineFails() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["remote", "remove", "ghost"], paths: home.paths) == 1)
    }

    @Test func removeUnpairsAndAudits() throws {
        let home = try TempHome(); defer { home.remove() }
        try MachineFile.save([Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: fingerprint),
                              Machine(id: "keep", transport: ["ssh", "keep"], fingerprint: fingerprint)],
                             to: home.paths.machinesFile)
        #expect(runCLI(["remote", "remove", "devbox"], paths: home.paths) == 0)
        #expect(MachineFile.load(from: home.paths.machinesFile).map(\.id) == ["keep"])
        let records = home.paths.remoteAudit.records()
        #expect(records.contains { $0.action == .unpaired && $0.machine == "devbox" })
    }

    @Test func removeWithUninstallButNoShimStillUnpairsAndReportsFailure() throws {
        let home = try TempHome(); defer { home.remove() }
        try MachineFile.save([Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: fingerprint)],
                             to: home.paths.machinesFile)
        #expect(runCLI(["remote", "remove", "devbox", "--uninstall"], paths: home.paths) == 1)
        #expect(MachineFile.load(from: home.paths.machinesFile).isEmpty)
    }

    @Test func purgeScrubsAndAuditsEvenWhenNotPaired() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(["remote", "purge", "old-box"], paths: home.paths) == 0)
        #expect(home.paths.remoteAudit.records().contains { $0.action == .purged && $0.machine == "old-box" })
    }

    @Test func purgeUnpairsAPairedMachine() throws {
        let home = try TempHome(); defer { home.remove() }
        try MachineFile.save([Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: fingerprint)],
                             to: home.paths.machinesFile)
        #expect(runCLI(["remote", "purge", "devbox"], paths: home.paths) == 0)
        #expect(MachineFile.load(from: home.paths.machinesFile).isEmpty)
    }

    @Test func doctorRemoteForAPairedMachineWithoutShimReportsProblems() throws {
        let home = try TempHome(); defer { home.remove() }
        try MachineFile.save([Machine(id: "devbox", transport: ["/usr/bin/false"], fingerprint: fingerprint)],
                             to: home.paths.machinesFile)
        // Exit code depends on what RemoteDoctor can check offline; it must answer, not hang or crash.
        let code = runCLI(["doctor", "--remote", "devbox"], paths: home.paths)
        #expect(code == 0 || code == 1)
    }
}

// MARK: - Emit

@Suite(.serialized) struct EmitCommandTests {
    @Test(arguments: [["emit"], ["emit", "dancing"], ["emit", "bogus", "--session", "s1"], ["emit", "--session", "s1"]])
    func usageErrors(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
    }

    @Test(arguments: [["emit", "working"], ["emit", "start", "--session", "s1"]])
    func failsWithNoApp(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 1)
    }

    @Test func demoMoodReachesTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in nil }
        defer { app.stop() }
        #expect(runCLI(["emit", "waiting", "--agent", "codex", "--project", "web", "--message", "Approve?"], paths: home.paths) == 0)
        #expect(eventually { !app.received.isEmpty })
        let events = app.received.compactMap { message -> AgentEvent? in
            if case let .event(e) = message { return e }
            return nil
        }
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.agent == .codex })
    }

    @Test func unknownDemoAgentFallsBackToClaude() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in nil }
        defer { app.stop() }
        #expect(runCLI(["emit", "done", "--agent", "nobody"], paths: home.paths) == 0)
        #expect(eventually { !app.received.isEmpty })
        if case let .event(e)? = app.received.first { #expect(e.agent == .claude) }
    }

    @Test func customSessionEventReachesTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in nil }
        defer { app.stop() }
        let args = ["emit", "working", "--session", "build-42", "--agent", "ci", "--cwd", "/src/app", "--tool", "make",
                    "--detail", "make test"]
        #expect(runCLI(args, paths: home.paths) == 0)
        #expect(eventually { !app.received.isEmpty })
        guard case let .event(e)? = app.received.first else {
            Issue.record("No event: \(app.received)")
            return
        }
        #expect(e.agent == .custom)
        #expect(e.sessionId.contains("build-42"))
        #expect(e.cwd == "/src/app")
    }
}

// MARK: - Hook

@Suite struct HookCommandTests {
    /// Anything but a known agent returns before reading stdin, so a bad hook line never hangs the agent.
    @Test(arguments: [[], ["--answer"], ["nobody"], ["CLAUDE"], ["--claude"]])
    func invalidArgumentsReturnAtOnce(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        let start = Date()
        Hook.run(arguments: args, paths: home.paths)
        #expect(Date().timeIntervalSince(start) < 1)
    }
}
