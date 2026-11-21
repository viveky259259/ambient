import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA TaskStatus")
struct QATaskStatusTests {
    @Test func rawValuesAreTheWireNames() {
        #expect(TaskStatus.allCases.map(\.rawValue) == ["backlog", "inProgress", "blocked", "done", "cancelled"])
    }

    @Test(arguments: [(TaskStatus.backlog, "Backlog"), (.inProgress, "In progress"), (.blocked, "Blocked"),
                      (.done, "Done"), (.cancelled, "Cancelled")])
    func displayNames(status: TaskStatus, name: String) {
        #expect(status.displayName == name)
    }

    @Test func boardOrderHoldsEveryStatusOnce() {
        #expect(TaskStatus.boardOrder == [.blocked, .inProgress, .backlog, .done, .cancelled])
        #expect(Set(TaskStatus.boardOrder) == Set(TaskStatus.allCases))
        #expect(TaskStatus.boardOrder.count == TaskStatus.allCases.count)
    }

    @Test(arguments: ["in_progress", "InProgress", "archived", "", "DONE"])
    func unknownStatusesDoNotDecode(raw: String) {
        #expect(throws: DecodingError.self) { try QA.decode(TaskStatus.self, "\"\(raw)\"") }
    }

    @Test func summarySourceRawValues() throws {
        #expect(try QA.decode([TaskSummarySource].self, #"["heuristic","localLLM","manual"]"#)
            == [.heuristic, .localLLM, .manual])
        #expect(throws: DecodingError.self) { try QA.decode(TaskSummarySource.self, #""llm""#) }
    }
}

@Suite("QA TaskSemantics")
struct QATaskSemanticsTests {
    @Test func defaultsAreEmpty() {
        let s = TaskSemantics()
        #expect(s.title == nil && s.summary == nil && s.status == nil)
        #expect(s == TaskSemantics(title: nil, summary: nil, status: nil))
    }

    @Test func storesAndComparesEveryField() {
        let a = TaskSemantics(title: "T", summary: "S", status: .blocked)
        #expect(a.title == "T" && a.summary == "S" && a.status == .blocked)
        #expect(a != TaskSemantics(title: "T", summary: "S", status: .done))
        #expect(a != TaskSemantics(title: "T", summary: nil, status: .blocked))
        #expect(a != TaskSemantics(title: "t", summary: "S", status: .blocked))
        var b = a
        b.status = nil
        #expect(b != a)
    }
}

@Suite("QA AgentTask")
struct QAAgentTaskTests {
    static func task(_ title: String = "Fix login", status: TaskStatus = .backlog, summary: String? = nil,
                     project: String? = nil, cwd: String? = nil, agents: [AgentKind] = [],
                     machine: MachineRef? = nil, id: String = "task-x") -> AgentTask {
        AgentTask(id: id, title: title, status: status, summary: summary, project: project, cwd: cwd, agents: agents,
                  createdAt: QA.t0, updatedAt: QA.t0, machine: machine)
    }

    @Test func makeIDFormat() {
        for _ in 0..<200 {
            let id = AgentTask.makeID()
            #expect(id.hasPrefix("task-"))
            let suffix = id.dropFirst(5)
            #expect(suffix.count == 8)
            #expect(suffix.allSatisfy { "0123456789abcdef".contains($0) }, "\(id)")
        }
    }

    @Test func makeIDIsUniqueInPractice() {
        let ids = (0..<500).map { _ in AgentTask.makeID() }
        #expect(Set(ids).count == ids.count)
    }

    @Test func defaultInitUsesAFreshIdAndEmptyFields() {
        let a = AgentTask(title: "A", createdAt: QA.t0, updatedAt: QA.t0)
        let b = AgentTask(title: "A", createdAt: QA.t0, updatedAt: QA.t0)
        #expect(a.id != b.id)
        #expect(a.status == .backlog && a.summarySource == .heuristic && !a.manual)
        #expect(a.agents.isEmpty && a.sessionIds.isEmpty)
        #expect(a.summary == nil && a.summarizedAt == nil && a.project == nil && a.cwd == nil)
        #expect(a.lastSessionId == nil && a.machine == nil && a.lastChat == nil)
    }

    @Test(arguments: [([AgentKind](), "—"), ([.claude], "Claude"), ([.claude, .codex], "Claude · Codex"),
                      ([.custom, .opencode, .custom], "Agent · OpenCode · Agent")])
    func agentLabel(agents: [AgentKind], label: String) {
        #expect(Self.task(agents: agents).agentLabel == label)
    }

    @Test func roundTripsEveryField() throws {
        var t = AgentTask(id: "task-1", title: "T", status: .blocked, summary: "S", summarySource: .manual,
                          summarizedAt: QA.t0, project: "p", cwd: "/w/p", agents: [.claude, .custom],
                          sessionIds: ["claude:1", "remote/m1/codex:2"], manual: true, createdAt: QA.t0,
                          updatedAt: QA.t0.addingTimeInterval(1), lastSessionId: "claude:1", machine: QA.machine)
        t.lastChat = TaskChat(agent: .claude, sessionId: "1", host: HostInfo(bundleId: "b", hostSessionId: "h"))
        #expect(try QA.roundTrip(t) == t)
    }

    @Test func olderTasksWithoutMachineOrChatDecode() throws {
        let json = #"""
        {"id":"task-old","title":"Old","status":"done","summarySource":"heuristic","agents":["codex"],
         "sessionIds":[],"manual":false,"createdAt":0,"updatedAt":0}
        """#
        let t = try QA.decode(AgentTask.self, json)
        #expect(t.machine == nil && t.lastChat == nil && t.summary == nil && t.project == nil)
        #expect(t.status == .done && t.agents == [.codex])
    }

    @Test(arguments: ["id", "title", "status", "summarySource", "agents", "sessionIds", "manual", "createdAt",
                      "updatedAt"])
    func requiredTaskFields(key: String) throws {
        let data = try QA.edited(Self.task()) { $0.removeValue(forKey: key) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AgentTask.self, from: data) }
    }

    @Test func unknownKeysAreIgnoredButUnknownStatusIsNot() throws {
        let extra = try QA.edited(Self.task()) { $0["priority"] = 3 }
        #expect(try JSONDecoder().decode(AgentTask.self, from: extra) == Self.task())
        let status = try QA.edited(Self.task()) { $0["status"] = "archived" }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AgentTask.self, from: status) }
    }
}

@Suite("QA TaskChat")
struct QATaskChatTests {
    static let fullHost = HostInfo(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal", pids: [1, 2],
                                   agentPid: 3, appServer: true, tty: "/dev/ttys001", hostSessionId: "h-1",
                                   tmuxSocket: "/s", tmuxPane: "%1", cmuxWorkspace: "w", cmuxSurface: "s",
                                   cmuxSocket: "/c")

    @Test func keepsOnlyWhatOutlivesTheProcess() {
        let chat = TaskChat(agent: .claude, sessionId: "s", host: Self.fullHost)
        #expect(chat.host == HostInfo(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal", hostSessionId: "h-1"))
        #expect(chat.host?.pids == [] && chat.host?.agentPid == nil && chat.host?.tty == nil)
        #expect(chat.host?.tmuxPane == nil && chat.host?.cmuxSocket == nil && chat.host?.appServer == nil)
    }

    @Test func nilHostStaysNil() {
        #expect(TaskChat(agent: .codex, sessionId: "s", host: nil).host == nil)
    }

    @Test func fromSession() {
        var s = QA.session(.cursor, id: "c-1")
        s.host = Self.fullHost
        let chat = TaskChat(s)
        #expect(chat.agent == .cursor && chat.sessionId == "c-1")
        #expect(chat.host?.bundleId == "com.apple.Terminal" && chat.host?.tty == nil)
        #expect(TaskChat(QA.session(origin: QA.origin())).host == nil)
    }

    @Test func roundTrips() throws {
        let chat = TaskChat(agent: .gemini, sessionId: "g", host: Self.fullHost)
        #expect(try QA.roundTrip(chat) == chat)
    }
}

@Suite("QA TaskBoardColumn")
struct QATaskBoardColumnTests {
    static func tasks(_ statuses: [TaskStatus]) -> [AgentTask] {
        statuses.enumerated().map { QAAgentTaskTests.task("t\($0.offset)", status: $0.element, id: "task-\($0.offset)") }
    }

    @Test func emptyBoardHasNoColumns() {
        #expect(TaskBoardColumn.columns([]).isEmpty)
    }

    @Test func columnsFollowBoardOrderAndSkipEmptyOnes() {
        let cols = TaskBoardColumn.columns(Self.tasks([.done, .backlog, .blocked, .done]))
        #expect(cols.map(\.status) == [.blocked, .backlog, .done])
        #expect(cols.map(\.total) == [1, 1, 2])
        #expect(cols.map(\.id) == cols.map(\.status))
        #expect(cols[2].tasks.map(\.id) == ["task-0", "task-3"], "tasks keep the order they came in")
    }

    @Test func limitCapsDrawnTasksButNotTotals() {
        let cols = TaskBoardColumn.columns(Self.tasks(Array(repeating: .inProgress, count: 5) + [.cancelled]), limit: 2)
        #expect(cols.map(\.status) == [.inProgress, .cancelled])
        #expect(cols[0].total == 5 && cols[0].tasks.map(\.id) == ["task-0", "task-1"])
        #expect(cols[1].total == 1 && cols[1].tasks.count == 1)
    }

    @Test(arguments: [0, -1])
    func zeroOrNegativeLimitStillCounts(limit: Int) {
        let cols = TaskBoardColumn.columns(Self.tasks([.done, .done]), limit: limit)
        #expect(cols.count == 1 && cols[0].total == 2 && cols[0].tasks.isEmpty)
    }

    @Test func everyStatusGetsAColumn() {
        let cols = TaskBoardColumn.columns(Self.tasks(TaskStatus.allCases))
        #expect(cols.map(\.status) == TaskStatus.boardOrder)
        #expect(cols.allSatisfy { $0.total == 1 })
    }
}

@Suite("QA TaskSearch")
struct QATaskSearchTests {
    static let board: [AgentTask] = [
        QAAgentTaskTests.task("Fix the login", status: .inProgress, project: "api", agents: [.claude], id: "task-a"),
        QAAgentTaskTests.task("Café menu", summary: "Résumé page tweaks", cwd: "/w/site", id: "task-b"),
        QAAgentTaskTests.task("Ship release", status: .blocked, agents: [.codex, .gemini], machine: QA.machine,
                              id: "task-c"),
    ]

    func ids(_ query: String) -> [String] { TaskSearch.filter(Self.board, query: query).map(\.id) }

    @Test(arguments: ["", "   ", "\n\t"])
    func blankQueryReturnsEverything(query: String) {
        #expect(ids(query) == ["task-a", "task-b", "task-c"])
    }

    @Test(arguments: [
        ("api fix", ["task-a"]), ("FIX API", ["task-a"]), ("login   the", ["task-a"]),
        ("cafe", ["task-b"]), ("RESUME", ["task-b"]), ("café", ["task-b"]), ("site", ["task-b"]),
        ("studio", ["task-c"]), ("codex gemini", ["task-c"]), ("blocked", ["task-c"]),
        ("in progress", ["task-a"]), ("backlog", ["task-b"]), ("claude", ["task-a"]),
        ("—", ["task-b"]), ("ＡＰＩ", ["task-a"]), ("fix release", []), ("zzz", []), ("e", ["task-a", "task-b", "task-c"]),
    ] as [(String, [String])])
    func everyWordMustMatchSomewhere(query: String, expected: [String]) {
        #expect(ids(query) == expected)
    }

    @Test func emptyBoard() {
        #expect(TaskSearch.filter([], query: "x").isEmpty)
        #expect(TaskSearch.filter([], query: "").isEmpty)
    }
}
