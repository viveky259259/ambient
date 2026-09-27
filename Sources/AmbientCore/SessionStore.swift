import Foundation

/// Folds agent events into per-session state. Not thread-safe: own it from one queue.
public final class SessionStore {
    public struct Timeouts: Sendable {
        /// A busy session with no events for this long was probably interrupted or killed.
        public var busy: TimeInterval = 600
        /// Give up on a prompt nobody answered (it may have been dismissed with Esc).
        public var waiting: TimeInterval = 1_800
        /// Results nobody looked at stop asking for attention.
        public var unacknowledged: TimeInterval = 3_600
        /// Quiet sessions are forgotten.
        public var expire: TimeInterval = 7_200

        public init() {}
    }

    public var timeouts: Timeouts
    private let isAlive: (Int32) -> Bool
    private var byId: [String: Session] = [:]

    public init(timeouts: Timeouts = Timeouts(), isAlive: @escaping (Int32) -> Bool = SessionStore.processExists) {
        self.timeouts = timeouts
        self.isAlive = isAlive
    }

    /// Sessions, most urgent first, then most recent.
    public var sessions: [Session] {
        byId.values.sorted {
            if $0.mood != $1.mood { return $0.mood > $1.mood }
            if $0.lastEventAt != $1.lastEventAt { return $0.lastEventAt > $1.lastEventAt }
            return $0.id < $1.id
        }
    }

    public var mood: Mood { byId.values.map(\.mood).max() ?? .idle }
    public var busyCount: Int { byId.values.filter { $0.activity.isBusy }.count }
    public var waitingCount: Int { byId.values.filter { $0.mood == .waiting }.count }

    public func session(id: String) -> Session? { byId[id] }

    @discardableResult
    public func apply(_ e: AgentEvent) -> SessionChange? {
        let id = "\(e.agent.rawValue):\(e.sessionId)"
        let existing = byId[id]
        if let existing, e.timestamp < existing.lastEventAt { return nil }

        var s = existing ?? Session(agent: e.agent, sessionId: e.sessionId, at: e.timestamp)
        let previous = existing?.activity
        if let cwd = e.cwd, !cwd.isEmpty { s.cwd = cwd }
        if let host = e.host { s.host = host }
        s.lastEventAt = e.timestamp

        if e.kind == .sessionEnded {
            byId[id] = nil
            return SessionChange(session: s, previous: previous, event: e.kind, removed: true)
        }

        reduce(&s, e.kind, at: e.timestamp)
        if s.activity != previous { s.activitySince = e.timestamp }
        byId[id] = s
        return SessionChange(session: s, previous: previous, event: e.kind, removed: false)
    }

    private func reduce(_ s: inout Session, _ kind: EventKind, at date: Date) {
        switch kind {
        case .sessionStarted, .notice, .sessionEnded:
            break
        case .promptSubmitted:
            s.activity = .thinking
            s.turnStartedAt = date
            s.turnEndedAt = nil
            s.toolCount = 0
            s.acknowledged = false
        case let .toolStarted(name, detail):
            if s.turnStartedAt == nil || s.turnEndedAt != nil { startTurn(&s, at: date) }
            s.activity = .tool(name: name, detail: detail)
            s.toolCount += 1
        case .toolFinished:
            if s.turnStartedAt == nil || s.turnEndedAt != nil { startTurn(&s, at: date) }
            s.activity = .thinking
        case let .needsInput(reason, message):
            if case .waiting = s.activity {} else { s.acknowledged = false }
            s.activity = .waiting(reason: reason, message: message)
        case .compactStarted:
            if s.activity != .compacting { s.beforeCompaction = s.activity }
            s.activity = .compacting
        case .compactFinished:
            let before = s.beforeCompaction ?? .thinking
            s.activity = before.isBusy || before == .compacting ? .thinking : before
            s.beforeCompaction = nil
        case .subagentStarted:
            s.subagents += 1
        case .subagentFinished:
            s.subagents = max(0, s.subagents - 1)
        case let .turnCompleted(summary):
            s.activity = .done(summary: summary)
            finishTurn(&s, at: date)
        case let .turnFailed(message):
            s.activity = .error(message: message)
            finishTurn(&s, at: date)
        }
    }

    private func startTurn(_ s: inout Session, at date: Date) {
        s.turnStartedAt = date
        s.turnEndedAt = nil
        s.toolCount = 0
        s.acknowledged = false
    }

    private func finishTurn(_ s: inout Session, at date: Date) {
        s.turnEndedAt = date
        s.subagents = 0
        s.acknowledged = false
    }

    /// Names a session; returns whether anything changed. Titles never alter state or timing.
    @discardableResult
    public func setTitle(_ title: String?, sessionID: String) -> Bool {
        guard var s = byId[sessionID], s.title != title else { return false }
        s.title = title
        byId[sessionID] = s
        return true
    }

    /// Marks a session's result or prompt as seen. Returns true if that lowered its mood.
    @discardableResult
    public func acknowledge(sessionID: String) -> Bool {
        guard var s = byId[sessionID], !s.acknowledged, [.done, .error, .waiting].contains(s.mood) else { return false }
        s.acknowledged = true
        byId[sessionID] = s
        return true
    }

    /// Marks every session hosted by an app as seen, e.g. when the user switches to it.
    @discardableResult
    public func acknowledge(hostBundleId: String) -> [String] {
        let ids = byId.values.filter { $0.host?.bundleId == hostBundleId }.map(\.id).sorted()
        return ids.filter { acknowledge(sessionID: $0) }
    }

    /// Ages sessions out. Call periodically.
    @discardableResult
    public func sweep(now: Date) -> [SessionChange] {
        var changes: [SessionChange] = []
        for (id, var s) in byId {
            let quiet = now.timeIntervalSince(s.lastEventAt)
            let previous = s.activity

            if let pid = s.host?.agentPid, !isAlive(pid) {
                byId[id] = nil
                changes.append(SessionChange(session: s, previous: previous, event: nil, removed: true))
                continue
            }

            if s.activity.isBusy, quiet > timeouts.busy {
                s.activity = .idle
            } else if case .waiting = s.activity, quiet > timeouts.waiting {
                s.activity = .idle
            } else if !s.acknowledged, s.mood == .done || s.mood == .error, quiet > timeouts.unacknowledged {
                s.acknowledged = true
            } else if s.mood == .idle, quiet > timeouts.expire {
                byId[id] = nil
                changes.append(SessionChange(session: s, previous: previous, event: nil, removed: true))
                continue
            }

            if s != byId[id] {
                if s.activity != previous { s.activitySince = now }
                byId[id] = s
                changes.append(SessionChange(session: s, previous: previous, event: nil, removed: false))
            }
        }
        return changes
    }

    /// Replaces all state, e.g. when restoring. Used by tests and the app's status snapshot.
    public func load(_ sessions: [Session]) {
        byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    public static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
