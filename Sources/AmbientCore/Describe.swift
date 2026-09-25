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

    /// The session's project, or the agent's name when the project is unknown.
    public static func title(_ s: Session) -> String {
        s.project ?? s.agent.displayName
    }

    /// "4s", "12m", "1h 5m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3_600 { return "\(s / 60)m" }
        let h = s / 3_600, m = (s % 3_600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
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
