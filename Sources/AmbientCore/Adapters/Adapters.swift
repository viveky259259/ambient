import Foundation

/// Limits for text that leaves the hook process.
enum Limits {
    static let detail = 80
    static let message = 160
    static let sessionId = 128
    static let agentName = 24
}

/// Turns one agent's hook payloads into normalized events.
protocol AgentAdapter {
    static func normalize(event: String, payload: HookPayload) -> EventKind?
    static func sessionId(_ payload: HookPayload) -> String?
    static func cwd(_ payload: HookPayload) -> String?
    static func agentName(_ payload: HookPayload) -> String?
    /// The event's name, from the payload or else from the hook command.
    static func eventName(_ payload: HookPayload, hint: String?) -> String?
}

extension AgentAdapter {
    static func sessionId(_ payload: HookPayload) -> String? { payload.string("session_id") }
    static func cwd(_ payload: HookPayload) -> String? { payload.string("cwd") }
    static func agentName(_ payload: HookPayload) -> String? { nil }
    static func eventName(_ payload: HookPayload, hint: String?) -> String? { payload.string("hook_event_name") ?? hint }
}

public enum AdapterRegistry {
    /// Normalizes a hook payload. Returns nil when the payload has no session id or the event
    /// doesn't affect Ambient.
    public static func event(agent: AgentKind, payload: HookPayload, eventHint: String?,
                             now: Date = Date(), host: HostInfo? = nil) -> AgentEvent? {
        let adapter: any AgentAdapter.Type = switch agent {
        // OpenCode's events reach Ambient through its plugin, which speaks Claude's format.
        case .claude, .codex, .opencode: ClaudeAdapter.self
        case .gemini: GeminiAdapter.self
        case .antigravity: AntigravityAdapter.self
        case .cursor: CursorAdapter.self
        case .copilot: CopilotAdapter.self
        case .custom: CustomAdapter.self
        }
        guard let sessionId = adapter.sessionId(payload), !sessionId.isEmpty,
              let name = adapter.eventName(payload, hint: eventHint),
              let kind = adapter.normalize(event: name, payload: payload) else { return nil }
        return AgentEvent(agent: agent, sessionId: Trim.truncate(sessionId, max: Limits.sessionId),
                          cwd: adapter.cwd(payload), kind: kind, timestamp: now, host: host,
                          agentName: adapter.agentName(payload))
    }

    /// What the hook prints on stdout. Gemini and Antigravity parse it as JSON; Antigravity requires a
    /// decision before a tool runs and when a turn stops, and "allow" defers to its own permission rules.
    public static func reply(agent: AgentKind, event: String?) -> String? {
        switch agent {
        case .claude, .codex, .cursor, .copilot, .opencode, .custom: nil
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
/// OpenCode's plugin also speaks this format. Cursor has its own adapter — do not add it here.
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
            // The docs spell reasons in lowercase; agy 1.4 sends constants such as NO_TOOL_CALL.
            switch p.string("terminationReason")?.lowercased() {
            case "error": return .turnFailed(message: error)
            case "max_steps_exceeded": return .turnFailed(message: error ?? "Reached its step limit")
            default: return error.map { .turnFailed(message: $0) } ?? .turnCompleted(summary: nil)
            }
        default:
            return nil
        }
    }
}

/// Cursor's agent, in the editor and in cursor-agent where its hooks fire. Ambient registers only hooks that
/// can't block or approve anything: Cursor treats a before-tool / before-shell hook's reply as a permission
/// decision. After-the-fact hooks map to `toolStarted` so the island shows the last tool until the turn stops.
///
/// Not part of the ClaudeAdapter family (Claude / Codex / OpenCode). Never read a payload `agent` field —
/// Cursor payloads can mention model names like Codex; the tag must stay "Cursor".
enum CursorAdapter: AgentAdapter {
    static func sessionId(_ p: HookPayload) -> String? { p.string("conversation_id") ?? p.string("session_id") }
    static func cwd(_ p: HookPayload) -> String? { p.strings("workspace_roots").first ?? p.string("cwd") }
    static func agentName(_: HookPayload) -> String? { nil }

    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        switch event {
        case "sessionStart":
            return .sessionStarted
        case "beforeSubmitPrompt":
            return .promptSubmitted
        case "postToolUse", "afterShellExecution", "afterMCPExecution":
            let name = p.string("tool_name") ?? p.string("command") ?? defaultToolName(event)
            return .toolStarted(name: name, detail: ToolNames.detail(name: name, input: p.object("tool_input") ?? p.object("args")))
        case "afterFileEdit":
            let path = p.string("file_path") ?? p.string("path") ?? p.strings("file_paths").first
            let detail = path.map { URL(fileURLWithPath: $0).lastPathComponent }
            return .toolStarted(name: "Edit", detail: detail)
        case "postToolUseFailure":
            return .toolFinished(name: p.string("tool_name") ?? "tool", failed: true)
        case "subagentStart":
            return .subagentStarted
        case "subagentStop":
            return .subagentFinished
        case "preCompact":
            return .compactStarted
        case "stop":
            return p.string("status") == "error" ? .turnFailed(message: nil) : .turnCompleted(summary: nil)
        case "sessionEnd":
            return .sessionEnded
        default:
            return nil
        }
    }

    private static func defaultToolName(_ event: String) -> String {
        switch event {
        case "afterShellExecution": "Shell"
        case "afterMCPExecution": "MCP"
        default: "tool"
        }
    }
}

/// GitHub Copilot CLI. Its camelCase payloads don't always name the event, so each hook command passes it.
enum CopilotAdapter: AgentAdapter {
    static func sessionId(_ p: HookPayload) -> String? { p.string("sessionId") ?? p.string("session_id") }

    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        // The command passes "notification"; the payload itself says "Notification".
        switch event.lowercased() {
        case "sessionstart":
            return .sessionStarted
        case "userpromptsubmitted":
            return .promptSubmitted
        case "pretooluse":
            let name = p.string("toolName") ?? p.string("tool_name") ?? "tool"
            let input = p.objectOrJSON("toolArgs") ?? p.object("tool_input")
            return .toolStarted(name: name, detail: ToolNames.detail(name: name, input: input))
        case "posttooluse":
            return .toolFinished(name: p.string("toolName") ?? p.string("tool_name") ?? "tool", failed: false)
        case "posttoolusefailure":
            return .toolFinished(name: p.string("toolName") ?? p.string("tool_name") ?? "tool", failed: true)
        case "agentstop":
            return .turnCompleted(summary: nil)
        case "erroroccurred":
            let message = Trim.clean(p.object("error")?.string("message") ?? p.string("error"), max: Limits.message)
            if p.raw["recoverable"] as? Bool == true { return message.map { .notice(message: $0) } }
            return .turnFailed(message: message)
        case "subagentstart":
            return .subagentStarted
        case "subagentstop":
            return .subagentFinished
        case "precompact":
            return .compactStarted
        case "notification":
            let message = Trim.clean(p.string("message"), max: Limits.message)
            switch p.string("notification_type") {
            case "permission_prompt": return .needsInput(reason: "permission", message: message)
            case "elicitation_dialog": return .needsInput(reason: "question", message: message)
            // The turn's end arrives as agentStop; shell completions are noise.
            case "agent_completed", "agent_idle", "shell_completed", "shell_detached_completed": return nil
            default: return message.map { .notice(message: $0) }
            }
        case "sessionend":
            return .sessionEnded
        default:
            return nil
        }
    }
}

/// Any other agent or script. The event JSON is documented in the README under "Any other agent":
/// `{"session_id", "event", "agent", "cwd", "tool", "detail", "message", "reason"}`, where `event` is one of
/// start, working, waiting, done, error or end (idle is an alias for end).
public enum CustomAdapter: AgentAdapter {
    public static let events = ["start", "working", "waiting", "done", "error", "end", "idle"]

    static func agentName(_ p: HookPayload) -> String? { Trim.clean(p.string("agent"), max: Limits.agentName) }
    static func eventName(_ p: HookPayload, hint: String?) -> String? { p.string("event") ?? hint }

    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        let message = Trim.clean(p.string("message"), max: Limits.message)
        switch event {
        case "start":
            return .sessionStarted
        case "working":
            guard let tool = Trim.clean(p.string("tool"), max: Limits.detail) else { return .promptSubmitted }
            return .toolStarted(name: tool, detail: Trim.clean(p.string("detail"), max: Limits.detail))
        case "waiting":
            return .needsInput(reason: p.string("reason") == "permission" ? "permission" : "question", message: message)
        case "done":
            return .turnCompleted(summary: message)
        case "error":
            return .turnFailed(message: message)
        case "end", "idle":
            return .sessionEnded
        default:
            return nil
        }
    }
}
