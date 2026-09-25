import Foundation

/// What a session is doing right now.
public enum Activity: Codable, Equatable, Sendable {
    case idle
    case thinking
    case tool(name: String, detail: String?)
    case compacting
    case waiting(reason: String, message: String?)
    case done(summary: String?)
    case error(message: String?)

    public var isBusy: Bool {
        switch self {
        case .thinking, .tool, .compacting: true
        default: false
        }
    }
}

/// How much a session wants the user's attention. Higher wins.
public enum Mood: Int, Codable, Comparable, CaseIterable, Sendable {
    case idle = 0
    case working = 2
    case done = 3
    case error = 4
    case waiting = 5

    public static func < (a: Mood, b: Mood) -> Bool { a.rawValue < b.rawValue }
}

public struct Session: Identifiable, Codable, Equatable, Sendable {
    /// "agent:sessionId", unique across agents.
    public let id: String
    public let agent: AgentKind
    public let sessionId: String
    public var cwd: String?
    public var host: HostInfo?
    public var activity: Activity
    public var activitySince: Date
    public var lastEventAt: Date
    public var turnStartedAt: Date?
    public var turnEndedAt: Date?
    public var toolCount: Int
    public var subagents: Int
    /// The user has seen the latest result or prompt (done, error or waiting).
    public var acknowledged: Bool
    /// What compaction interrupted, to return to afterwards.
    var beforeCompaction: Activity?

    public init(agent: AgentKind, sessionId: String, at date: Date) {
        self.id = "\(agent.rawValue):\(sessionId)"
        self.agent = agent
        self.sessionId = sessionId
        self.activity = .idle
        self.activitySince = date
        self.lastEventAt = date
        self.toolCount = 0
        self.subagents = 0
        self.acknowledged = false
    }

    public var project: String? {
        AgentEvent(agent: agent, sessionId: sessionId, cwd: cwd, kind: .sessionStarted).project
    }

    public var mood: Mood {
        switch activity {
        // A prompt the user has looked at: they've probably answered it and the agent is running again.
        case .waiting: acknowledged ? .working : .waiting
        case .error: acknowledged ? .idle : .error
        case .done: acknowledged ? .idle : .done
        case .thinking, .tool, .compacting: .working
        case .idle: .idle
        }
    }

    /// How long the last finished turn took.
    public var turnDuration: TimeInterval? {
        guard let start = turnStartedAt, let end = turnEndedAt, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }

    /// How long the current turn has been running, or the last one ran.
    public func elapsed(now: Date) -> TimeInterval? {
        guard let start = turnStartedAt else { return nil }
        return max(0, (turnEndedAt ?? now).timeIntervalSince(start))
    }
}

/// The result of applying an event, for surfaces that react to changes.
public struct SessionChange: Equatable, Sendable {
    public let session: Session
    /// The activity before the event; nil for a session seen for the first time.
    public let previous: Activity?
    public let event: EventKind?
    public let removed: Bool

    public init(session: Session, previous: Activity?, event: EventKind?, removed: Bool) {
        self.session = session
        self.previous = previous
        self.event = event
        self.removed = removed
    }

    public var changed: Bool { previous != session.activity || removed }
    public var previousMood: Mood? {
        guard let previous else { return nil }
        var s = session
        s.activity = previous
        return s.mood
    }
}
