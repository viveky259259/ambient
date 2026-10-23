import Foundation

/// Preferences for Ambient's board summarizer (local-agent MCP only).
public struct TaskLLMConfig: Codable, Equatable, Sendable {
    /// Master switch. When off, the board uses metadata heuristics only.
    public var enabled: Bool
    /// Streamable HTTP MCP endpoint for local-agent (default loopback LaunchAgent).
    public var mcpURL: String
    /// Exact model id from `list_models`, e.g. `hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit`.
    public var modelID: String
    /// A model folder or `.gguf` file on this Mac. When set it wins over `modelID`: the gateway runs it if it
    /// knows that path, otherwise Ambient runs it directly with the runtime its format needs.
    public var modelPath: String
    /// Python with mlx-lm / mlx-vlm for direct runs; empty to find one.
    public var pythonPath: String
    /// When true, Ambient may read local agent transcript stores (Claude projects, Codex index) for richer context.
    public var readTranscripts: Bool
    /// Path checked for the external models volume (`models-on` mounts here).
    public var modelsVolumePath: String
    /// Minimum seconds between LLM refreshes for the same task.
    public var minRefreshSeconds: TimeInterval

    public init(enabled: Bool = false,
                mcpURL: String = "http://127.0.0.1:5051/mcp",
                modelID: String = "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                modelPath: String = "",
                pythonPath: String = "",
                readTranscripts: Bool = false,
                modelsVolumePath: String = "/Volumes/Models",
                minRefreshSeconds: TimeInterval = 45) {
        self.enabled = enabled
        self.mcpURL = mcpURL
        self.modelID = modelID
        self.modelPath = modelPath
        self.pythonPath = pythonPath
        self.readTranscripts = readTranscripts
        self.modelsVolumePath = modelsVolumePath
        self.minRefreshSeconds = minRefreshSeconds
    }

    public var mcpEndpoint: URL? { URL(string: mcpURL) }

    public var usesModelPath: Bool { !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Cloud-tagged Ollama models are refused so session text never leaves the Mac by default.
    public var refusesCloudModel: Bool { !usesModelPath && Self.isCloudModel(modelID) }

    public static func isCloudModel(_ id: String) -> Bool {
        id.lowercased().contains(":cloud") || id.lowercased().contains("cloud/")
    }

    /// True when the configured MCP URL is not a loopback http(s) endpoint.
    public var refusesNonLoopback: Bool {
        guard let url = mcpEndpoint else { return true }
        return !Self.isLoopback(url)
    }

    /// Session text may only go to 127.0.0.1 / localhost / ::1.
    public static func isLoopback(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

/// A change to the board's model from `ambient task model` or `ambient mcp`; nil leaves a setting alone.
public struct TaskModelChange: Codable, Equatable, Sendable {
    /// A model folder or `.gguf` file; empty goes back to the gateway model id.
    public var modelPath: String?
    public var pythonPath: String?
    public var enabled: Bool?

    public init(modelPath: String? = nil, pythonPath: String? = nil, enabled: Bool? = nil) {
        self.modelPath = modelPath
        self.pythonPath = pythonPath
        self.enabled = enabled
    }
}

/// What `ambient task model` and `ambient mcp` say about the board's model: what the path is and how it runs.
public struct TaskModelReport: Sendable {
    public var config: TaskLLMConfig
    public var model: LocalModelPath?
    public var resolution: TaskModelResolution

    /// Resolves as if summaries were on, so it can say how the model would run before they are.
    public static func make(_ config: TaskLLMConfig) async -> TaskModelReport {
        var probe = config
        probe.enabled = true
        let resolution = await TaskSummarizer(config: probe).resolve()
        return TaskModelReport(config: config,
                               model: config.usesModelPath ? LocalModelPath.inspect(config.modelPath) : nil,
                               resolution: resolution)
    }

    /// Ordered for people; `ambient mcp` sends the same keys as JSON.
    public var fields: [(key: String, value: String)] {
        var out: [(key: String, value: String)] = [("summaries", config.enabled ? "on" : "off")]
        if config.usesModelPath {
            out.append(("model_path", config.modelPath))
            if let model {
                out.append(("format", model.format.label))
                if model.resolved != model.requested { out.append(("loads", model.resolved)) }
            }
        } else {
            out.append(("model_id", config.modelID))
        }
        switch resolution.route {
        case let .gateway(id, kind)?:
            out.append(("runs", "via local-agent"))
            out.append(("gateway_model", "\(id) (\(kind))"))
        case let .mlx(_, vision, python)?:
            out.append(("runs", vision ? "directly with mlx-vlm" : "directly with mlx-lm"))
            out.append(("runtime", python))
        case let .llamaCpp(_, binary)?:
            out.append(("runs", "directly with llama.cpp"))
            out.append(("runtime", binary))
        case nil:
            break
        }
        out.append(("status", resolution.status.label))
        return out
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
    case nonLoopbackBlocked(String)
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
        case let .nonLoopbackBlocked(m): m
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

/// The model the board will use and how it runs, or why it can't use one.
public enum TaskModelResolution: Equatable, Sendable {
    case ready(TaskModelRoute)
    case unavailable(TaskLLMStatus)

    public var status: TaskLLMStatus {
        switch self {
        case .ready: .ready
        case let .unavailable(status): status
        }
    }

    public var route: TaskModelRoute? {
        guard case let .ready(route) = self else { return nil }
        return route
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
    /// On-device few-shots from `~/.ambient/task-skill.json` (or bundled seed). Never calls Anthropic.
    public var skillPack: TaskSkillPack

    public init(config: TaskLLMConfig, mcp: LocalAgentMCP? = nil, skillPack: TaskSkillPack? = nil) {
        self.config = config
        self.skillPack = skillPack ?? TaskSkillStore.load()
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
        await resolve().status
    }

    /// Picks how to run the configured model: by gateway id, or for a model path, through the gateway when it
    /// knows that path and otherwise directly with the runtime the model's format needs.
    public func resolve() async -> TaskModelResolution {
        guard config.enabled else { return .unavailable(.disabled) }
        if config.usesModelPath { return await resolvePath() }
        if config.refusesCloudModel {
            return .unavailable(.cloudModelBlocked("Model \(config.modelID) looks cloud-hosted. Choose a local hf:/ollama: model."))
        }
        guard let endpoint = config.mcpEndpoint else {
            return .unavailable(.gatewayDown("Local-agent MCP URL is invalid."))
        }
        if !TaskLLMConfig.isLoopback(endpoint) {
            return .unavailable(.nonLoopbackBlocked("MCP URL must be loopback (127.0.0.1 / localhost). Session text stays on this Mac."))
        }
        do {
            let storage = try await mcp.callTool(name: "model_storage_status") as? [String: Any]
            let volumeOK = (storage?["external_volume_available"] as? Bool)
                ?? FileManager.default.fileExists(atPath: config.modelsVolumePath)
            // Models that live off the volume (configured internals) still work while it's unmounted.
            guard let entry = try await inventory().first(where: { ($0["id"] as? String) == config.modelID }) else {
                if volumeOK == false {
                    let hint = (storage?["mount_hint"] as? String)
                        ?? "Run models-on if \(config.modelsVolumePath) is missing."
                    return .unavailable(.volumeMissing("Models disk unmounted. \(hint)"))
                }
                return .unavailable(.modelUnavailable("Model \(config.modelID) isn't available. Call list_models / run models-on."))
            }
            guard Self.writesText(entry) else {
                let kind = entry["kind"] as? String ?? "unknown"
                return .unavailable(.modelUnavailable("\(config.modelID) isn't a chat or vision model (local-agent kind: \(kind))."))
            }
            return .ready(.gateway(modelID: config.modelID, kind: entry["kind"] as? String ?? "chat"))
        } catch {
            return .unavailable(.gatewayDown(error.localizedDescription))
        }
    }

    private func resolvePath() async -> TaskModelResolution {
        let requested = (config.modelPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard let model = LocalModelPath.inspect(requested) else {
            let volume = config.modelsVolumePath
            if !volume.isEmpty, requested.hasPrefix(volume + "/"), !FileManager.default.fileExists(atPath: volume) {
                return .unavailable(.volumeMissing("Models disk unmounted. Run models-on if \(volume) is missing."))
            }
            return .unavailable(.modelUnavailable("Nothing at \(requested)."))
        }
        guard model.format.writesText else {
            return .unavailable(.modelUnavailable(model.format == .media
                ? "\(model.name) is a speech, image or video model. Choose a text model."
                : "\(model.name): \(model.note ?? "unrecognized model.")"))
        }

        // The gateway first when it already knows this model: its queue, adapters and runtimes.
        var gatewayPythons: [String] = []
        if let endpoint = config.mcpEndpoint, TaskLLMConfig.isLoopback(endpoint),
           let inventory = try? await inventory() {
            if let entry = Self.entry(for: model, in: inventory), let id = entry["id"] as? String,
               Self.writesText(entry), entry["runtime_available"] as? Bool != false {
                return .ready(.gateway(modelID: id, kind: entry["kind"] as? String ?? "chat"))
            }
            gatewayPythons = inventory.compactMap { entry in
                guard ["mlx_lm", "mlx_vlm"].contains(entry["adapter"] as? String ?? ""),
                      entry["runtime_available"] as? Bool == true else { return nil }
                return entry["runtime_python"] as? String
            }
        }

        // Otherwise directly, with the runtime this format needs. Probing a Python can take a moment.
        let config = self.config, pythons = gatewayPythons
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.directRoute(for: model, config: config, gatewayPythons: pythons))
            }
        }
    }

    static func directRoute(for model: LocalModelPath, config: TaskLLMConfig, gatewayPythons: [String]) -> TaskModelResolution {
        switch model.format {
        case .mlxText, .mlxVision:
            let vision = model.format == .mlxVision
            let (module, package) = vision ? ("mlx_vlm", "mlx-vlm") : ("mlx_lm", "mlx-lm")
            guard let python = LocalRuntimes.python(with: module, configured: config.pythonPath,
                                                    gatewayPythons: gatewayPythons) else {
                let which = config.pythonPath.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "No Python with \(package) found" : "\(config.pythonPath) can't import \(module)"
                return .unavailable(.modelUnavailable(
                    "\(which). Install it with pip install \(package), set Python for MLX, or register the model with local-agent."))
            }
            return .ready(.mlx(path: model.resolved, vision: vision, python: python))
        case .gguf:
            guard let binary = LocalRuntimes.llamaCpp() else {
                return .unavailable(.modelUnavailable("GGUF models need llama.cpp: brew install llama.cpp."))
            }
            return .ready(.llamaCpp(path: model.resolved, binary: binary))
        case .media, .unknown:
            return .unavailable(.modelUnavailable("\(model.name) can't write summaries."))
        }
    }

    /// Resolves the model, then summarizes with it.
    public func summarize(context: String) async throws -> TaskSemantics {
        switch await resolve() {
        case let .ready(route): try await summarize(context: context, via: route)
        case let .unavailable(status): throw LocalAgentMCP.MCPError.rpc(status.label)
        }
    }

    public func summarize(context: String, via route: TaskModelRoute) async throws -> TaskSemantics {
        let prompt = Self.prompt(for: context, skill: skillPack)
        guard case let .gateway(modelID, _) = route else {
            let text = try await LocalModelRunner.generate(route, prompt: prompt, maxTokens: 220, temperature: 0.2,
                                                           timeout: 120)
            return Self.parse(text)
        }
        if TaskLLMConfig.isCloudModel(modelID) {
            throw LocalAgentMCP.MCPError.rpc("Cloud models are blocked for board summaries.")
        }
        guard let endpoint = config.mcpEndpoint, TaskLLMConfig.isLoopback(endpoint) else {
            throw LocalAgentMCP.MCPError.nonLoopback
        }
        let submitted = try await mcp.callTool(name: "submit_inference", arguments: [
            "model_id": modelID,
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
            try await Task.sleep(nanoseconds: 500_000_000)
            let status = try await mcp.callTool(name: "get_job", arguments: ["job_id": jobID]) as? [String: Any]
            let state = status?["status"] as? String ?? ""
            if state == "failed" || state == "cancelled" {
                let err = ((status?["error"] as? String) ?? (status?["message"] as? String) ?? state)
                throw LocalAgentMCP.MCPError.rpc(err)
            }
            if state == "completed" {
                if let result = status?["result"] as? [String: Any], let text = Self.text(fromResult: result) {
                    return text
                }
                throw LocalAgentMCP.MCPError.decode("Job completed without text")
            }
        }
        throw LocalAgentMCP.MCPError.transport("Local LLM timed out.")
    }

    /// Chat and vision jobs reply with a message, agent jobs with text, and `command` models with an output file.
    static func text(fromResult result: [String: Any]) -> String? {
        if let message = result["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        if let text = result["text"] as? String { return text }
        guard let file = (result["files"] as? [String])?.first,
              let size = (try? FileManager.default.attributesOfItem(atPath: file))?[.size] as? NSNumber,
              size.intValue <= 256 * 1024,
              let data = FileManager.default.contents(atPath: file) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func inventory() async throws -> [[String: Any]] {
        let reply = try await mcp.callTool(name: "list_models") as? [String: Any]
        return reply?["models"] as? [[String: Any]] ?? []
    }

    /// The gateway inventory entry that loads the same files as `model`, symlinks resolved on both sides.
    static func entry(for model: LocalModelPath, in inventory: [[String: Any]]) -> [String: Any]? {
        func canonical(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path }
        let wanted = Set([model.requested, model.resolved].map(canonical))
        return inventory.first { entry in
            guard let path = entry["path"] as? String else { return false }
            return wanted.contains(canonical(path))
        }
    }

    /// Chat and vision models write text; a `command` model does when its configured output is a text file.
    static func writesText(_ entry: [String: Any]) -> Bool {
        switch entry["kind"] as? String {
        case "chat", "vision": true
        case "custom":
            ["txt", "json", "md"].contains(URL(fileURLWithPath: entry["output_name"] as? String ?? "").pathExtension.lowercased())
        default: false
        }
    }

    public static func prompt(for context: String, skill: TaskSkillPack = .bundledSeed) -> String {
        let skillBlock = skill.promptFragment(maxExamples: 4)
        return """
        Summarize coding-agent work for a calm local task board. Use only the facts below.
        Reply with ONE JSON object and nothing else. Keys (all required when possible):
        - title: max 50 characters, no quotes inside
        - summary: max 12 words, one plain sentence
        - status: exactly one of backlog, inProgress, blocked, done, cancelled
        Prefer blocked when the agent needs the user; inProgress when working; done when finished.
        Do not invent files, people, or work not present in the facts.

        \(skillBlock)

        Session facts:
        \(context)
        """
    }

    /// Tolerates fenced JSON, tiny-model duplicates and reasoning models' `<think>` blocks.
    public static func parse(_ raw: String) -> TaskSemantics {
        let trimmed = withoutThinking(raw).trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// The answer after a reasoning model's thinking. Templates often open `<think>` in the prompt, so a reply may
    /// carry only the closing tag; thinking cut off by the token limit leaves no answer at all.
    static func withoutThinking(_ raw: String) -> String {
        if let close = raw.range(of: "</think>", options: .backwards) { return String(raw[close.upperBound...]) }
        if let open = raw.range(of: "<think>") { return String(raw[..<open.lowerBound]) }
        return raw
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
