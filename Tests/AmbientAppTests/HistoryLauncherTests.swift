@testable import AmbientApp
@testable import AmbientCore
import AmbientHistory
import Foundation
import Testing

/// When the app hands a chat to `ambient history capture`, and when it doesn't.
@Suite struct HistoryLauncherTests {
    private func change(_ session: Session, event: EventKind?, removed: Bool) -> SessionChange {
        SessionChange(session: session, previous: session.activity, event: event, removed: removed)
    }

    private func session(_ id: String = "abc", pid: Int32? = nil) -> Session {
        var s = makeSession(id)
        s.host = HostInfo(agentPid: pid)
        return s
    }

    @Test func aChatIsFinishedWhenItSaysSoOrItsAgentHasExited() {
        let alive: (Int32) -> Bool = { $0 == 100 }
        // It said it ended.
        #expect(HistoryLauncher.isFinished(change(session(), event: .sessionEnded, removed: true), isAlive: alive))
        // Its agent's process is gone.
        #expect(HistoryLauncher.isFinished(change(session(pid: 200), event: nil, removed: true), isAlive: alive))
        // Dropped from the island for going quiet, with its agent still running: it may pick up again.
        #expect(!HistoryLauncher.isFinished(change(session(pid: 100), event: nil, removed: true), isAlive: alive))
        // Dropped with no process to ask about: the hourly look decides, not this.
        #expect(!HistoryLauncher.isFinished(change(session(), event: nil, removed: true), isAlive: alive))
        // Still on the island.
        #expect(!HistoryLauncher.isFinished(change(session(), event: .turnCompleted(summary: nil), removed: false), isAlive: alive))
        #expect(!HistoryLauncher.isFinished(change(session("demo-1"), event: .sessionEnded, removed: true), isAlive: alive))
    }

    @Test func aChatOnAnotherMachineIsThatMachinesToStore() throws {
        var remote = session()
        remote.origin = RemoteOrigin(machine: MachineRef(id: "daily", label: "Daily"))
        #expect(!HistoryLauncher.isFinished(change(remote, event: .sessionEnded, removed: true), isAlive: { _ in false }))
    }

    /// Collects what the launcher would have run.
    private final class Launched: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String]] = []
        var commands: [[String]] {
            lock.lock()
            defer { lock.unlock() }
            return all
        }
        func add(_ arguments: [String]) {
            lock.lock()
            all.append(arguments)
            lock.unlock()
        }
    }

    private func wait(for launched: Launched, count: Int) {
        let deadline = Date().addingTimeInterval(3)
        while launched.commands.count < count, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    @Test func startsNothingUntilARepositoryIsSetUp() throws {
        let box = try AppSandbox()
        let launched = Launched()
        let launcher = HistoryLauncher(paths: box.paths, isAlive: { _ in false })
        launcher.launch = { launched.add($0) }
        launcher.settle = 0
        launcher.observe(change(session(), event: .sessionEnded, removed: true))
        launcher.tick(now: Date())
        Thread.sleep(forTimeInterval: 0.15)
        #expect(launched.commands.isEmpty)
    }

    @Test func storesAFinishedChatAndLooksForQuietOnesHourly() throws {
        let box = try AppSandbox()
        var config = HistoryConfig()
        config.repos["acme/widgets"] = .init(store: "/tmp/nowhere")
        try config.save(to: box.paths.historyConfig)
        let launched = Launched()
        let launcher = HistoryLauncher(paths: box.paths, isAlive: { _ in false })
        launcher.launch = { launched.add($0) }
        launcher.settle = 0

        launcher.observe(change(session("abc"), event: .sessionEnded, removed: true))
        // A chat that is only going quiet starts nothing.
        launcher.observe(change(session("def"), event: .turnCompleted(summary: nil), removed: false))
        wait(for: launched, count: 1)
        // Quiet, so a capture nobody is watching never stops on a dialog.
        #expect(launched.commands == [["history", "capture", "--session", "claude:abc", "--quiet"]])

        let now = Date()
        launcher.tick(now: now)
        launcher.tick(now: now.addingTimeInterval(60))
        wait(for: launched, count: 2)
        Thread.sleep(forTimeInterval: 0.1)
        #expect(launched.commands.count == 2)
        #expect(launched.commands.last == ["history", "capture", "--due", "--quiet"])
        launcher.tick(now: now.addingTimeInterval(HistoryLauncher.scanInterval + 1))
        wait(for: launched, count: 3)
        #expect(launched.commands.count == 3)
    }

    private func setUp(_ box: AppSandbox) throws {
        var config = HistoryConfig()
        config.repos["acme/widgets"] = .init(store: "/tmp/nowhere")
        try config.save(to: box.paths.historyConfig)
    }

    @Test func theAppHandsOverAChatWhenItsSessionEnds() throws {
        let box = try AppSandbox()
        try setUp(box)
        let launched = Launched()
        let launcher = HistoryLauncher(paths: box.paths, isAlive: { _ in false })
        launcher.launch = { launched.add($0) }
        launcher.settle = 0
        // The app's own model, with the launcher the app delegate would give it.
        let model = AppModel(prefs: box.preferences(), stateURL: nil, history: launcher)
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .sessionStarted))
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .promptSubmitted))
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .turnCompleted(summary: "done")))
        Thread.sleep(forTimeInterval: 0.1)
        // A finished turn isn't a finished chat.
        #expect(launched.commands.isEmpty)
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .sessionEnded))
        wait(for: launched, count: 1)
        #expect(launched.commands == [["history", "capture", "--session", "claude:abc", "--quiet"]])
    }

    @Test func runsTheCommandLineToolAndKeepsALog() throws {
        let box = try AppSandbox()
        try setUp(box)
        // Stands in for the bundled tool: writes down how it was called and says something on both streams.
        let record = box.root.appendingPathComponent("called.txt")
        try FileManager.default.createDirectory(at: box.paths.binDir, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(record.path)'\necho \"NO_COLOR=$NO_COLOR\" >> '\(record.path)'\n"
            + "echo stored one chat\necho a warning >&2\n"
        try Data(script.utf8).write(to: box.paths.cliLink)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.paths.cliLink.path)

        // The launcher as the app makes it: nothing replaced but the wait.
        let launcher = HistoryLauncher(paths: box.paths, isAlive: { _ in false })
        launcher.settle = 0
        launcher.observe(change(session("abc"), event: .sessionEnded, removed: true))
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: record.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        Thread.sleep(forTimeInterval: 0.2)
        let called = try String(contentsOf: record, encoding: .utf8)
        #expect(called == "history\ncapture\n--session\nclaude:abc\n--quiet\nNO_COLOR=1\n")
        let log = try String(contentsOf: box.paths.logs.appendingPathComponent("history.log"), encoding: .utf8)
        #expect(log.contains("ambient history capture --session claude:abc --quiet"))
        #expect(log.contains("stored one chat") && log.contains("a warning"))
    }

    @Test func withoutTheToolItDoesNothingAndDoesNotFail() throws {
        let box = try AppSandbox()
        try setUp(box)
        let launcher = HistoryLauncher(paths: box.paths, isAlive: { _ in false })
        launcher.settle = 0
        launcher.observe(change(session("abc"), event: .sessionEnded, removed: true))
        Thread.sleep(forTimeInterval: 0.2)
        #expect(!FileManager.default.fileExists(atPath: box.paths.logs.appendingPathComponent("history.log").path))
    }

    @Test func anAppModelInATestHasNoLauncherAtAll() throws {
        let box = try AppSandbox()
        // Built the way every test builds it: ending a session there can't start a capture of the real home's chats.
        let model = AppModel(prefs: box.preferences(), stateURL: nil)
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .sessionStarted))
        model.apply(AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/api", kind: .sessionEnded))
        #expect(model.sessions.isEmpty)
    }
}
