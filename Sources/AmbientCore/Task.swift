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
