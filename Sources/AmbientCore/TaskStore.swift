import Foundation

/// Folds session activity into board tasks using metadata only (no transcripts).
/// Not thread-safe: own it from one queue.
public final class TaskStore {
    private var byId: [String: AgentTask] = [:]
    /// Session id → task id for quick lookup.
    private var sessionIndex: [String: String] = [:]

    public init() {}

    public var tasks: [AgentTask] {
        byId.values.sorted {
            if $0.status != $1.status {
                return rank($0.status) < rank($1.status)
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public func task(id: String) -> AgentTask? { byId[id] }

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
        t.updatedAt = date
        if byId[t.id] == nil { t.createdAt = date }
        else if let existing = byId[t.id] { t.createdAt = existing.createdAt }
        for sid in t.sessionIds { sessionIndex[sid] = t.id }
        byId[t.id] = t
        return t
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
            lastSessionId: s.id
        )
        if s.mood == .idle { t.status = .backlog }
        byId[t.id] = t
        sessionIndex[s.id] = t.id
        return t
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
            guard calendar.startOfDay(for: t.updatedAt) == day || calendar.startOfDay(for: t.createdAt) == day else {
                return false
            }
            let sameProject: Bool = {
                if let a = t.cwd, let b = s.cwd, !a.isEmpty, a == b { return true }
                if let a = t.project, let b = s.project, a.caseInsensitiveCompare(b) == .orderedSame { return true }
                return false
            }()
            guard sameProject else { return false }
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
