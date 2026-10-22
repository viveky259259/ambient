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

/// A unit of intended work, linked to one or more live agent sessions.
/// Named `AgentTask` so it never collides with Swift concurrency's `Task`.
public struct AgentTask: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var status: TaskStatus
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

    public init(id: String = AgentTask.makeID(), title: String, status: TaskStatus = .backlog,
                project: String? = nil, cwd: String? = nil, agents: [AgentKind] = [],
                sessionIds: [String] = [], manual: Bool = false, createdAt: Date = Date(),
                updatedAt: Date = Date(), lastSessionId: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.project = project
        self.cwd = cwd
        self.agents = agents
        self.sessionIds = sessionIds
        self.manual = manual
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSessionId = lastSessionId
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
