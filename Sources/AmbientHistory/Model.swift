import AmbientBase
import Foundation

/// One question for a language model, answered as JSON in a given shape.
public struct ModelRequest: Sendable {
    public var model: String
    /// The standing instructions: the same for every request of a kind, so the API can cache them.
    public var system: String
    public var user: String
    /// The JSON Schema the answer must fit, as JSON text.
    public var schema: String
    /// "low", "medium" or "high": how hard the model should think.
    public var effort: String
    public var maxTokens: Int

    public init(model: String, system: String, user: String, schema: String, effort: String = "low",
                maxTokens: Int = 4_000) {
        self.model = model
        self.system = system
        self.user = user
        self.schema = schema
        self.effort = effort
        self.maxTokens = maxTokens
    }
}

/// Something that answers a `ModelRequest` with JSON text. Tests use their own.
public protocol TextModel: Sendable {
    func answer(_ request: ModelRequest) throws -> String
}

/// The Claude API over plain HTTPS: Swift has no official SDK.
public struct ClaudeAPI: TextModel {
    public var apiKey: String
    public var endpoint: URL
    public var timeout: TimeInterval
    /// How long to wait before the second try; the third waits twice as long.
    public var retryDelay: TimeInterval = 2
    /// Sends a request and waits for the reply. Tests replace it.
    public var send: @Sendable (URLRequest) throws -> (Data, Int)

    /// Models whose safety refusals the API can hand to another model inside the same call.
    static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1",
    ]

    public init(apiKey: String, endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
                timeout: TimeInterval = 240, send: (@Sendable (URLRequest) throws -> (Data, Int))? = nil) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.timeout = timeout
        self.send = send ?? Self.sendOverNetwork
    }

    /// With `ANTHROPIC_API_KEY` when it is set, else the key Ambient already keeps in the Keychain for the board's
    /// skill pack. The environment comes first so a key given on purpose wins, and so nothing asks the Keychain
    /// (which can mean a permission dialog) when it doesn't have to.
    ///
    /// - Parameter asking: false when nobody is watching: the Keychain is then read only if macOS won't ask.
    public static func fromKeychain(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    asking: Bool = true) -> ClaudeAPI? {
        if let key = environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return ClaudeAPI(apiKey: key)
        }
        let stored = asking ? SecretStore.key(for: .anthropic, environment: environment)
            : SecretStore.keyWithoutAsking(for: .anthropic)
        return stored.map { ClaudeAPI(apiKey: $0) }
    }

    func urlRequest(for request: ModelRequest) throws -> URLRequest {
        guard let schema = try? JSONSerialization.jsonObject(with: Data(request.schema.utf8)) else {
            throw HistoryError.message("The answer's schema isn't JSON.")
        }
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "system": [["type": "text", "text": request.system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": request.user]],
            "output_config": ["effort": request.effort, "format": ["type": "json_schema", "schema": schema]],
        ]
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"
        http.timeoutInterval = timeout
        http.setValue("application/json", forHTTPHeaderField: "content-type")
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if Self.fallbackModels.contains(request.model) {
            // A refusal by this model is retried on the one the API picks, in the same call.
            body["fallbacks"] = "default"
            http.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        http.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return http
    }

    public func answer(_ request: ModelRequest) throws -> String {
        let http = try urlRequest(for: request)
        var last = HistoryError.message("The model didn't answer.")
        // Overloaded and rate-limited replies are worth a short wait; anything else is the request's own fault.
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: Double(attempt) * retryDelay) }
            let (data, status): (Data, Int)
            do { (data, status) = try send(http) } catch {
                last = .message("Couldn't reach the Claude API: \(error.localizedDescription)")
                continue
            }
            if status == 429 || status >= 500 {
                last = .message("The Claude API answered \(status).")
                continue
            }
            return try Self.text(from: data, status: status)
        }
        throw last
    }

    static func text(from data: Data, status: Int) throws -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = ((object?["error"] as? [String: Any])?["message"] as? String) ?? "no details"
            if status == 401 || status == 403 {
                throw HistoryError.keyRejected("The Claude API turned the key down (\(status): \(message)). "
                    + "Put a working key in ANTHROPIC_API_KEY or in Ambient's Keychain item.")
            }
            throw HistoryError.message("The Claude API answered \(status): \(message)")
        }
        guard let object, let content = object["content"] as? [[String: Any]] else {
            throw HistoryError.message("The Claude API's reply had no content.")
        }
        switch object["stop_reason"] as? String {
        case "refusal": throw HistoryError.message("The model declined to answer.")
        case "max_tokens": throw HistoryError.message("The model's answer was cut off.")
        default: break
        }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw HistoryError.message("The model's answer was empty.") }
        return text
    }

    private static let sendOverNetwork: @Sendable (URLRequest) throws -> (Data, Int) = { request in
        final class Box: @unchecked Sendable {
            var data: Data?
            var status = -1
            var error: Error?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode ?? -1
            box.error = error
            done.signal()
        }.resume()
        done.wait()
        if let error = box.error { throw error }
        return (box.data ?? Data(), box.status)
    }
}
