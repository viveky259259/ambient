import Foundation

/// Where a unit of work sits on the agent task board.
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case inProgress
    case blocked
    case done
    case cancelled

    public var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }

    /// Column order on the board.
    public static let boardOrder: [TaskStatus] = [.blocked, .inProgress, .backlog, .done, .cancelled]
}

/// Where a task's title/summary came from.
public enum TaskSummarySource: String, Codable, Sendable {
    case heuristic
    case localLLM
    case manual
}

/// Where a task's most recent local chat lives, kept after its session ends so the board can still open it.
/// Only what stays true once the agent has exited: a terminal, pane or process id could belong to something else by then.
public struct TaskChat: Codable, Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var host: HostInfo?

    public init(agent: AgentKind, sessionId: String, host: HostInfo?) {
        self.agent = agent
        self.sessionId = sessionId
        self.host = host.map { HostInfo(bundleId: $0.bundleId, termProgram: $0.termProgram, hostSessionId: $0.hostSessionId) }
    }

    public init(_ session: Session) {
        self.init(agent: session.agent, sessionId: session.sessionId, host: session.host)
    }
}

/// A unit of intended work, linked to one or more live agent sessions.
/// Named `AgentTask` so it never collides with Swift concurrency's `Task`.
public struct AgentTask: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var status: TaskStatus
    /// One- or two-sentence summary from the local LLM (or empty when heuristics-only).
    public var summary: String?
    public var summarySource: TaskSummarySource
    public var summarizedAt: Date?
    /// Last path component of the working directory, when known.
    public var project: String?
    public var cwd: String?
    /// Agents that have touched this task.
    public var agents: [AgentKind]
    /// `Session.id` values (`agent:sessionId`) linked to this task.
    public var sessionIds: [String]
    /// True when created or edited by the user / CLI; heuristics won't overwrite status or title.
    public var manual: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Most recently active linked session.
    public var lastSessionId: String?
    /// The remote machine this task's sessions run on; nil for local work. Tasks never mix machines.
    public var machine: MachineRef?
    /// The chat to open once no session is linked. For another machine's task, it's opened there.
    public var lastChat: TaskChat?

    public init(id: String = AgentTask.makeID(), title: String, status: TaskStatus = .backlog,
                summary: String? = nil, summarySource: TaskSummarySource = .heuristic,
                summarizedAt: Date? = nil, project: String? = nil, cwd: String? = nil,
                agents: [AgentKind] = [], sessionIds: [String] = [], manual: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), lastSessionId: String? = nil,
                machine: MachineRef? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.summary = summary
        self.summarySource = summarySource
        self.summarizedAt = summarizedAt
        self.project = project
        self.cwd = cwd
        self.agents = agents
        self.sessionIds = sessionIds
        self.manual = manual
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSessionId = lastSessionId
        self.machine = machine
    }

    public static func makeID() -> String {
        "task-\(String(UUID().uuidString.prefix(8)).lowercased())"
    }

    public var agentLabel: String {
        let names = agents.map(\.displayName)
        guard !names.isEmpty else { return "—" }
        return names.joined(separator: " · ")
    }
}

/// One column of the task board: a status, the tasks it draws, and how many it holds in all.
public struct TaskBoardColumn: Identifiable, Equatable, Sendable {
    public let status: TaskStatus
    /// The first tasks with this status, in the order they came.
    public internal(set) var tasks: [AgentTask] = []
    /// Every task with this status, drawn or not.
    public internal(set) var total = 0

    public var id: TaskStatus { status }

    /// The board's columns in board order, without empty ones, from one pass over `tasks`. Each keeps its first `limit`
    /// tasks: `TaskStore` sorts each status newest first, so those are the latest.
    public static func columns(_ tasks: [AgentTask], limit: Int = .max) -> [TaskBoardColumn] {
        var columns = TaskStatus.boardOrder.map { TaskBoardColumn(status: $0) }
        for task in tasks {
            guard let i = TaskStatus.boardOrder.firstIndex(of: task.status) else { continue }
            columns[i].total += 1
            if columns[i].tasks.count < limit { columns[i].tasks.append(task) }
        }
        return columns.filter { $0.total > 0 }
    }
}

/// Finds board tasks by what's written on them. Every word must appear somewhere, in any order, ignoring case and accents:
/// "api fix" finds *Fix the login* in project *api*.
public enum TaskSearch {
    public static func filter(_ tasks: [AgentTask], query: String) -> [AgentTask] {
        let words = terms(query)
        guard !words.isEmpty else { return tasks }
        return tasks.filter { matches($0, words: words) }
    }

    private static func matches(_ task: AgentTask, words: [String]) -> Bool {
        let text = fold([task.title, task.summary, task.project, task.cwd, task.agentLabel, task.machine?.label,
                         task.status.displayName].compactMap { $0 }.joined(separator: "\n"))
        return words.allSatisfy { text.contains($0) }
    }

    private static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
