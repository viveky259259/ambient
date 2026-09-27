import Foundation

/// Human-readable text for sessions, shared by the CLI and every surface.
public enum Describe {
    public static func activity(_ a: Activity) -> String {
        switch a {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .compacting: return "Compacting context"
        case let .tool(name, detail):
            return join(ToolNames.display(name), detail)
        case let .waiting(reason, message):
            return join(reason == "permission" ? "Needs permission" : "Has a question", message)
        case let .done(summary):
            return join("Done", summary)
        case let .error(message):
            return join("Failed", message)
        }
    }

    /// One or two words, for the collapsed island and the menu bar.
    public static func shortActivity(_ a: Activity) -> String {
        switch a {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .compacting: "Compacting"
        case let .tool(name, _): ToolNames.display(name)
        case .waiting: "Needs you"
        case .done: "Done"
        case .error: "Failed"
        }
    }

    /// The chat or thread title when known, else the project, else the agent's name.
    public static func title(_ s: Session) -> String {
        s.title ?? s.project ?? s.agent.displayName
    }

    /// The project folder, when the title is something else and the folder adds information.
    public static func place(_ s: Session) -> String? {
        guard s.title != nil, let project = s.project, project != s.title else { return nil }
        return project
    }

    /// The time that matters for the session's state: how long the turn has run while working, how long
    /// it has been waiting for you, or how long ago it finished or failed. Nil when idle.
    public static func clock(_ s: Session, now: Date, compact: Bool = false) -> String? {
        func format(_ t: TimeInterval) -> String { compact ? compactDuration(t) : duration(t) }
        switch s.activity {
        case .idle:
            return nil
        case .thinking, .tool, .compacting:
            return s.turnStartedAt.map { format(now.timeIntervalSince($0)) }
        case .waiting:
            return format(now.timeIntervalSince(s.activitySince))
        case .done, .error:
            let ago = now.timeIntervalSince(s.turnEndedAt ?? s.activitySince)
            return ago < 10 ? "just now" : "\(format(ago)) ago"
        }
    }

    /// "took 1m" for a finished or failed turn.
    public static func took(_ s: Session) -> String? {
        switch s.activity {
        case .done, .error: s.turnDuration.map { "took \(duration($0))" }
        default: nil
        }
    }

    /// "4s", "12m", "1h 5m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3_600 { return "\(s / 60)m" }
        let h = s / 3_600, m = (s % 3_600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Like `duration`, but whole hours only: "1h" instead of "1h 5m", for tight spaces.
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        seconds >= 3_600 ? "\(Int(seconds / 3_600))h" : duration(seconds)
    }

    public static func mood(_ m: Mood) -> String {
        switch m {
        case .idle: "idle"
        case .working: "working"
        case .done: "done"
        case .error: "failed"
        case .waiting: "needs you"
        }
    }

    private static func join(_ head: String, _ tail: String?) -> String {
        guard let tail, !tail.isEmpty else { return head }
        return "\(head) · \(tail)"
    }
}
