import AmbientCore
import Foundation

/// `ambient mcp`: a stdio MCP server so agents can read and set the task board's model.
/// One JSON-RPC message per line in each direction; standard output carries nothing else.
struct MCPServer {
    /// Sends a message to the running app and returns its reply, nil when the app isn't running.
    let request: (WireMessage) -> WireMessage?

    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    func run() -> Int32 {
        while let line = readLine() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let reply = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
        return 0
    }

    /// The reply line for one request line; nil for notifications.
    func handle(_ line: String) -> String? {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch message["method"] as? String {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return reply(id, [
                "protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "ambient", "version": AmbientVersion.current],
                "instructions": "Ambient's task board summarizes agent sessions with a model on this Mac. "
                    + "Use get_task_model to see which model and how it runs; set_task_model_path to point it at "
                    + "an MLX or Hugging Face folder or a .gguf file. Ambient.app must be running.",
            ])
        case "ping":
            return reply(id, [String: Any]())
        case "tools/list":
            return reply(id, ["tools": Self.tools])
        case "tools/call":
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = call(params["name"] as? String ?? "", arguments)
            return reply(id, ["content": [["type": "text", "text": text]], "isError": isError])
        default:
            return encode(["jsonrpc": "2.0", "id": id,
                           "error": ["code": -32601, "message": "Method not found: \(message["method"] ?? "")"]])
        }
    }

    static var tools: [[String: Any]] { [
        [
            "name": "get_task_model",
            "description": "Show the model Ambient's task board uses to title and summarize agent tasks, what kind "
                + "of model it is, and how Ambient runs it: through the local-agent MCP gateway, or directly with "
                + "mlx-lm, mlx-vlm or llama.cpp.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "set_task_model_path",
            "description": "Point Ambient's task board at a model on this Mac. Accepts an MLX or Hugging Face model "
                + "folder (config.json with safetensors; one with a vision_config runs with mlx-vlm), a Hugging Face "
                + "cache folder (models--org--name), or a .gguf file. Ambient runs it through the local-agent gateway "
                + "when the gateway knows that path, otherwise directly with the matching runtime, offline. "
                + "Speech, image and video models are refused. An empty path goes back to the gateway model id.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Absolute path to the model folder or .gguf file (~ allowed). Empty clears it."],
                    "python": ["type": "string", "description": "Optional Python with mlx-lm / mlx-vlm for direct MLX runs. Empty finds one."],
                    "enable": ["type": "boolean", "description": "Also turn board summaries on (true) or off (false). Omit to leave as is."],
                ],
                "required": ["path"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
    ] }

    /// Tool result text, and whether it's an error.
    func call(_ name: String, _ arguments: [String: Any]) -> (String, Bool) {
        switch name {
        case "get_task_model":
            let reply = request(.taskModelRequest)
            guard case let .taskModel(config)? = reply else { return (Self.noConfig(reply, changing: false), true) }
            return (Self.render(report(config)), false)
        case "set_task_model_path":
            guard let path = arguments["path"] as? String else { return ("path is required.", true) }
            if let problem = LocalModelPath.problem(with: path) { return (problem, true) }
            let python = (arguments["python"] as? String).map(Self.absolute)
            if let python, let problem = Self.validate(python: python) { return (problem, true) }
            let change = TaskModelChange(modelPath: path, pythonPath: python, enabled: arguments["enable"] as? Bool)
            let reply = request(.setTaskModel(change))
            guard case let .taskModel(config)? = reply else { return (Self.noConfig(reply, changing: true), true) }
            return (Self.render(report(config)), false)
        default:
            return ("Unknown tool: \(name)", true)
        }
    }

    /// `path` with `~` expanded and made absolute against the current directory, since the app runs from elsewhere.
    /// Symlinks stay as they are: a venv's python finds its packages through its own path. Empty stays empty.
    static func absolute(_ path: String) -> String {
        let trimmed = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    /// Expects a path from `absolute(_:)`.
    static func validate(python: String) -> String? {
        guard !python.isEmpty, !FileManager.default.isExecutableFile(atPath: python) else { return nil }
        return "No executable Python at \(python). Nothing changed."
    }

    /// Why a task-model request brought back no settings.
    static func noConfig(_ reply: WireMessage?, changing: Bool) -> String {
        guard case .taskModelTimedOut? = reply else { return "Ambient isn't running. Open Ambient.app, then try again." }
        return changing ? "Ambient didn't confirm the change in time. It may still apply; check the model again in a moment."
            : "Ambient didn't answer in time. Try again in a moment."
    }

    private func report(_ config: TaskLLMConfig) -> TaskModelReport {
        blocking { await TaskModelReport.make(config) }
    }

    static func render(_ report: TaskModelReport) -> String {
        var object: [String: String] = [:]
        for field in report.fields { object[field.key] = field.value }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func reply(_ id: Any, _ result: [String: Any]) -> String? {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encode(_ object: [String: Any]) -> String? {
        // Without .withoutEscapingSlashes paths come out as \/Users\/…, which is valid but noisy.
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Waits for async work from the CLI's synchronous code.
func blocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
    let box = BlockingBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task {
        box.value = await work()
        done.signal()
    }
    done.wait()
    return box.value!
}

private final class BlockingBox<T>: @unchecked Sendable {
    var value: T?
}
