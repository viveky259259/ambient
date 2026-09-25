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
