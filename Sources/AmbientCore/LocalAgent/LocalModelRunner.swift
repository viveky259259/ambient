import Foundation

/// How the board reaches its model: which runtime, and what it loads.
public enum TaskModelRoute: Equatable, Sendable {
    /// The local-agent gateway, by model id. `kind` is the gateway's: chat, vision or custom.
    case gateway(modelID: String, kind: String)
    /// mlx-lm (or mlx-vlm for a vision model) in a Python that has it.
    case mlx(path: String, vision: Bool, python: String)
    /// llama.cpp's completion tool.
    case llamaCpp(path: String, binary: String)

    public var label: String {
        switch self {
        case let .gateway(id, _): "via local-agent (\(id))"
        case let .mlx(_, vision, _): vision ? "with mlx-vlm on this Mac" : "with mlx-lm on this Mac"
        case .llamaCpp: "with llama.cpp on this Mac"
        }
    }
}

/// Runs a model on disk directly, without the local-agent gateway. One model at a time, like the gateway's queue,
/// so two summaries never load two copies of the weights.
public enum LocalModelRunner {
    public enum RunError: LocalizedError, Equatable, CustomStringConvertible, Sendable {
        case launch(String)
        case timedOut
        case failed(String)
        case noOutput

        public var description: String {
            switch self {
            case let .launch(message): "Couldn't start the model runtime: \(message)"
            case .timedOut: "Local model timed out."
            case let .failed(log): log
            case .noOutput: "The local model returned no text."
            }
        }

        public var errorDescription: String? { description }
    }

    private static let queue = DispatchQueue(label: "com.viveky259259.Ambient.localmodel", qos: .utility)

    /// Keeps Hugging Face libraries from reaching the network: weights must already be on disk.
    static let offline = ["HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_DATASETS_OFFLINE": "1",
                          "TOKENIZERS_PARALLELISM": "false"]

    /// Marks the result line, since runtimes print their own warnings to standard output.
    static let marker = "AMBIENT_RESULT "

    public static func generate(_ route: TaskModelRoute, prompt: String, maxTokens: Int, temperature: Double,
                                timeout: TimeInterval) async throws -> String {
        switch route {
        case .gateway:
            throw RunError.launch("gateway models run through local-agent")
        case let .mlx(path, vision, python):
            // The prompt goes on standard input, not argv, so session text never shows up in `ps`.
            let request: [String: Any] = ["path": path, "vision": vision, "prompt": prompt,
                                          "max_tokens": maxTokens, "temperature": temperature]
            let input = try JSONSerialization.data(withJSONObject: request)
            let out = try await run(python, ["-c", mlxScript], input: input, timeout: timeout)
            return try parseMarked(out)
        case let .llamaCpp(path, binary):
            // llama.cpp reads prompts from a file; keep it private to the user and gone afterwards.
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-prompt-\(UUID().uuidString).txt")
            guard FileManager.default.createFile(atPath: file.path, contents: Data(prompt.utf8),
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw RunError.launch("couldn't write the prompt file")
            }
            defer { try? FileManager.default.removeItem(at: file) }
            let out = try await run(binary, llamaArguments(binary: binary, model: path, promptFile: file.path,
                                                           maxTokens: maxTokens, temperature: temperature),
                                    input: nil, timeout: timeout)
            let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RunError.noOutput }
            return text
        }
    }

    static func llamaArguments(binary: String, model: String, promptFile: String, maxTokens: Int,
                               temperature: Double) -> [String] {
        var args = ["-m", model, "-f", promptFile, "-n", String(maxTokens), "--temp", String(temperature),
                    "--no-display-prompt"]
        // `llama-cli` became chat-first; `llama-completion` is the plain-completion tool that replaced that mode.
        if URL(fileURLWithPath: binary).lastPathComponent == "llama-cli" { args.append("-no-cnv") }
        return args
    }

    static func parseMarked(_ stdout: String) throws -> String {
        guard let line = stdout.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix(marker) }),
              let data = String(line.dropFirst(marker.count)).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            throw RunError.noOutput
        }
        return text
    }

    /// Standard output on exit status 0. Runs on the shared serial queue.
    static func run(_ executable: String, _ arguments: [String], input: Data?, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try runBlocking(executable, arguments, input: input, timeout: timeout) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], input: Data?,
                                    timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Not the app's folder: Python puts the working directory first on its import path.
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = ProcessInfo.processInfo.environment.merging(offline) { $1 }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw RunError.launch(error.localizedDescription) }

        // Drain both pipes while the process runs, or a chatty runtime fills one and stalls.
        let group = DispatchGroup()
        final class Box: @unchecked Sendable { var data = Data() }
        let out = Box(), err = Box()
        for (pipe, box) in [(stdout, out), (stderr, err)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        if let input {
            let writer = stdin.fileHandleForWriting
            // A runtime that exits before reading its input must not take the app down with SIGPIPE.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global(qos: .utility).async {
                try? writer.write(contentsOf: input)
                try? writer.close()
            }
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 3) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            // A child it started may still hold the pipes open; don't wait on it.
            _ = group.wait(timeout: .now() + 1)
            throw RunError.timedOut
        }
        group.wait()
        guard process.terminationStatus == 0 else {
            let log = String(decoding: err.data, as: UTF8.self)
                .split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n")
            throw RunError.failed(log.isEmpty ? "Local model exited with status \(process.terminationStatus)." : log)
        }
        return String(decoding: out.data, as: UTF8.self)
    }

    /// Loads with mlx-lm (or mlx-vlm) and prints one marked JSON line. Base models without a chat template get the
    /// prompt as plain text. `enable_thinking=False` keeps reasoning models (Qwen3 and later) from spending the whole
    /// token budget thinking before the JSON; templates without that switch ignore it.
    static let mlxScript = """
    import json, sys
    req = json.load(sys.stdin)
    if req["vision"]:
        from mlx_vlm import generate, load
        from mlx_vlm.prompt_utils import apply_chat_template
        from mlx_vlm.utils import load_config
        model, processor = load(req["path"])
        prompt = apply_chat_template(processor, load_config(req["path"]), req["prompt"], num_images=0, enable_thinking=False)
        out = generate(model, processor, prompt, max_tokens=req["max_tokens"], temperature=req["temperature"], verbose=False)
        text = getattr(out, "text", out)
    else:
        from mlx_lm import generate, load
        from mlx_lm.sample_utils import make_sampler
        model, tokenizer = load(req["path"])
        prompt = req["prompt"]
        if getattr(tokenizer, "chat_template", None):
            prompt = tokenizer.apply_chat_template([{"role": "user", "content": prompt}], tokenize=False, add_generation_prompt=True, enable_thinking=False)
        text = generate(model, tokenizer, prompt=prompt, max_tokens=req["max_tokens"], sampler=make_sampler(temp=req["temperature"]), verbose=False)
    sys.stdout.write("\\n\(marker)" + json.dumps({"text": text}) + "\\n")
    """
}
