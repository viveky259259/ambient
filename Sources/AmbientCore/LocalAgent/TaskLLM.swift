import Foundation

/// Preferences for Ambient's board summarizer (local-agent MCP only).
public struct TaskLLMConfig: Equatable, Sendable {
    /// Master switch. When off, the board uses metadata heuristics only.
    public var enabled: Bool
    /// Streamable HTTP MCP endpoint for local-agent (default loopback LaunchAgent).
    public var mcpURL: String
    /// Exact model id from `list_models`, e.g. `hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit`.
    public var modelID: String
    /// When true, Ambient may read local agent transcript stores (Claude projects, Codex index) for richer context.
    public var readTranscripts: Bool
    /// Path checked for the external models volume (`models-on` mounts here).
    public var modelsVolumePath: String
    /// Minimum seconds between LLM refreshes for the same task.
    public var minRefreshSeconds: TimeInterval

    public init(enabled: Bool = false,
                mcpURL: String = "http://127.0.0.1:5051/mcp",
                modelID: String = "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                readTranscripts: Bool = false,
                modelsVolumePath: String = "/Volumes/Models",
                minRefreshSeconds: TimeInterval = 45) {
        self.enabled = enabled
        self.mcpURL = mcpURL
        self.modelID = modelID
        self.readTranscripts = readTranscripts
        self.modelsVolumePath = modelsVolumePath
        self.minRefreshSeconds = minRefreshSeconds
    }

    public var mcpEndpoint: URL? { URL(string: mcpURL) }

    /// Cloud-tagged Ollama models are refused so session text never leaves the Mac by default.
    public var refusesCloudModel: Bool {
        modelID.lowercased().contains(":cloud") || modelID.lowercased().contains("cloud/")
    }
}

/// Calm status for Settings › Board.
public enum TaskLLMStatus: Equatable, Sendable {
    case disabled
    case ready
    case summarizing
    case gatewayDown(String)
    case volumeMissing(String)
    case modelUnavailable(String)
    case cloudModelBlocked(String)
    case failed(String)

    public var label: String {
        switch self {
        case .disabled: "Local LLM off — using metadata heuristics"
        case .ready: "Local LLM ready"
        case .summarizing: "Summarizing…"
        case let .gatewayDown(m): m
        case let .volumeMissing(m): m
        case let .modelUnavailable(m): m
        case let .cloudModelBlocked(m): m
        case let .failed(m): m
        }
    }

    public var isUsable: Bool {
        switch self {
        case .ready, .summarizing: true
        default: false
        }
    }
}

/// Structured semantics produced by the local LLM (or parsed from its reply).
public struct TaskSemantics: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var status: TaskStatus?

    public init(title: String? = nil, summary: String? = nil, status: TaskStatus? = nil) {
        self.title = title
        self.summary = summary
        self.status = status
    }
}

/// Builds prompts and calls local-agent `submit_inference` / `get_job`.
public struct TaskSummarizer: Sendable {
    public var config: TaskLLMConfig
    public var mcp: LocalAgentMCP

    public init(config: TaskLLMConfig, mcp: LocalAgentMCP? = nil) {
        self.config = config
        if let mcp {
            self.mcp = mcp
        } else if let url = config.mcpEndpoint {
            self.mcp = LocalAgentMCP(config: .init(url: url))
        } else {
            self.mcp = LocalAgentMCP()
        }
    }

    /// Probe gateway + storage + model without running inference.
    public func probe() async -> TaskLLMStatus {
        guard config.enabled else { return .disabled }
        if config.refusesCloudModel {
            return .cloudModelBlocked("Model \(config.modelID) looks cloud-hosted. Choose a local hf:/ollama: model.")
        }
        guard config.mcpEndpoint != nil else {
            return .gatewayDown("Local-agent MCP URL is invalid.")
        }
        do {
            let storage = try await mcp.callTool(name: "model_storage_status") as? [String: Any]
            let volumeOK = (storage?["external_volume_available"] as? Bool)
                ?? FileManager.default.fileExists(atPath: config.modelsVolumePath)
            if volumeOK == false {
                let hint = (storage?["mount_hint"] as? String)
                    ?? "Run models-on if \(config.modelsVolumePath) is missing."
                // Still allow models that live off the volume (configured internals).
                let models = try await mcp.callTool(name: "list_models") as? [String: Any]
                if !modelAvailable(config.modelID, in: models) {
                    return .volumeMissing("Models disk unmounted. \(hint)")
                }
            }
            let models = try await mcp.callTool(name: "list_models") as? [String: Any]
            if !modelAvailable(config.modelID, in: models) {
                return .modelUnavailable("Model \(config.modelID) isn't available. Call list_models / run models-on.")
            }
            return .ready
        } catch {
            return .gatewayDown(error.localizedDescription)
        }
    }

    public func summarize(context: String) async throws -> TaskSemantics {
        if config.refusesCloudModel {
            throw LocalAgentMCP.MCPError.rpc("Cloud models are blocked for board summaries.")
        }
        let prompt = Self.prompt(for: context)
        let submitted = try await mcp.callTool(name: "submit_inference", arguments: [
            "model_id": config.modelID,
            "prompt": prompt,
            "options": [
                "max_tokens": 220,
                "temperature": 0.2,
                "timeout_seconds": 120,
            ],
        ]) as? [String: Any]
        guard let jobID = submitted?["id"] as? String else {
            throw LocalAgentMCP.MCPError.decode("submit_inference returned no job id")
        }
        let text = try await waitForText(jobID: jobID)
        return Self.parse(text)
    }

    private func waitForText(jobID: String, attempts: Int = 90) async throws -> String {
        for _ in 0..<attempts {
            try await Swift.Task.sleep(nanoseconds: 500_000_000)
            let status = try await mcp.callTool(name: "get_job", arguments: ["job_id": jobID]) as? [String: Any]
            let state = status?["status"] as? String ?? ""
            if state == "failed" || state == "cancelled" {
                let err = ((status?["error"] as? String) ?? (status?["message"] as? String) ?? state)
                throw LocalAgentMCP.MCPError.rpc(err)
            }
            if state == "completed" {
                if let result = status?["result"] as? [String: Any] {
                    if let message = result["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        return content
                    }
                    if let text = result["text"] as? String { return text }
                }
                throw LocalAgentMCP.MCPError.decode("Job completed without text")
            }
        }
        throw LocalAgentMCP.MCPError.transport("Local LLM timed out.")
    }

    private func modelAvailable(_ id: String, in inventory: [String: Any]?) -> Bool {
        guard let models = inventory?["models"] as? [[String: Any]] else { return false }
        return models.contains { ($0["id"] as? String) == id }
    }

    public static func prompt(for context: String) -> String {
        """
        Summarize coding-agent work for a calm local task board. Use only the facts below.
        Reply with ONE JSON object and nothing else. Keys (all required when possible):
        - title: max 50 characters, no quotes inside
        - summary: max 12 words, one plain sentence
        - status: exactly one of backlog, inProgress, blocked, done, cancelled
        Prefer blocked when the agent needs the user; inProgress when working; done when finished.
        Do not invent files, people, or work not present in the facts.

        Session facts:
        \(context)
        """
    }

    /// Tolerates fenced JSON and tiny-model duplicates.
    public static func parse(_ raw: String) -> TaskSemantics {
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
        if let data = unfenced.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return semantics(from: obj)
        }
        // Last resort: find the first {...} block.
        if let start = unfenced.firstIndex(of: "{"), let end = unfenced.lastIndex(of: "}"),
           start < end {
            let slice = String(unfenced[start...end])
            if let data = slice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return semantics(from: obj)
            }
        }
        let summary = Trim.clean(trimmed, max: 240)
        return TaskSemantics(summary: summary)
    }

    private static func semantics(from obj: [String: Any]) -> TaskSemantics {
        let title = (obj["title"] as? String).flatMap { Trim.clean($0, max: 50) }
        let summary = (obj["summary"] as? String).flatMap { Trim.clean($0, max: 90) }
        let statusName = obj["status"] as? String
        let status = statusName.flatMap(TaskStatus.init(rawValue:))
        return TaskSemantics(title: title, summary: summary, status: status)
    }
}

/// Compact, privacy-aware context string for the summarizer.
public enum SessionContextBuilder {
    public static func make(session: Session, transcriptExcerpt: String? = nil, maxChars: Int = 2500) -> String {
        var lines: [String] = []
        lines.append("agent: \(session.agentLabel)")
        lines.append("session_id: \(session.sessionId)")
        if let project = session.project { lines.append("project: \(project)") }
        if let cwd = session.cwd { lines.append("cwd: \(cwd)") }
        if let title = session.title { lines.append("title: \(title)") }
        lines.append("mood: \(Describe.mood(session.mood))")
        lines.append("activity: \(Describe.activity(session.activity))")
        if let excerpt = transcriptExcerpt, !excerpt.isEmpty {
            lines.append("transcript_excerpt:")
            lines.append(Trim.truncate(excerpt, max: maxChars))
        }
        return lines.joined(separator: "\n")
    }
}
