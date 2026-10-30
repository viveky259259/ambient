import Foundation

/// Messages between the `ambient` CLI and the app: one JSON object per line, one message per connection.
public enum WireMessage: Codable, Equatable, Sendable {
    case event(AgentEvent)
    case statusRequest
    case status(sessions: [Session], mood: Mood)
    case acknowledgeAll
    /// Take the user to a session: by project, id or id prefix; nil for the most urgent one.
    case open(query: String?)
    /// Reply to `open`: the session that was opened, or nil if nothing matched.
    case opened(sessionID: String?)
    case listTasks
    case tasks([AgentTask])
    case upsertTask(AgentTask)
    case upsertTaskResult(AgentTask)
    /// Open the most urgent linked session for a task id.
    case openTask(String)
    /// The board's local-LLM settings; the reply is `taskModel`.
    case taskModelRequest
    /// Change them (`ambient task model`, `ambient mcp`); the reply is `taskModel` with the result.
    case setTaskModel(TaskModelChange)
    case taskModel(TaskLLMConfig)
    /// Reply when the app didn't get to a task-model request in time; a change may still apply.
    case taskModelTimedOut
    case ping
    case pong(version: String)
    /// A permission prompt the island may answer; the hook waits for `permissionAnswer`.
    case permissionRequest(PermissionAsk)
    case permissionAnswer(PermissionAnswer)
}

public enum Wire {
    public static func encode(_ message: WireMessage) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decode(_ data: Data) throws -> WireMessage {
        try JSONDecoder().decode(WireMessage.self, from: data)
    }
}
