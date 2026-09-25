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
    case ping
    case pong(version: String)
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
