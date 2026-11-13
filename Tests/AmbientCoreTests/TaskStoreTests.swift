import Foundation
import Testing
@testable import AmbientCore

@Suite struct TaskStoreTests {
    @Test func needsYouBecomesBlocked() {
        let store = TaskStore()
        var session = liveSession(agent: .codex, id: "c1", cwd: "/src/app")
        session.activity = .waiting(reason: "permission", message: "ok?")
        let change = SessionChange(session: session, previous: .thinking,
                                   event: .needsInput(reason: "permission", message: "ok?"), removed: false)
        let task = store.observe(change)
        #expect(task?.status == TaskStatus.blocked)
        #expect(task?.project == "app")
        #expect(task?.agents == [AgentKind.codex])
    }

    @Test func sameProjectSameDayGroups() {
        let store = TaskStore()
        let now = Date()
        let a = liveSession(agent: .codex, id: "a", cwd: "/src/web", title: "Ship board")
        _ = store.observe(SessionChange(session: a, previous: nil, event: .promptSubmitted, removed: false), now: now)
        var b = liveSession(agent: .cursor, id: "b", cwd: "/src/web", title: "Ship board")
        b.activity = .thinking
        let second = store.observe(SessionChange(session: b, previous: nil, event: .promptSubmitted, removed: false), now: now)
        #expect(store.tasks.count == 1)
        #expect(second?.sessionIds.contains("codex:a") == true)
        #expect(second?.sessionIds.contains("cursor:b") == true)
        #expect(second?.agents.contains(.codex) == true)
        #expect(second?.agents.contains(.cursor) == true)
    }

    @Test func manualUpsertWinsTitle() {
        let store = TaskStore()
        let saved = store.upsert(AgentTask(title: "Manual name", status: .inProgress, project: "app", manual: true))
        var linked = saved
        linked.sessionIds = ["codex:x"]
        let again = store.upsert(linked)
        #expect(again.title == "Manual name")
        #expect(again.manual)
        #expect(again.sessionIds == ["codex:x"])
    }

    @Test func persistRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("tasks.json")
        let tasks = [AgentTask(title: "One", status: .blocked, project: "app", agents: [.codex])]
        try TaskFile.save(tasks, to: url)
        let loaded = TaskFile.load(from: url)
        #expect(loaded.count == 1)
        #expect(loaded[0].title == "One")
        #expect(loaded[0].status == TaskStatus.blocked)
    }

    @Test func finishedTasksAgeOffTheBoard() {
        let store = TaskStore()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let s = liveSession(agent: .claude, id: "old", cwd: "/src/old")
        let old = store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false), now: start)
        store.observe(SessionChange(session: s, previous: nil, event: .sessionEnded, removed: true), now: start)
        let live = liveSession(agent: .claude, id: "live", cwd: "/src/live")
        let running = store.observe(SessionChange(session: live, previous: nil, event: .promptSubmitted, removed: false), now: start)
        let mine = store.upsert(AgentTask(title: "Mine", status: .backlog), at: start)

        #expect(!store.prune(now: start.addingTimeInterval(store.retention - 60)))
        #expect(store.prune(now: start.addingTimeInterval(store.retention + 60)))
        #expect(store.task(id: old!.id) == nil)
        // A running session's task and the user's own stay, however old.
        #expect(store.task(id: running!.id) != nil)
        #expect(store.task(id: mine.id) != nil)
    }

    @Test func aLateSummaryDoesntReopenAFinishedTask() throws {
        let store = TaskStore()
        let s = liveSession(agent: .claude, id: "a", cwd: "/src/app")
        let task = try #require(store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false)))
        store.observe(SessionChange(session: s, previous: nil, event: .sessionEnded, removed: true))
        let after = try #require(store.applySemantics(TaskSemantics(title: "Ship it", summary: "Working", status: .inProgress),
                                                      toTaskID: task.id))
        #expect(after.status == .done)
        #expect(after.title == "Ship it")
    }

    @Test func pruneUnlinksSessionsThatAreGoneAndSettlesOrphans() throws {
        let store = TaskStore()
        let now = Date()
        let s = liveSession(agent: .claude, id: "gone", cwd: "/src/app")
        let task = try #require(store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false), now: now))
        // Saved by an older version: in progress with nothing linked.
        var orphan = AgentTask(title: "Orphan", status: .inProgress, createdAt: now, updatedAt: now)
        orphan.summarySource = .localLLM
        store.load(store.tasks + [orphan])

        #expect(store.prune(liveSessionIDs: [], now: now))
        #expect(store.task(id: task.id)?.sessionIds.isEmpty == true)
        #expect(store.task(id: task.id)?.status == .done)
        #expect(store.task(id: orphan.id)?.status == .done)
        #expect(!store.prune(liveSessionIDs: [], now: now))
    }

    @Test func thisMacsTasksHaveALimitToo() {
        let store = TaskStore()
        store.machineTaskLimit = 3
        let start = Date()
        for i in 0..<5 {
            let s = liveSession(agent: .claude, id: "s\(i)", cwd: "/src/p\(i)")
            store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false),
                          now: start.addingTimeInterval(Double(i)))
        }
        #expect(store.tasks.map(\.project) == ["p4", "p3", "p2"])
    }

    @Test func tasksStaySortedAsTheyChange() throws {
        let store = TaskStore()
        let now = Date()
        let a = liveSession(agent: .claude, id: "a", cwd: "/src/a")
        let b = liveSession(agent: .claude, id: "b", cwd: "/src/b")
        store.observe(SessionChange(session: a, previous: nil, event: .promptSubmitted, removed: false), now: now)
        store.observe(SessionChange(session: b, previous: nil, event: .promptSubmitted, removed: false), now: now.addingTimeInterval(1))
        #expect(store.tasks.map(\.project) == ["b", "a"])
        store.observe(SessionChange(session: a, previous: nil, event: .toolStarted(name: "Bash", detail: nil), removed: false), now: now.addingTimeInterval(2))
        #expect(store.tasks.map(\.project) == ["a", "b"])
    }

    @Test func anEndedTasksChatStillOpens() throws {
        let store = TaskStore()
        var s = liveSession(agent: .claude, id: "c1", cwd: "/Users/me/src/app")
        s.host = HostInfo(bundleId: "com.anthropic.claudefordesktop", pids: [4242], agentPid: 4243, tty: "/dev/ttys004",
                          hostSessionId: "local_abc-123", tmuxPane: "%3")
        let task = try #require(store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false)))
        store.observe(SessionChange(session: s, previous: nil, event: .sessionEnded, removed: true))
        #expect(store.task(id: task.id)?.sessionIds.isEmpty == true)

        let chat = try #require(store.endedChat(forTaskID: task.id))
        #expect(chat.id == "claude:c1")
        #expect(chat.cwd == "/Users/me/src/app")
        // A terminal, pane or process from a session that's over could be someone else's now.
        #expect(chat.host?.tty == nil)
        #expect(chat.host?.tmuxPane == nil)
        #expect(chat.host?.pids.isEmpty == true)
        #expect(FocusPlanner.routes(for: chat, userHome: "/Users/me").first
            == .openURL("claude://code/continue?session=local_abc-123&source=ambient"))
    }

    @Test func aRemoteTasksChatIsntOpenedHere() throws {
        let store = TaskStore()
        let s = liveSession(agent: .claude, id: "r1", cwd: "/src/api")
        var task = try #require(store.observe(SessionChange(session: s, previous: nil, event: .promptSubmitted, removed: false)))
        task.machine = MachineRef(id: "devbox", label: "devbox")
        store.upsert(task)
        #expect(store.endedChat(forTaskID: task.id) == nil)
    }

    @Test func aBoardSavedBeforeChatsWereKeptStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = #"{"version":1,"tasks":[{"id":"task-1","title":"Old","status":"done","summarySource":"heuristic","agents":["claude"],"sessionIds":[],"manual":false,"createdAt":800000000,"updatedAt":800000000}]}"#
        try Data(old.utf8).write(to: url)
        let tasks = TaskFile.load(from: url)
        #expect(tasks.count == 1)
        #expect(tasks.first?.lastChat == nil)
    }

    @Test func searchFindsTasksByWhatsWrittenOnThem() {
        var fix = AgentTask(title: "Fix the login", project: "api", cwd: "/src/api", agents: [.codex])
        fix.summary = "Token refresh fails after sleep"
        var remote = AgentTask(title: "Résumé parser", project: "cv", agents: [.claude])
        remote.machine = MachineRef(id: "devbox", label: "Devbox")
        let tasks = [fix, remote]

        #expect(TaskSearch.filter(tasks, query: "").count == 2)
        #expect(TaskSearch.filter(tasks, query: "   ").count == 2)
        #expect(TaskSearch.filter(tasks, query: "API fix").map(\.id) == [fix.id])
        #expect(TaskSearch.filter(tasks, query: "refresh").map(\.id) == [fix.id])
        #expect(TaskSearch.filter(tasks, query: "codex").map(\.id) == [fix.id])
        #expect(TaskSearch.filter(tasks, query: "resume").map(\.id) == [remote.id])
        #expect(TaskSearch.filter(tasks, query: "devbox").map(\.id) == [remote.id])
        #expect(TaskSearch.filter(tasks, query: "fix devbox").isEmpty)
    }

    private func liveSession(agent: AgentKind, id: String, cwd: String, title: String? = nil) -> Session {
        var s = Session(agent: agent, sessionId: id, at: Date())
        s.cwd = cwd
        s.title = title
        s.activity = .thinking
        return s
    }
}

@Suite struct TaskBoardColumnTests {
    @Test func columnsFollowBoardOrderAndSkipEmptyOnes() {
        let tasks = [AgentTask(title: "a", status: .done), AgentTask(title: "b", status: .blocked),
                     AgentTask(title: "c", status: .done)]
        let columns = TaskBoardColumn.columns(tasks)
        #expect(columns.map(\.status) == [.blocked, .done])
        #expect(columns.map(\.total) == [1, 2])
        #expect(columns[1].tasks.map(\.title) == ["a", "c"])
    }

    @Test func limitKeepsTheFirstTasksAndCountsTheRest() {
        let tasks = (0..<5).map { AgentTask(title: "done \($0)", status: .done) }
            + [AgentTask(title: "working", status: .inProgress)]
        let columns = TaskBoardColumn.columns(tasks, limit: 2)
        #expect(columns.map(\.status) == [.inProgress, .done])
        #expect(columns[1].tasks.map(\.title) == ["done 0", "done 1"])
        #expect(columns[1].total == 5)
        #expect(columns[0].tasks.count == 1)
        #expect(columns[0].total == 1)
    }

    @Test func noTasksNoColumns() {
        #expect(TaskBoardColumn.columns([]).isEmpty)
    }
}
