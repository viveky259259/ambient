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

    private func liveSession(agent: AgentKind, id: String, cwd: String, title: String? = nil) -> Session {
        var s = Session(agent: agent, sessionId: id, at: Date())
        s.cwd = cwd
        s.title = title
        s.activity = .thinking
        return s
    }
}
