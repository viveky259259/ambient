import Foundation

/// Folds session activity into board tasks. Metadata heuristics are the baseline;
/// optional local-LLM semantics overwrite title/summary/status when applied.
/// Not thread-safe: own it from one queue.
public final class TaskStore {
    /// The most tasks the board keeps from one machine, this Mac included. `prune` is what keeps a board small; this
    /// holds back a machine that makes tasks faster than they expire. Past it, the machine's oldest go first.
    public var machineTaskLimit = 5_000
    /// How long a task the agents made stays once no session is linked to it. Tasks the user wrote don't expire.
    public var retention: TimeInterval = 3 * 86_400
    private var byId: [String: AgentTask] = [:] {
        didSet { sorted = nil }
    }
    /// Session id → task id for quick lookup.
    private var sessionIndex: [String: String] = [:]
    /// `tasks`, kept until the board changes: it's read on every session event.
    private var sorted: [AgentTask]?

    public init() {}

    public var tasks: [AgentTask] {
        if let sorted { return sorted }
        let next = byId.values.sorted {
            if $0.status != $1.status {
                return rank($0.status) < rank($1.status)
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        sorted = next
        return next
    }

    public func task(id: String) -> AgentTask? { byId[id] }

    /// What to open for a task with no live session: its last chat, rebuilt as a session that's no longer running.
    /// Nil for another machine's task, since nothing on this Mac is its.
    public func endedChat(forTaskID id: String) -> Session? {
        guard let t = byId[id], t.machine == nil, let chat = t.lastChat else { return nil }
        return session(chat, of: t)
    }

    /// The same, found by the chat's `agent:session` id: for another machine asking this one to open a chat it ran.
    public func endedChat(forSessionID id: String) -> Session? {
        byId.values
            .filter { $0.machine == nil && $0.lastChat.map { "\($0.agent.rawValue):\($0.sessionId)" } == id }
            .max { $0.updatedAt < $1.updatedAt }
            .flatMap { t in t.lastChat.map { session($0, of: t) } }
    }

    /// Where another machine's task opens: that machine, and the id it knows the chat by. Nil for this Mac's tasks.
    public func remoteChat(forTaskID id: String) -> (machine: MachineRef, sessionID: String)? {
        guard let t = byId[id], let machine = t.machine, let chat = t.lastChat,
              let sid = RemoteOpen.sessionID(agent: chat.agent, sessionId: chat.sessionId) else { return nil }
        return (machine, sid)
    }

    private func session(_ chat: TaskChat, of t: AgentTask) -> Session {
        var s = Session(agent: chat.agent, sessionId: chat.sessionId, at: t.updatedAt)
        s.cwd = t.cwd
        s.host = chat.host
        s.title = t.title
        return s
    }

    public func task(forSessionID id: String) -> AgentTask? {
        sessionIndex[id].flatMap { byId[$0] }
    }

    public func load(_ tasks: [AgentTask]) {
        byId = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        sessionIndex = [:]
        for t in tasks {
            for sid in t.sessionIds { sessionIndex[sid] = t.id }
        }
    }

    /// Creates or replaces a task from the CLI / UI. Manual flag always set.
    @discardableResult
    public func upsert(_ draft: AgentTask, at date: Date = Date()) -> AgentTask {
        var t = draft
        t.manual = true
        t.summarySource = .manual
        t.updatedAt = date
        if byId[t.id] == nil { t.createdAt = date }
        else if let existing = byId[t.id] { t.createdAt = existing.createdAt }
        for sid in t.sessionIds { sessionIndex[sid] = t.id }
        byId[t.id] = t
        return t
    }

    /// Applies local-LLM semantics. Manual titles stay unless empty.
    /// Pass the *current* linked session (not a captured copy): needs-you forces blocked only while
    /// that live session is still `.waiting`.
    @discardableResult
    public func applySemantics(_ semantics: TaskSemantics, toTaskID id: String,
                               session: Session? = nil, at date: Date = Date()) -> AgentTask? {
        guard var t = byId[id] else { return nil }
        // What a model says about a remote session can be remote text, and `ambient tasks` prints it.
        let plain = { [machine = t.machine] (text: String?) in
            machine == nil ? text : text.flatMap { RemoteEventDecoder.plainText($0, max: $0.count) }
        }
        if let title = plain(semantics.title), !title.isEmpty, !t.manual || titleLooksGeneric(t.title) {
            t.title = title
        }
        if let summary = plain(semantics.summary), !summary.isEmpty {
            t.summary = summary
        }
        // A summary can finish after its session ended: it describes work that's over, so it doesn't reopen the task.
        if let status = semantics.status, !t.manual, !t.sessionIds.isEmpty {
            // Never let a stale LLM reply clear needs-you / blocked.
            if !(t.status == .blocked && status != .blocked) {
                t.status = status
            }
        }
        if let session, session.mood == .waiting {
            t.status = .blocked
        }
        t.summarySource = .localLLM
        t.summarizedAt = date
        t.updatedAt = date
        byId[id] = t
        return t
    }

    /// Keeps the board to current work. Unlinks sessions that are gone, when given the ones that are left (sessions a
    /// sweep dropped while Ambient wasn't running never said they ended). A task with no session left isn't in progress
    /// or blocked any more, and once it's been that way for `retention` it goes. Returns whether anything changed.
    @discardableResult
    public func prune(liveSessionIDs live: Set<String>? = nil, now: Date = Date()) -> Bool {
        var changed = false
        if let live {
            for sid in sessionIndex.keys where !live.contains(sid) {
                _ = unlink(sessionID: sid, at: now)
                changed = true
            }
        }
        let cutoff = now.addingTimeInterval(-retention)
        for (id, t) in byId where !t.manual && t.sessionIds.isEmpty {
            if t.updatedAt < cutoff {
                byId[id] = nil
                changed = true
            } else if t.status == .inProgress || t.status == .blocked {
                // Left behind by a summary that came back after its session ended. Its time stays, so it still expires.
                byId[id]?.status = .done
                changed = true
            }
        }
        return changed
    }

    /// Deletes every task from a machine. Returns whether anything went.
    @discardableResult
    public func remove(machine: String) -> Bool {
        let ids = byId.values.filter { $0.machine?.id == machine }.map(\.id)
        for id in ids { byId[id] = nil }
        sessionIndex = sessionIndex.filter { byId[$0.value] != nil }
        return !ids.isEmpty
    }

    /// Applies a session change: link, retitle heuristically, and mirror needs-you → blocked.
    @discardableResult
    public func observe(_ change: SessionChange, calendar: Calendar = .current, now: Date = Date()) -> AgentTask? {
        let s = change.session
        if change.removed {
            return unlink(sessionID: s.id, at: now)
        }
        if s.sessionId.hasPrefix("demo-") { return nil }

        if let id = sessionIndex[s.id], var t = byId[id] {
            applyLive(&t, from: s, at: now)
            byId[id] = t
            return t
        }

        if let match = findMatch(for: s, calendar: calendar, now: now) {
            var t = match
            if !t.sessionIds.contains(s.id) { t.sessionIds.append(s.id) }
            sessionIndex[s.id] = t.id
            applyLive(&t, from: s, at: now)
            byId[t.id] = t
            return t
        }

        if !makeRoom(on: s.origin?.machine.id) { return nil }
        var t = AgentTask(
            title: heuristicTitle(s),
            status: status(from: s.mood),
            project: s.project,
            cwd: s.cwd,
            agents: [s.agent],
            sessionIds: [s.id],
            manual: false,
            createdAt: now,
            updatedAt: now,
            lastSessionId: s.id,
            machine: s.origin?.machine
        )
        t.lastChat = TaskChat(s)
        if s.mood == .idle { t.status = .backlog }
        byId[t.id] = t
        sessionIndex[s.id] = t.id
        return t
    }

    /// Makes room for one more of a machine's tasks by dropping its oldest. A session that's still running has updated
    /// its task, so these are finished work. Tasks the user wrote stay, and when they're all that's left there's no room.
    private func makeRoom(on machine: String?) -> Bool {
        let own = byId.values.lazy.filter { $0.machine?.id == machine }
        var excess = own.count + 1 - machineTaskLimit
        while excess > 0 {
            guard let oldest = own.filter({ !$0.manual }).min(by: { $0.updatedAt < $1.updatedAt }) else { return false }
            byId[oldest.id] = nil
            for sid in oldest.sessionIds where sessionIndex[sid] == oldest.id { sessionIndex[sid] = nil }
            excess -= 1
        }
        return true
    }

    private func unlink(sessionID: String, at date: Date) -> AgentTask? {
        guard let tid = sessionIndex.removeValue(forKey: sessionID), var t = byId[tid] else { return nil }
        t.sessionIds.removeAll { $0 == sessionID }
        if t.lastSessionId == sessionID { t.lastSessionId = t.sessionIds.last }
        t.updatedAt = date
        if t.sessionIds.isEmpty, !t.manual, t.status == .inProgress || t.status == .blocked {
            t.status = .done
        }
        byId[tid] = t
        return t
    }

    private func applyLive(_ t: inout AgentTask, from s: Session, at date: Date) {
        t.lastSessionId = s.id
        // A remote session has no host here; its id is what its own machine opens it by.
        t.lastChat = TaskChat(s)
        t.updatedAt = date
        if let cwd = s.cwd, !cwd.isEmpty { t.cwd = cwd }
        if let project = s.project { t.project = project }
        if !t.agents.contains(s.agent) { t.agents.append(s.agent) }

        if !t.manual {
            let next = heuristicTitle(s)
            if t.title.isEmpty || t.title == "Untitled" || titleLooksGeneric(t.title) {
                t.title = next
            }
            t.status = status(from: s.mood, previous: t.status)
        } else if s.mood == .waiting {
            // Even manual tasks surface needs-you as blocked.
            t.status = .blocked
        }
    }

    private func status(from mood: Mood, previous: TaskStatus = .backlog) -> TaskStatus {
        switch mood {
        case .waiting: .blocked
        case .working: .inProgress
        case .done: .done
        case .error: .blocked
        case .idle:
            previous == .inProgress || previous == .blocked ? previous : .backlog
        }
    }

    private func findMatch(for s: Session, calendar: Calendar, now: Date) -> AgentTask? {
        let day = calendar.startOfDay(for: now)
        let title = normalize(heuristicTitle(s))
        return byId.values.first { t in
            // The same folder name on two machines is two pieces of work.
            guard t.machine?.id == s.origin?.machine.id else { return false }
            let sameProject: Bool = {
                if let a = t.cwd, let b = s.cwd, !a.isEmpty, a == b { return true }
                if let a = t.project, let b = s.project, a.caseInsensitiveCompare(b) == .orderedSame { return true }
                return false
            }()
            guard sameProject else { return false }
            // After the project, because this is what's slow on a full board.
            guard calendar.startOfDay(for: t.updatedAt) == day || calendar.startOfDay(for: t.createdAt) == day else {
                return false
            }
            let other = normalize(t.title)
            return other == title || other.hasPrefix(title) || title.hasPrefix(other)
                || (titleLooksGeneric(t.title) && titleLooksGeneric(heuristicTitle(s)))
        }
    }

    private func heuristicTitle(_ s: Session) -> String {
        if let title = s.title, !title.isEmpty { return Trim.truncate(title, max: 80) }
        if let project = s.project { return project }
        return s.agentLabel
    }

    private func titleLooksGeneric(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty || t == "untitled" || AgentKind.allCases.map { $0.displayName.lowercased() }.contains(t)
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func rank(_ status: TaskStatus) -> Int {
        TaskStatus.boardOrder.firstIndex(of: status) ?? 99
    }
}
