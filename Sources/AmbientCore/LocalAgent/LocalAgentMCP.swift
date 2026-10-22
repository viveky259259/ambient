import Foundation

/// Minimal MCP Streamable HTTP client for the local-agent gateway (`http://127.0.0.1:5051/mcp`).
/// Talks only to loopback; never opens cloud endpoints.
public final class LocalAgentMCP: @unchecked Sendable {
    public struct Config: Equatable, Sendable {
        public var url: URL
        /// Seconds for a single HTTP round-trip.
        public var requestTimeout: TimeInterval
        public init(url: URL = URL(string: "http://127.0.0.1:5051/mcp")!, requestTimeout: TimeInterval = 30) {
            self.url = url
            self.requestTimeout = requestTimeout
        }
    }

    public enum MCPError: Error, Equatable, CustomStringConvertible, Sendable {
        case badURL
        case nonLoopback
        case http(Int)
        case transport(String)
        case rpc(String)
        case decode(String)

        public var description: String {
            switch self {
            case .badURL: "Local-agent MCP URL is invalid."
            case .nonLoopback: "Local-agent MCP URL must be loopback (127.0.0.1 / localhost)."
            case let .http(code): "Local-agent MCP returned HTTP \(code)."
            case let .transport(message): message
            case let .rpc(message): message
            case let .decode(message): "Couldn't read the MCP reply: \(message)"
            }
        }
    }

    private let config: Config
    private let session: URLSession
    private var mcpSessionId: String?
    private var nextID = 1

    public init(config: Config = Config(), session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let s = URLSessionConfiguration.ephemeral
            s.timeoutIntervalForRequest = config.requestTimeout
            s.timeoutIntervalForResource = max(config.requestTimeout, 120)
            self.session = URLSession(configuration: s)
        }
    }

    /// Ensures a session exists (initialize + notifications/initialized).
    public func ensureSession() async throws {
        if mcpSessionId != nil { return }
        _ = try await rpc(method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [:],
            "clientInfo": ["name": "ambient", "version": AmbientVersion.current],
        ] as [String: Any])
        try await notify(method: "notifications/initialized")
    }

    public func callTool(name: String, arguments: [String: Any] = [:]) async throws -> Any {
        try await ensureSession()
        let result = try await rpc(method: "tools/call", params: [
            "name": name,
            "arguments": arguments,
        ])
        guard let obj = result as? [String: Any] else { return result }
        if let isError = obj["isError"] as? Bool, isError {
            let text = ((obj["content"] as? [[String: Any]]) ?? [])
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
            throw MCPError.rpc(text.isEmpty ? "Tool \(name) failed." : text)
        }
        let texts = ((obj["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
        if texts.count == 1, let data = texts[0].data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        if texts.isEmpty { return obj }
        return texts.count == 1 ? texts[0] : texts
    }

    // MARK: - Wire

    private func rpc(method: String, params: [String: Any]?) async throws -> Any {
        // Client is used from one summarizer queue at a time; sequential ids are enough.
        let id = nextID
        nextID += 1
        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { body["params"] = params }
        let payload = try await post(body, expectSSE: true)
        if let err = payload["error"] as? [String: Any] {
            throw MCPError.rpc((err["message"] as? String) ?? "MCP error")
        }
        guard let result = payload["result"] else {
            throw MCPError.decode("Missing result for \(method)")
        }
        return result
    }

    private func notify(method: String) async throws {
        try await post(["jsonrpc": "2.0", "method": method], expectSSE: false)
    }

    @discardableResult
    private func post(_ body: [String: Any], expectSSE: Bool) async throws -> [String: Any] {
        guard TaskLLMConfig.isLoopback(config.url) else { throw MCPError.nonLoopback }
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let mcpSessionId {
            request.setValue(mcpSessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MCPError.transport("Couldn't reach local-agent at \(config.url.host ?? "?"): \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw MCPError.transport("Invalid response") }
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            mcpSessionId = sid
        }
        // 202 Accepted for notifications.
        if (200...299).contains(http.statusCode) == false {
            throw MCPError.http(http.statusCode)
        }
        if !expectSSE || data.isEmpty { return [:] }
        guard let message = Self.parseSSE(data) else {
            throw MCPError.decode(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return message
    }

    /// Extracts the first `data:` JSON object from an SSE body.
    public static func parseSSE(_ data: Data) -> [String: Any]? {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let json = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let payload = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
            return obj
        }
        // Some gateways may reply with raw JSON.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        return nil
    }
}
