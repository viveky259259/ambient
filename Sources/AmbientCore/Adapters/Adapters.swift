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
    /// Whether to leave this event out whatever it says, e.g. an agent's own background work.
    static func ignores(event: String, payload: HookPayload, host: HostInfo?) -> Bool
    /// When the event happened, for agents whose events can reach Ambient out of order. Nil means now.
    static func timestamp(_ payload: HookPayload) -> Date?
    /// Where the agent runs, from what the hook found around it.
    static func host(_ payload: HookPayload, captured: HostInfo?) -> HostInfo?
}

extension AgentAdapter {
    static func sessionId(_ payload: HookPayload) -> String? { payload.string("session_id") }
    static func cwd(_ payload: HookPayload) -> String? { payload.string("cwd") }
    static func agentName(_ payload: HookPayload) -> String? { nil }
    static func eventName(_ payload: HookPayload, hint: String?) -> String? { payload.string("hook_event_name") ?? hint }
    static func ignores(event: String, payload: HookPayload, host: HostInfo?) -> Bool { false }
    static func timestamp(_ payload: HookPayload) -> Date? { nil }
    static func host(_ payload: HookPayload, captured: HostInfo?) -> HostInfo? { captured }
}

public enum AdapterRegistry {
    /// How far an agent's own timestamp may be from the hook's clock before Ambient ignores it.
    static let clockTolerance: TimeInterval = 60

    /// Normalizes a hook payload. Returns nil when the payload has no session id or the event
    /// doesn't affect Ambient.
    public static func event(agent: AgentKind, payload: HookPayload, eventHint: String?,
                             now: Date = Date(), host: HostInfo? = nil) -> AgentEvent? {
        let adapter: any AgentAdapter.Type = switch agent {
        case .claude: ClaudeAdapter.self
        case .opencode: OpenCodeAdapter.self
        case .codex: CodexAdapter.self
        case .gemini: GeminiAdapter.self
        case .antigravity: AntigravityAdapter.self
        case .cursor: CursorAdapter.self
        case .copilot: CopilotAdapter.self
        case .custom: CustomAdapter.self
        }
        guard let sessionId = adapter.sessionId(payload), !sessionId.isEmpty,
              let name = adapter.eventName(payload, hint: eventHint),
              !adapter.ignores(event: name, payload: payload, host: host),
              let kind = adapter.normalize(event: name, payload: payload) else { return nil }
        let at = adapter.timestamp(payload).flatMap { abs($0.timeIntervalSince(now)) <= clockTolerance ? $0 : nil } ?? now
        return AgentEvent(agent: agent, sessionId: Trim.truncate(sessionId, max: Limits.sessionId),
                          cwd: adapter.cwd(payload), kind: kind, timestamp: at, host: adapter.host(payload, captured: host),
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

    /// A prompt about a tool call: what it needs, and the command, file, host or question it's about.
    static func needsInput(tool name: String, input: HookPayload?) -> EventKind {
        let need = Need.forTool(name)
        let detail: String? = switch need {
        case .command, .edit, .web: ToolNames.detail(name: name, input: input)
        case .question: question(input)
        case .plan: firstLine(input?.string("plan"))
        case .access, .permission: toolMessage(name: name, input: input)
        }
        return needsInput(need, detail)
    }

    static func needsInput(_ need: Need, _ detail: String?) -> EventKind {
        .needsInput(reason: need.rawValue, message: Trim.clean(detail, max: Limits.message))
    }

    /// A permission prompt known only by its text.
    static func permissionNotice(_ message: String?) -> EventKind {
        let (need, detail) = Need.fromText(message)
        return needsInput(need, detail)
    }

    /// "Read: secrets.txt", "github · create_pr": a tool whose name the headline doesn't give.
    static func toolMessage(name: String, input: HookPayload?) -> String {
        let display = ToolNames.display(name)
        guard let detail = ToolNames.detail(name: name, input: input) else { return display }
        return "\(display): \(detail)"
    }

    /// The first question of Claude's AskUserQuestion or OpenCode's question tool, which share a shape:
    /// `{"questions": [{"question", "header", "options"}]}`.
    static func question(_ input: HookPayload?) -> String? {
        let questions = input?.objects("questions") ?? []
        guard let text = questions.first?.firstString(["question", "header"]) else { return nil }
        return questions.count > 1 ? "\(text) (+\(questions.count - 1) more)" : text
    }

    /// A plan's first line, without its heading marks.
    private static func firstLine(_ text: String?) -> String? {
        let line = text?.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .first { !$0.isEmpty }
        return line.flatMap { Trim.clean($0, max: Limits.message) }
    }
}

/// Claude Code. Codex's hooks use the same event names and fields, so CodexAdapter builds on this one, and
/// OpenCode's plugin speaks this format too. Cursor has its own adapter — do not add it here.
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
            return AdapterRegistry.needsInput(tool: p.string("tool_name") ?? "tool", input: p.object("tool_input"))
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
            // Claude's own words for the prompt its PermissionRequest hook already described.
            return AdapterRegistry.permissionNotice(message)
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            return AdapterRegistry.needsInput(.question, message)
        case "idle_prompt":
            // A reminder that the turn already finished; the session is already done.
            return nil
        default:
            return message.map { .notice(message: $0) }
        }
    }
}

/// OpenCode, through the plugin `ambient install opencode` writes (`OpenCodePlugin`). It speaks Claude's format for
/// prompts, tools and turns, and adds events of its own: `Permission` with OpenCode's permission request, `Question`
/// when its question tool asks, and `Answered` when the user replies to either. Each event goes to its own process,
/// so they can reach the app out of order: the plugin stamps them with `ts`, OpenCode's time in milliseconds, which
/// only goes up.
enum OpenCodeAdapter: AgentAdapter {
    static func timestamp(_ p: HookPayload) -> Date? {
        p.number("ts").map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// OpenCode 2 runs plugins in its background service (`service: true`), whose environment is that of whatever first
    /// started it: an app, a terminal tab, a tmux pane, another agent's chat. None of it says where this session is, so
    /// only the service itself is kept, which tells when it's gone.
    static func host(_ p: HookPayload, captured: HostInfo?) -> HostInfo? {
        guard p.raw["service"] as? Bool == true, let captured else { return captured }
        return HostInfo(pids: captured.pids, agentPid: captured.agentPid)
    }

    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        switch event {
        case "Permission": permission(p)
        case "Question": AdapterRegistry.needsInput(.question, AdapterRegistry.question(p))
        case "Answered": .answered
        default: ClaudeAdapter.normalize(event: event, payload: p)
        }
    }

    /// OpenCode asks by permission rather than tool: `bash`, `edit`, `webfetch`, `external_directory`, `doom_loop`, an
    /// MCP tool's name. `patterns` are what it would allow (the files of an edit, a command's prefix) and `metadata`
    /// what the tool said: the command, the file, the URL.
    private static func permission(_ p: HookPayload) -> EventKind {
        let name = p.string("permission") ?? "tool"
        let patterns = p.strings("patterns").filter { $0 != "*" }
        let metadata = p.object("metadata")
        switch name {
        case "bash", "shell":
            // OpenCode 2 names only the command, as the request's one pattern.
            let command = metadata?.string("command") ?? patterns.first
            return AdapterRegistry.needsInput(.command, Trim.clean(command, max: Limits.detail))
        case "doom_loop":
            // The same call three times in a row: OpenCode checks before the agent goes round again.
            return AdapterRegistry.needsInput(tool: metadata?.string("tool") ?? "tool", input: metadata?.object("input"))
        case "edit":
            let files = patterns.isEmpty ? metadata.flatMap { $0.string("filepath") }.map { [$0] } ?? [] : patterns
            let first = files.first.map { URL(fileURLWithPath: $0).lastPathComponent }
            return AdapterRegistry.needsInput(.edit, first.map { files.count > 1 ? "\($0) +\(files.count - 1) more" : $0 })
        case "external_directory":
            let place = metadata?.strings("directories").first ?? metadata?.firstString(["parentDir", "filepath"]) ?? patterns.first
            return AdapterRegistry.needsInput(.access, place.map { ($0 as NSString).abbreviatingWithTildeInPath })
        default:
            // Some tools say nothing in metadata, like read: their pattern is the file, or the page.
            let pattern = patterns.first.map { [$0.contains("://") ? "url" : "path": $0] } ?? [:]
            let input = metadata.flatMap { $0.raw.isEmpty ? nil : $0 } ?? HookPayload(pattern)
            return AdapterRegistry.needsInput(tool: name, input: input)
        }
    }
}

/// Codex. Codex Desktop also runs one-turn threads of its own through these hooks, e.g. to suggest
/// the next prompt when a turn ends ({"suggestion":"…"}). It doesn't save them, so their payloads
/// carry a null transcript_path, and they run under `codex app-server`. Threads people work in there
/// have a transcript, forks included. `codex exec --ephemeral` has none either, but it's real work and
/// doesn't run under the app server. SessionEnd still passes, clearing rows from before.
enum CodexAdapter: AgentAdapter {
    static func normalize(event: String, payload p: HookPayload) -> EventKind? {
        ClaudeAdapter.normalize(event: event, payload: p)
    }

    static func ignores(event: String, payload p: HookPayload, host: HostInfo?) -> Bool {
        p.isNull("transcript_path") && host?.appServer == true && event != "SessionEnd"
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
                return toolPermission(p.object("details"), message: message)
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

    /// Gemini describes the confirmation it shows in `details`: `exec` with the command, `edit` with the file, `mcp`
    /// with the server and tool, `info` with the URLs a fetch would read. Its `message` ("Tool Shell requires
    /// execution") only helps when there are no details.
    private static func toolPermission(_ d: HookPayload?, message: String?) -> EventKind {
        guard let d else { return AdapterRegistry.permissionNotice(message) }
        switch d.string("type") {
        case "exec":
            return AdapterRegistry.needsInput(.command, Trim.clean(d.firstString(["command", "rootCommand"]), max: Limits.detail))
        case "edit":
            let file = d.firstString(["fileName"]) ?? d.string("filePath").map { URL(fileURLWithPath: $0).lastPathComponent }
            return AdapterRegistry.needsInput(.edit, file)
        case "mcp":
            let tool = d.firstString(["toolDisplayName", "toolName"])
            let detail = [d.string("serverName"), tool].compactMap { $0 }.joined(separator: " · ")
            return AdapterRegistry.needsInput(.permission, detail.isEmpty ? d.string("title") : detail)
        case "info":
            let url = d.strings("urls").first
            return AdapterRegistry.needsInput(.web, url.map { URL(string: $0)?.host ?? $0 })
        default:
            return AdapterRegistry.needsInput(.permission, d.string("title") ?? message)
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
            case "permission_prompt": return AdapterRegistry.permissionNotice(message)
            case "elicitation_dialog": return AdapterRegistry.needsInput(.question, message)
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
/// start, working, waiting, done, error or end (idle is an alias for end), and `reason` names a `Need`.
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
            let need = p.string("reason").flatMap { Need(rawValue: $0.lowercased()) } ?? .question
            return .needsInput(reason: need.rawValue, message: message)
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
