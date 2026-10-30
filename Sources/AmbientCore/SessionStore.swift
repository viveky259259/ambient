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

    /// A local hook's event, from the Unix socket.
    @discardableResult
    public func apply(_ e: AgentEvent) -> SessionChange? {
        let id = "\(e.agent.rawValue):\(e.sessionId)"
        let existing = byId[id]
        if let existing, e.timestamp < existing.lastEventAt { return nil }

        var s = existing ?? Session(agent: e.agent, sessionId: e.sessionId, at: e.timestamp)
        if let cwd = e.cwd, !cwd.isEmpty { s.cwd = cwd }
        if let host = e.host { s.host = host }
        // Only custom agents may carry a display override; hooked kinds keep AgentKind.displayName
        // (so Cursor never inherits a Codex/Claude payload name).
        if e.agent == .custom, let name = e.agentName { s.agentName = name }
        return commit(s, previous: existing?.activity, kind: e.kind, at: e.timestamp)
    }

    /// A remote machine's event, already through `RemoteEventDecoder`. Quarantined: the session is keyed by
    /// (machine, session id), ordered by `seq` rather than the remote clock, and never gets a `HostInfo`, so no
    /// focus route, pid check, tty or script ever runs for it. `date` is when to record it: the remote time, or
    /// the hub's when the clocks disagree.
    @discardableResult
    public func apply(_ e: RemoteEvent, from machine: MachineRef, at date: Date, missed: Bool = false) -> SessionChange? {
        let id = Session.remoteID(machine: machine.id, agent: e.agent, sessionId: e.session)
        let existing = byId[id]
        if let last = existing?.origin?.lastSeq, e.seq <= last { return nil }

        var s = existing ?? Session(agent: e.agent, sessionId: e.session, at: date, origin: RemoteOrigin(machine: machine))
        s.host = nil
        s.origin?.machine.label = machine.label
        s.origin?.lastSeq = e.seq
        s.origin?.unreachable = false
        if e.eventKind != nil { s.origin?.missed = missed }
        if let project = e.project { s.origin?.project = project }
        if let title = e.title { s.title = title }
        let at = max(date, existing?.lastEventAt ?? date)
        guard let kind = e.eventKind else {
            // A title change: no new state, and not worth a transition unless the name changed.
            guard existing != nil else { return nil }
            byId[id] = s
            return s.title == existing?.title ? nil : SessionChange(session: s, previous: s.activity, event: nil, removed: false)
        }
        return commit(s, previous: existing?.activity, kind: kind, at: at)
    }

    /// A batch from one machine, and whether the state must reach disk before anyone hears about it. Alerts go out
    /// only after the sessions and the cursor are saved together, so a hub killed at any point replays the events
    /// it hasn't saved: none lost, none announced twice. A batch that doesn't follow `saved` comes from a rebuilt spool,
    /// whose `seq` started over, so what the machine's sessions remember no longer compares.
    public func apply(_ batch: [RemoteDelivery], from machine: MachineRef, saved: RemoteCursor = RemoteCursor(),
                      cursor: RemoteCursor = RemoteCursor()) -> (changes: [SessionChange], saveFirst: Bool) {
        if let first = batch.first?.event.seq, saved.epoch != cursor.epoch || first <= saved.seq {
            for var s in byId.values where s.origin?.machine.id == machine.id {
                s.origin?.lastSeq = 0
                byId[s.id] = s
            }
        }
        var changes: [SessionChange] = []
        var saveFirst = false
        for delivery in batch {
            guard let change = apply(delivery.event, from: machine, at: delivery.at, missed: delivery.missed) else { continue }
            changes.append(change)
            if !change.removed, change.session.origin?.missed != true, AlertPolicy.attentionMoods.contains(change.session.mood),
               change.session.mood != change.previousMood {
                saveFirst = true
            }
        }
        return (changes, saveFirst)
    }

    /// Marks a machine's sessions as out of reach, or back. Returns the changes for surfaces to show.
    @discardableResult
    public func setUnreachable(_ unreachable: Bool, machine: String) -> [SessionChange] {
        var changes: [SessionChange] = []
        for var s in byId.values where s.origin?.machine.id == machine && s.origin?.unreachable != unreachable {
            s.origin?.unreachable = unreachable
            byId[s.id] = s
            changes.append(SessionChange(session: s, previous: s.activity, event: nil, removed: false))
        }
        return changes
    }

    /// Forgets every session from a machine, e.g. when it's unpaired.
    @discardableResult
    public func remove(machine: String) -> [SessionChange] {
        var changes: [SessionChange] = []
        for s in byId.values where s.origin?.machine.id == machine {
            byId[s.id] = nil
            changes.append(SessionChange(session: s, previous: s.activity, event: nil, removed: true))
        }
        return changes
    }

    private func commit(_ session: Session, previous: Activity?, kind: EventKind, at date: Date) -> SessionChange {
        var s = session
        s.lastEventAt = date
        if kind == .sessionEnded {
            byId[s.id] = nil
            return SessionChange(session: s, previous: previous, event: kind, removed: true)
        }

        reduce(&s, kind, at: date)
        if s.activity != previous { s.activitySince = date }
        byId[s.id] = s
        return SessionChange(session: s, previous: previous, event: kind, removed: false)
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
        let ids = byId.values.filter { $0.origin == nil && $0.host?.bundleId == hostBundleId }.map(\.id).sorted()
        return ids.filter { acknowledge(sessionID: $0) }
    }

    /// Ages sessions out. Call periodically.
    @discardableResult
    public func sweep(now: Date) -> [SessionChange] {
        var changes: [SessionChange] = []
        for (id, var s) in byId {
            let quiet = now.timeIntervalSince(s.lastEventAt)
            let previous = s.activity

            // A remote session's liveness comes from its machine's `follow`; its pids mean nothing here.
            if s.origin == nil, let pid = s.host?.agentPid, !isAlive(pid) {
                byId[id] = nil
                changes.append(SessionChange(session: s, previous: previous, event: nil, removed: true))
                continue
            }

            if s.activity.isBusy, quiet > timeouts.busy {
                s.activity = .idle
            } else if case .waiting = s.activity, quiet > timeouts.waiting, s.origin?.missed != true {
                // A missed prompt is old by definition; it stays until the user has seen it.
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
        let sessions = sessions.map { s in
            var s = s
            if s.origin != nil { s.host = nil }
            return s
        }
        byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    public static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
