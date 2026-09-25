import Foundation

/// Synthetic events for `ambient emit` and `ambient demo`.
public enum Demo {
    /// Events that put a demo session into `mood`.
    public static func events(for mood: Mood, agent: AgentKind = .claude, project: String = "ambient-demo",
                              message: String? = nil, now: Date = Date(), host: HostInfo? = nil) -> [AgentEvent] {
        let session = "demo-\(agent.rawValue)-\(project)"
        let cwd = "/demo/\(project)"
        func e(_ kind: EventKind, _ offset: TimeInterval) -> AgentEvent {
            AgentEvent(agent: agent, sessionId: session, cwd: cwd, kind: kind, timestamp: now.addingTimeInterval(offset), host: host)
        }
        switch mood {
        case .idle:
            return [e(.sessionEnded, 0)]
        case .working:
            return [e(.promptSubmitted, -1), e(.toolStarted(name: "Bash", detail: message ?? "npm test"), 0)]
        case .waiting:
            return [e(.promptSubmitted, -12), e(.needsInput(reason: "permission", message: message ?? "Bash: rm -rf build"), 0)]
        case .done:
            // Long enough to clear the notification threshold.
            return [e(.promptSubmitted, -95), e(.turnCompleted(summary: message ?? "All 42 tests pass. Ready for review."), 0)]
        case .error:
            return [e(.promptSubmitted, -30), e(.turnFailed(message: message ?? "Rate limited — retry in 2 minutes"), 0)]
        }
    }

    public struct Step: Sendable {
        public let title: String
        public let mood: Mood
        public let agent: AgentKind
        public let project: String
        public let message: String?
    }

    /// A tour of every state across three agents, a few seconds apart.
    public static let tour: [Step] = [
        Step(title: "Claude starts working", mood: .working, agent: .claude, project: "api-server", message: "npm test"),
        Step(title: "Codex joins", mood: .working, agent: .codex, project: "web", message: "cargo build --release"),
        Step(title: "Claude needs permission", mood: .waiting, agent: .claude, project: "api-server", message: "Bash: rm -rf build"),
        Step(title: "Claude gets back to work", mood: .working, agent: .claude, project: "api-server", message: "swift build"),
        Step(title: "Gemini hits an error", mood: .error, agent: .gemini, project: "docs", message: "Quota exceeded"),
        Step(title: "Codex finishes", mood: .done, agent: .codex, project: "web", message: "Release build ready: 3 crates updated"),
        Step(title: "Claude finishes", mood: .done, agent: .claude, project: "api-server", message: "All 42 tests pass. Ready for review."),
    ]

    /// Ends every session the tour created.
    public static func tourCleanup(now: Date = Date(), host: HostInfo? = nil) -> [AgentEvent] {
        var seen = Set<String>()
        return tour.filter { seen.insert("\($0.agent.rawValue)/\($0.project)").inserted }
            .flatMap { events(for: .idle, agent: $0.agent, project: $0.project, now: now, host: host) }
    }

    public static func mood(named name: String) -> Mood? {
        switch name.lowercased() {
        case "idle", "clear", "end": .idle
        case "working", "work", "busy": .working
        case "waiting", "wait", "input", "permission": .waiting
        case "done", "finished", "complete": .done
        case "error", "fail", "failed": .error
        default: nil
        }
    }
}
