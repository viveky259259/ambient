import Foundation

/// A turn that finished today: a star, a moored boat or a flower in the day's build-up.
public struct DayMark: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case done, failed }

    public let agent: AgentKind
    public let outcome: Outcome
    public let at: Date

    public init(agent: AgentKind, outcome: Outcome, at: Date) {
        self.agent = agent
        self.outcome = outcome
        self.at = at
    }
}

/// A moment on the day's timeline. Never free text: only what happened, where and when.
public struct DayMoment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case neededYou, done, failed }

    public let kind: Kind
    public let agent: AgentKind
    /// The session's title, else its project, else the agent's name.
    public let place: String
    public let at: Date

    public init(kind: Kind, agent: AgentKind, place: String, at: Date) {
        self.kind = kind
        self.agent = agent
        self.place = place
        self.at = at
    }
}

/// Today's story, folded from session changes: totals, finished turns and recent moments.
public struct DayLog: Codable, Equatable, Sendable {
    public static let maxMarks = 40
    public static let maxMoments = 20

    /// Local midnight that starts the day this log covers.
    public private(set) var day: Date
    /// Time spent in turns that finished today; `agentTime(live:now:)` adds turns still running.
    public private(set) var finishedSeconds: TimeInterval = 0
    public private(set) var tools = 0
    public private(set) var turnsDone = 0
    public private(set) var turnsFailed = 0
    public private(set) var neededYou = 0
    public private(set) var projects: [String] = []
    public private(set) var longestRun: TimeInterval = 0
    /// Oldest first, at most `maxMarks`.
    public private(set) var marks: [DayMark] = []
    /// Newest first, at most `maxMoments`.
    public private(set) var moments: [DayMoment] = []

    public init(now: Date, calendar: Calendar = .current) {
        day = calendar.startOfDay(for: now)
    }

    /// Starts a fresh day when `now` is past this one. Returns whether it did.
    @discardableResult
    public mutating func rollOver(now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.startOfDay(for: now) > day else { return false }
        self = DayLog(now: now, calendar: calendar)
        return true
    }

    /// Counts what a change says happened. Demo sessions and sweeps (no event) don't count.
    public mutating func apply(_ change: SessionChange, now: Date, calendar: Calendar = .current) {
        rollOver(now: now, calendar: calendar)
        let s = change.session
        guard let event = change.event, !s.sessionId.hasPrefix("demo-") else { return }
        if let project = s.project, !projects.contains(project) {
            projects.append(project)
            projects.sort()
        }
        switch event {
        case .toolStarted:
            tools += 1
        case .needsInput:
            if case .waiting? = change.previous { return }
            neededYou += 1
            remember(.neededYou, s)
        case .turnCompleted:
            turnsDone += 1
            finish(s, .done)
        case .turnFailed:
            turnsFailed += 1
            finish(s, .failed)
        default:
            break
        }
    }

    /// Agent time today, including turns still running. Parallel sessions add up.
    public func agentTime(live sessions: [Session], now: Date) -> TimeInterval {
        sessions.reduce(finishedSeconds) { total, s in
            guard !s.sessionId.hasPrefix("demo-"), s.activity.isBusy,
                  let start = s.turnStartedAt, s.turnEndedAt == nil else { return total }
            return total + max(0, now.timeIntervalSince(max(start, day)))
        }
    }

    private mutating func finish(_ s: Session, _ outcome: DayMark.Outcome) {
        if let start = s.turnStartedAt, let end = s.turnEndedAt, end >= start {
            finishedSeconds += max(0, end.timeIntervalSince(max(start, day)))
            longestRun = max(longestRun, end.timeIntervalSince(start))
        }
        marks.append(DayMark(agent: s.agent, outcome: outcome, at: s.lastEventAt))
        if marks.count > Self.maxMarks { marks.removeFirst(marks.count - Self.maxMarks) }
        remember(outcome == .done ? .done : .failed, s)
    }

    private mutating func remember(_ kind: DayMoment.Kind, _ s: Session) {
        moments.insert(DayMoment(kind: kind, agent: s.agent, place: Describe.title(s), at: s.lastEventAt), at: 0)
        if moments.count > Self.maxMoments { moments.removeLast(moments.count - Self.maxMoments) }
    }
}

/// Today's story, saved across restarts.
public enum DayLogFile {
    private struct Envelope: Codable {
        var version = 1
        var log: DayLog
    }

    public static func save(_ log: DayLog, to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(log: log))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// What was saved, or nil if the file is missing, corrupt or from another version.
    public static func load(from url: URL) -> DayLog? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return nil }
        return envelope.log
    }
}

extension AmbientPaths {
    public var dayFile: URL { home.appendingPathComponent("day.json") }
}
