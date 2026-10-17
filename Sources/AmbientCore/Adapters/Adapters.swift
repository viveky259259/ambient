import Foundation

/// Limits for text that leaves the hook process.
enum Limits {
    static let detail = 80
    static let message = 160
}

/// Turns one agent's hook payloads into normalized events.
protocol AgentAdapter {
    static func normalize(event: String, payload: HookPayload) -> EventKind?
    static func sessionId(_ payload: HookPayload) -> String?
    static func cwd(_ payload: HookPayload) -> String?
}

extension AgentAdapter {
    static func sessionId(_ payload: HookPayload) -> String? { payload.string("session_id") }
    static func cwd(_ payload: HookPayload) -> String? { payload.string("cwd") }
}

public enum AdapterRegistry {
    /// Normalizes a hook payload. Returns nil when the payload has no session id or the event
    /// doesn't affect Ambient.
    public static func event(agent: AgentKind, payload: HookPayload, eventHint: String?,
                             now: Date = Date(), host: HostInfo? = nil) -> AgentEvent? {
        let adapter: any AgentAdapter.Type = switch agent {
        case .claude, .codex: ClaudeAdapter.self
        case .gemini: GeminiAdapter.self
        case .antigravity: AntigravityAdapter.self
        }
        guard let sessionId = adapter.sessionId(payload), !sessionId.isEmpty,
              let name = payload.string("hook_event_name") ?? eventHint,
              let kind = adapter.normalize(event: name, payload: payload) else { return nil }
        return AgentEvent(agent: agent, sessionId: sessionId, cwd: adapter.cwd(payload),
                          kind: kind, timestamp: now, host: host)
    }

    /// What the hook prints on stdout. Gemini and Antigravity parse it as JSON; Antigravity requires a
    /// decision before a tool runs and when a turn stops, and "allow" defers to its own permission rules.
    public static func reply(agent: AgentKind, event: String?) -> String? {
        switch agent {
        case .claude, .codex: nil
        case .gemini: "{}\n"
        case .antigravity: event == "PreToolUse" || event == "Stop" ? #"{"decision":"allow"}"# + "\n" : "{}\n"
        }
    }

    static func toolStarted(_ p: HookPayload) -> EventKind {
        let name = p.string("tool_name") ?? "tool"
        return .toolStarted(name: name, detail: ToolNames.detail(name: name, input: p.object("tool_input")))
    }

    /// "Bash: rm -rf build", for permission prompts that don't come with their own message.
    static func permissionMessage(_ p: HookPayload) -> String? {
        guard let name = p.string("tool_name") else { return nil }
        let display = ToolNames.display(name)
        guard let detail = ToolNames.detail(name: name, input: p.object("tool_input")) else { return display }
        return Trim.clean("\(display): \(detail)", max: Limits.message)
    }
}

/// Claude Code. Codex's hooks use the same event names and fields, so it shares this adapter.
enum ClaudeAdapter: AgentAdapter {
    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        switch event {
        case "SessionStart":
            let source = p.string("source") ?? p.string("reason")
            return source == "compact" ? .compactFinished : .sessionStarted
        case "UserPromptSubmit":
            return .promptSubmitted
        case "PreToolUse":
            return AdapterRegistry.toolStarted(p)
        case "PostToolUse":
            return .toolFinished(name: p.string("tool_name") ?? "tool", failed: false)
        case "PostToolUseFailure":
            return .toolFinished(name: p.string("tool_name") ?? "tool", failed: true)
        case "PermissionRequest":
            return .needsInput(reason: "permission", message: AdapterRegistry.permissionMessage(p))
        case "Notification":
            return notification(p)
        case "PreCompact":
            return .compactStarted
        case "PostCompact":
            return .compactFinished
        case "SubagentStart":
            return .subagentStarted
        case "SubagentStop":
            return .subagentFinished
        case "Stop":
            return .turnCompleted(summary: Trim.clean(p.string("last_assistant_message"), max: Limits.message))
        case "StopFailure":
            let message = p.firstString(["error_message", "error", "error_type"])
            return .turnFailed(message: Trim.clean(message, max: Limits.message))
        case "SessionEnd":
            return .sessionEnded
        default:
            return nil
        }
    }

    private static func notification(_ p: HookPayload) -> EventKind? {
        let message = Trim.clean(p.string("message"), max: Limits.message)
        switch p.string("notification_type") {
        case "permission_prompt":
            return .needsInput(reason: "permission", message: message)
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            return .needsInput(reason: "question", message: message)
        case "idle_prompt":
            // A reminder that the turn already finished; the session is already done.
            return nil
        default:
            return message.map { .notice(message: $0) }
        }
    }
}

enum GeminiAdapter: AgentAdapter {
    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        switch event {
        case "SessionStart":
            return .sessionStarted
        case "BeforeAgent":
            return .promptSubmitted
        case "BeforeTool":
            return AdapterRegistry.toolStarted(p)
        case "AfterTool":
            let failed = p.object("tool_response")?.has("error") ?? false
            return .toolFinished(name: p.string("tool_name") ?? "tool", failed: failed)
        case "Notification":
            let message = Trim.clean(p.string("message"), max: Limits.message)
            if p.string("notification_type") == "ToolPermission" {
                return .needsInput(reason: "permission", message: message)
            }
            return message.map { .notice(message: $0) }
        case "PreCompress":
            return .compactStarted
        case "AfterAgent":
            return .turnCompleted(summary: Trim.clean(p.string("prompt_response"), max: Limits.message))
        case "SessionEnd":
            return .sessionEnded
        default:
            return nil
        }
    }
}

/// Google Antigravity. Its payloads are camelCase, name the session by conversation and the project by
/// workspace, and don't name the event, so each hook command passes it. There's no permission event.
enum AntigravityAdapter: AgentAdapter {
    static func sessionId(_ p: HookPayload) -> String? { p.string("conversationId") }
    static func cwd(_ p: HookPayload) -> String? { p.strings("workspacePaths").first }

    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        switch event {
        case "SessionStart":
            return .sessionStarted
        case "PreInvocation":
            // Runs before every model call of a turn; only the first means a new prompt.
            return (p.string("invocationNum") ?? "0") == "0" ? .promptSubmitted : nil
        case "PreToolUse":
            let call = p.object("toolCall")
            let name = call?.string("name") ?? "tool"
            return .toolStarted(name: name, detail: ToolNames.detail(name: name, input: call?.object("args")))
        case "PostToolUse":
            let failed = p.firstString(["error"]) != nil
            return .toolFinished(name: p.object("toolCall")?.string("name") ?? "tool", failed: failed)
        case "Stop":
            let error = Trim.clean(p.firstString(["error"]), max: Limits.message)
            switch p.string("terminationReason") {
            case "error": return .turnFailed(message: error)
            case "max_steps_exceeded": return .turnFailed(message: error ?? "Reached its step limit")
            default: return error.map { .turnFailed(message: $0) } ?? .turnCompleted(summary: nil)
            }
        default:
            return nil
        }
    }
}
