import Foundation

/// One-shot Anthropic bootstrap that writes `~/.ambient/task-skill.json` for the local summarizer.
///
/// Live board path never calls this — only `ambient task skill-bootstrap` (or Settings trigger) does.
public struct TaskSkillBootstrap: Sendable {
    public var apiKey: String
    public var model: String
    public var endpoint: URL

    public init(apiKey: String,
                model: String = "claude-haiku-4-5-20251001",
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    /// Reads Keychain / env, calls Anthropic once, writes the skill pack, returns it.
    @discardableResult
    public static func run(paths: AmbientPaths = .current(),
                           apiKey: String? = nil,
                           session: URLSession = .shared) async throws -> TaskSkillPack {
        let key = try resolveKey(apiKey)
        let boot = TaskSkillBootstrap(apiKey: key)
        let pack = try await boot.generate(session: session)
        try TaskSkillStore.save(pack, paths: paths)
        return pack
    }

    /// Sync wrapper for the CLI (`ambient task skill-bootstrap`).
    @discardableResult
    public static func runSync(paths: AmbientPaths = .current(),
                               apiKey: String? = nil,
                               session: URLSession = .shared) throws -> TaskSkillPack {
        let key = try resolveKey(apiKey)
        let boot = TaskSkillBootstrap(apiKey: key)
        let pack = try boot.generateSync(session: session)
        try TaskSkillStore.save(pack, paths: paths)
        return pack
    }

    public static func resolveKey(_ override: String? = nil,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        if let override, !override.isEmpty { return override }
        guard let key = SecretStore.key(for: .anthropic, environment: environment) else {
            throw SecretStoreError.missingAnthropicKey
        }
        return key
    }

    public func generate(session: URLSession = .shared) async throws -> TaskSkillPack {
        let request = try makeRequest()
        let (data, response) = try await session.data(for: request)
        return try Self.pack(from: data, response: response)
    }

    public func generateSync(session: URLSession = .shared) throws -> TaskSkillPack {
        let request = try makeRequest()
        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }.resume()
        sem.wait()
        if let error = box.error { throw error }
        guard let data = box.data else {
            throw SecretStoreError.decode("Anthropic returned empty body")
        }
        return try Self.pack(from: data, response: box.response)
    }

    private func makeRequest() throws -> URLRequest {
        let userPrompt = """
        You are labeling examples for a tiny on-device coding-agent task board summarizer.
        Produce JSON ONLY (no markdown) with this shape:
        {
          "hints": ["short style rule", "..."],
          "examples": [
            {
              "facts": "multiline session facts block (agent/project/mood/activity/optional transcript)",
              "title": "≤50 chars verb+object",
              "summary": "≤12 words one sentence",
              "status": "backlog|inProgress|blocked|done|cancelled"
            }
          ]
        }
        Rules:
        - Exactly 8 diverse examples across Codex, Claude, Cursor, Gemini, Copilot.
        - Cover blocked (needs user), inProgress, done, and one backlog.
        - facts must look like Ambient SessionContextBuilder output.
        - Never invent API keys or secrets.
        - hints: 3–5 short rules matching the JSON schema the local model must emit.
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 90

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2500,
            "temperature": 0.3,
            "messages": [
                ["role": "user", "content": userPrompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func pack(from data: Data, response: URLResponse?) throws -> TaskSkillPack {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SecretStoreError.anthropicHTTP(code, text)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            throw SecretStoreError.decode("Anthropic response missing content")
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        let payload = try parsePayload(text)
        return TaskSkillPack(
            version: 1,
            createdAt: Date(),
            source: "anthropic-bootstrap",
            hints: payload.hints,
            examples: payload.examples
        )
    }

    struct Payload {
        var hints: [String]
        var examples: [TaskSkillPack.Example]
    }

    static func parsePayload(_ raw: String) throws -> Payload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String = {
            if trimmed.hasPrefix("```") {
                var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
                if lines.last?.hasPrefix("```") == true { lines.removeLast() }
                return lines.joined(separator: "\n")
            }
            return trimmed
        }()
        guard let data = unfenced.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SecretStoreError.decode("Bootstrap reply was not JSON")
        }
        let hints = (obj["hints"] as? [String] ?? []).map { Trim.clean($0, max: 160) ?? $0 }.filter { !$0.isEmpty }
        let rawExamples = obj["examples"] as? [[String: Any]] ?? []
        let examples: [TaskSkillPack.Example] = rawExamples.compactMap { ex in
            guard let facts = ex["facts"] as? String, !facts.isEmpty,
                  let title = Trim.clean(ex["title"] as? String ?? "", max: 50),
                  let summary = Trim.clean(ex["summary"] as? String ?? "", max: 90),
                  let status = ex["status"] as? String,
                  TaskStatus(rawValue: status) != nil else { return nil }
            return .init(facts: Trim.truncate(facts, max: 800), title: title, summary: summary, status: status)
        }
        guard examples.count >= 4 else {
            throw SecretStoreError.decode("Bootstrap returned too few usable examples (\(examples.count))")
        }
        return Payload(hints: hints.isEmpty ? TaskSkillPack.bundledSeed.hints : hints, examples: examples)
    }
}
