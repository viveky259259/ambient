import Foundation

/// How the board reaches its model: which runtime, and what it loads.
public enum TaskModelRoute: Codable, Equatable, Sendable {
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

    /// How long an MLX model stays loaded after a summary: longer than the board's 45 seconds between refreshes of a
    /// task, so a busy board reads the weights once, and short enough to give the memory back soon after.
    static let idleSeconds: TimeInterval = 120

    /// How long a runtime that has exited gets to finish writing, since a child it started can keep the pipes open.
    static let exitGrace: TimeInterval = 5

    /// llama.cpp prompt files older than this belong to a run that never cleaned up: the app quit or crashed.
    static let staleAfter: TimeInterval = 600

    static let promptPrefix = "ambient-prompt-"

    /// When leftover prompt files were last looked for. Only touched on the shared queue.
    nonisolated(unsafe) private static var sweptAt = Date.distantPast

    /// What's running now, so quitting stops it.
    private static let live = Live()

    /// Cancelling the calling task skips a run still waiting for the queue, or stops the runtime of one under way.
    public static func generate(_ route: TaskModelRoute, prompt: String, maxTokens: Int, temperature: Double,
                                timeout: TimeInterval) async throws -> String {
        switch route {
        case .gateway:
            throw RunError.launch("gateway models run through local-agent")
        case let .mlx(path, vision, python):
            // The prompt goes on standard input, not argv, so session text never shows up in `ps`.
            let request: [String: Any] = ["path": path, "vision": vision, "prompt": prompt,
                                          "max_tokens": maxTokens, "temperature": temperature]
            let line = try JSONSerialization.data(withJSONObject: request) + Data("\n".utf8)
            let key = Worker.Key(python: python, path: path, vision: vision)
            let reply = try await onQueue { job in try ask(key, line: line, timeout: timeout, job: job) }
            return try parseMarked(reply)
        case let .llamaCpp(path, binary):
            return try await onQueue { job in
                if Date().timeIntervalSince(sweptAt) > staleAfter {
                    sweepPromptFiles()
                    sweptAt = Date()
                }
                // llama.cpp reads prompts from a file; keep it private to the user and gone afterwards.
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(promptPrefix)\(UUID().uuidString).txt")
                guard FileManager.default.createFile(atPath: file.path, contents: Data(prompt.utf8),
                                                     attributes: [.posixPermissions: 0o600]) else {
                    throw RunError.launch("couldn't write the prompt file")
                }
                defer { try? FileManager.default.removeItem(at: file) }
                let out = try runOnce(binary, llamaArguments(binary: binary, model: path, promptFile: file.path,
                                                             maxTokens: maxTokens, temperature: temperature),
                                      timeout: timeout, job: job)
                let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw RunError.noOutput }
                return text
            }
        }
    }

    /// Stops the loaded model and any run under way, and starts no runtime after that. For quitting.
    public static func stopAll() {
        live.stopAll(closing: true)
    }

    /// Stops the loaded model and any run under way, for tests.
    static func unload() {
        live.stopAll(closing: false)
    }

    static func llamaArguments(binary: String, model: String, promptFile: String, maxTokens: Int,
                               temperature: Double) -> [String] {
        // `-st` is one chat turn with the model's own template, then exit; a model without a template gets plain
        // completion. Both `llama-completion` and the chat-only `llama-cli` that replaced the old one take it.
        ["-m", model, "-f", promptFile, "-n", String(maxTokens), "--temp", String(temperature),
         "--no-display-prompt", "-st"]
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

    /// Removes prompt files a quit or crash left behind. Old ones only: another copy of Ambient may be mid-run.
    static func sweepPromptFiles(in folder: URL = FileManager.default.temporaryDirectory, now: Date = Date()) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(promptPrefix) {
            let file = folder.appendingPathComponent(name)
            guard let modified = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > staleAfter else { continue }
            try? fm.removeItem(at: file)
        }
    }

    /// Runs `work` on the shared serial queue.
    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable (Job) throws -> T) async throws -> T {
        let job = Job()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result {
                        try job.check()
                        return try work(job)
                    })
                }
            }
        } onCancel: {
            job.cancel()
        }
    }

    /// Standard output on exit status 0, for a runtime that loads, answers and exits. Runs on the shared queue.
    private static func runOnce(_ executable: String, _ arguments: [String], timeout: TimeInterval,
                                job: Job) throws -> String {
        let runtime = try ModelProcess.launch(executable, arguments, input: false)
        guard live.started(runtime) else {
            runtime.stop()
            throw CancellationError()
        }
        job.attach(runtime)
        defer {
            job.detach()
            live.finished(runtime)
        }
        let deadline = DispatchTime.now() + timeout
        var lines: [String] = []
        reading: while true {
            switch runtime.nextLine(until: deadline) {
            case let .line(line): lines.append(line)
            case .ended: break reading
            case .timedOut:
                runtime.stop()
                try job.check()
                throw RunError.timedOut
            }
        }
        try job.check()
        guard let status = runtime.status(until: deadline) else {
            runtime.stop()
            throw RunError.timedOut
        }
        guard status == 0 else { throw runtime.failure(status) }
        return lines.joined(separator: "\n")
    }

    /// Sends one request to the loaded MLX model, loading it first if it isn't the one asked for, and returns the
    /// marked reply line. Runs on the shared queue.
    private static func ask(_ key: Worker.Key, line: Data, timeout: TimeInterval, job: Job) throws -> String {
        let worker: Worker
        if let current = live.worker, current.key == key, current.runtime.isRunning {
            worker = current
        } else {
            live.worker?.runtime.stop()
            worker = Worker(key: key, runtime: try ModelProcess.launch(key.python, ["-c", mlxScript], input: true))
            guard live.adopt(worker) else {
                worker.runtime.stop()
                throw CancellationError()
            }
        }
        worker.uses += 1
        let runtime = worker.runtime
        // Lines printed since the last request are only noise.
        runtime.discardLines()
        job.attach(runtime)
        defer { job.detach() }
        runtime.send(line)
        let deadline = DispatchTime.now() + timeout
        while true {
            switch runtime.nextLine(until: deadline) {
            case let .line(reply) where reply.hasPrefix(marker):
                let uses = worker.uses
                queue.asyncAfter(deadline: .now() + idleSeconds) {
                    guard live.worker === worker, worker.uses == uses else { return }
                    worker.runtime.stop()
                    live.worker = nil
                }
                return reply
            case .line:
                continue
            case .ended:
                if live.worker === worker { live.worker = nil }
                try job.check()
                guard let status = runtime.status(until: .now() + exitGrace) else {
                    runtime.stop()
                    throw RunError.noOutput
                }
                throw status == 0 ? RunError.noOutput : runtime.failure(status)
            case .timedOut:
                runtime.stop()
                if live.worker === worker { live.worker = nil }
                try job.check()
                throw RunError.timedOut
            }
        }
    }

    /// Loads with mlx-lm (or mlx-vlm) on the first request, then answers each request line on standard input with one
    /// marked JSON line, until standard input closes. Base models without a chat template get the prompt as plain
    /// text. `enable_thinking=False` keeps reasoning models (Qwen3 and later) from spending the whole token budget
    /// thinking before the JSON; templates without that switch ignore it. Some mlx-vlm processors force
    /// `trust_remote_code` on and catch `Exception`, so loading a folder's code ends the run before any of it can start.
    static let mlxScript = """
    import json, sys
    import transformers.dynamic_module_utils as dynamic
    def refuse(*args, **kwargs):
        sys.exit("This model runs its own Python code, which Ambient won't load.")
    dynamic.get_class_in_module = dynamic.get_class_from_dynamic_module = refuse
    model = None
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        req = json.loads(line)
        if req["vision"]:
            from mlx_vlm import generate, load
            from mlx_vlm.prompt_utils import apply_chat_template
            from mlx_vlm.utils import load_config
            if model is None:
                model, processor = load(req["path"])
                config = load_config(req["path"])
            prompt = apply_chat_template(processor, config, req["prompt"], num_images=0, enable_thinking=False)
            out = generate(model, processor, prompt, max_tokens=req["max_tokens"], temperature=req["temperature"], verbose=False)
            text = getattr(out, "text", out)
        else:
            from mlx_lm import generate, load
            from mlx_lm.sample_utils import make_sampler
            if model is None:
                model, tokenizer = load(req["path"])
            prompt = req["prompt"]
            if getattr(tokenizer, "chat_template", None):
                prompt = tokenizer.apply_chat_template([{"role": "user", "content": prompt}], tokenize=False, add_generation_prompt=True, enable_thinking=False)
            text = generate(model, tokenizer, prompt=prompt, max_tokens=req["max_tokens"], sampler=make_sampler(temp=req["temperature"]), verbose=False)
        sys.stdout.write("\\n\(marker)" + json.dumps({"text": text}) + "\\n")
        sys.stdout.flush()
    """

    /// A loaded MLX model. Only touched on the shared queue, except by `stopAll`.
    final class Worker: @unchecked Sendable {
        struct Key: Equatable {
            var python: String
            var path: String
            var vision: Bool
        }

        let key: Key
        let runtime: ModelProcess
        var uses = 0

        init(key: Key, runtime: ModelProcess) {
            self.key = key
            self.runtime = runtime
        }
    }

    /// The loaded model and the run under way.
    private final class Live: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: Worker?
        private var running: ModelProcess?
        /// Set when Ambient quits: a run that was already queued must not start a runtime nobody will stop.
        private var closed = false

        var worker: Worker? {
            get { lock.lock(); defer { lock.unlock() }; return loaded }
            set { lock.lock(); loaded = newValue; lock.unlock() }
        }

        /// False once closed.
        func adopt(_ worker: Worker) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if !closed { loaded = worker }
            return !closed
        }

        /// False once closed.
        func started(_ runtime: ModelProcess) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if !closed { running = runtime }
            return !closed
        }

        func finished(_ runtime: ModelProcess) {
            lock.lock()
            if running === runtime { running = nil }
            lock.unlock()
        }

        func stopAll(closing: Bool) {
            lock.lock()
            let all = [loaded?.runtime, running].compactMap { $0 }
            loaded = nil
            running = nil
            if closing { closed = true }
            lock.unlock()
            all.forEach { $0.stop() }
        }
    }

    /// One request's hold on a runtime, so cancelling the request stops it.
    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var runtime: ModelProcess?

        func cancel() {
            lock.lock()
            cancelled = true
            let runtime = self.runtime
            lock.unlock()
            runtime?.stop()
        }

        func check() throws {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { throw CancellationError() }
        }

        func attach(_ runtime: ModelProcess) {
            lock.lock()
            self.runtime = runtime
            let cancelled = self.cancelled
            lock.unlock()
            if cancelled { runtime.stop() }
        }

        func detach() { lock.lock(); runtime = nil; lock.unlock() }
    }
}

/// A runtime process and what it has written. Both pipes are read the whole time it runs, so a chatty runtime never
/// fills one and stalls, and what it wrote stays usable even when a child it started keeps the pipes open.
final class ModelProcess: @unchecked Sendable {
    enum Next: Equatable {
        case line(String)
        /// Standard output closed, or the runtime exited and has had time to finish writing.
        case ended
        case timedOut
    }

    private let process: Process
    private let output: Output
    private let stdin: FileHandle?

    private init(process: Process, output: Output, stdin: FileHandle?) {
        self.process = process
        self.output = output
        self.stdin = stdin
    }

    static func launch(_ executable: String, _ arguments: [String], input: Bool) throws -> ModelProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Not the app's folder: Python puts the working directory first on its import path.
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = ProcessInfo.processInfo.environment.merging(LocalModelRunner.offline) { $1 }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = input ? stdin : FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        let output = Output()
        process.terminationHandler = { output.exited($0.terminationStatus) }
        do { try process.run() } catch { throw LocalModelRunner.RunError.launch(error.localizedDescription) }
        for (pipe, isStdout) in [(stdout, true), (stderr, false)] {
            let handle = pipe.fileHandleForReading
            // Threads of their own: a loaded model is read for as long as it stays loaded, too long to hold GCD's.
            Thread.detachNewThread {
                var buffer = [UInt8](repeating: 0, count: 65_536)
                while true {
                    let count = read(handle.fileDescriptor, &buffer, buffer.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { break }
                    output.received(Data(buffer[..<count]), stdout: isStdout)
                }
                output.ended(stdout: isStdout)
                try? handle.close()
            }
        }
        let writer = input ? stdin.fileHandleForWriting : nil
        // A runtime that exits before reading its input must not take the app down with SIGPIPE.
        if let writer { _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) }
        return ModelProcess(process: process, output: output, stdin: writer)
    }

    var isRunning: Bool { process.isRunning && !output.hasEnded }

    func send(_ data: Data) {
        guard let stdin else { return }
        DispatchQueue.global(qos: .utility).async { try? stdin.write(contentsOf: data) }
    }

    func discardLines() { output.discardLines() }

    func nextLine(until deadline: DispatchTime) -> Next {
        output.nextLine(until: deadline, grace: LocalModelRunner.exitGrace)
    }

    /// The exit status, once the runtime has exited and finished writing; nil if it's still running at `deadline`.
    func status(until deadline: DispatchTime) -> Int32? {
        output.status(until: deadline, grace: LocalModelRunner.exitGrace)
    }

    /// What the runtime said on standard error, as the error for a failed run.
    func failure(_ status: Int32) -> LocalModelRunner.RunError {
        let log = output.errorTail()
        return .failed(log.isEmpty ? "Local model exited with status \(status)." : log)
    }

    /// Standard input stays open until this is gone, so a request still being written fails with EPIPE instead of
    /// writing to a closed handle.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let process = self.process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Shared with the reader threads and the termination handler. Every change signals `changed`.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private let changed = DispatchSemaphore(value: 0)
        private var lines: [String] = []
        private var partial = Data()
        private var errors = Data()
        private var stdoutEnded = false, stderrEnded = false
        private var exitStatus: Int32?
        private var exitedAt: DispatchTime?

        /// The most standard error kept, from the end: a model that stays loaded can warn for a long time.
        private static let errorLimit = 64 * 1024

        var hasEnded: Bool { lock.lock(); defer { lock.unlock() }; return stdoutEnded || exitStatus != nil }

        func received(_ data: Data, stdout: Bool) {
            lock.lock()
            if stdout {
                partial.append(data)
                while let newline = partial.firstIndex(of: UInt8(ascii: "\n")) {
                    lines.append(String(decoding: partial[partial.startIndex..<newline], as: UTF8.self))
                    partial.removeSubrange(partial.startIndex...newline)
                }
            } else {
                errors.append(data)
                if errors.count > Self.errorLimit { errors.removeFirst(errors.count - Self.errorLimit) }
            }
            lock.unlock()
            changed.signal()
        }

        func ended(stdout: Bool) {
            lock.lock()
            if stdout {
                if !partial.isEmpty { lines.append(String(decoding: partial, as: UTF8.self)) }
                partial.removeAll()
                stdoutEnded = true
            } else {
                stderrEnded = true
            }
            lock.unlock()
            changed.signal()
        }

        func exited(_ status: Int32) {
            lock.lock()
            exitStatus = status
            exitedAt = .now()
            lock.unlock()
            changed.signal()
        }

        func discardLines() { lock.lock(); lines.removeAll(); lock.unlock() }

        func nextLine(until deadline: DispatchTime, grace: TimeInterval) -> Next {
            lock.lock()
            defer { lock.unlock() }
            while true {
                if !lines.isEmpty { return .line(lines.removeFirst()) }
                if stdoutEnded { return .ended }
                var wake = deadline
                if let exitedAt {
                    let done = exitedAt + grace
                    if DispatchTime.now() >= done { return .ended }
                    wake = min(wake, done)
                }
                if DispatchTime.now() >= deadline { return .timedOut }
                lock.unlock()
                _ = changed.wait(timeout: wake)
                lock.lock()
            }
        }

        func status(until deadline: DispatchTime, grace: TimeInterval) -> Int32? {
            lock.lock()
            defer { lock.unlock() }
            while true {
                if let exitStatus, let exitedAt {
                    // Standard error too, since a failure reports it.
                    if stdoutEnded && stderrEnded || DispatchTime.now() >= exitedAt + grace { return exitStatus }
                    lock.unlock()
                    _ = changed.wait(timeout: exitedAt + grace)
                    lock.lock()
                    continue
                }
                if DispatchTime.now() >= deadline { return nil }
                lock.unlock()
                _ = changed.wait(timeout: deadline)
                lock.lock()
            }
        }

        func errorTail() -> String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: errors, as: UTF8.self)
                .split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n")
        }
    }
}
