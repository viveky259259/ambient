import Foundation
import Testing
@testable import AmbientCore

/// A scratch folder for fake models and runtimes, removed when the test ends.
private final class Scratch {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ path: String, _ text: String = "") throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// An executable shell script standing in for python or llama.cpp.
    func tool(_ name: String, _ body: String) throws -> String {
        let file = try self.file(name, "#!/bin/sh\n" + body + "\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }
}

@Suite struct LocalModelPathTests {
    @Test func missingPathIsNil() {
        #expect(LocalModelPath.inspect("/nonexistent/ambient/model") == nil)
        #expect(LocalModelPath.inspect("   ") == nil)
    }

    @Test func problemsWithAChosenPath() throws {
        let s = try Scratch()
        try s.file("qwen/config.json", #"{"model_type":"qwen2"}"#)
        try s.file("qwen/model.safetensors")
        try s.file("whisper-large/config.json", #"{"model_type":"whisper"}"#)
        try s.file("whisper-large/model.safetensors")
        #expect(LocalModelPath.problem(with: " ") == nil)
        #expect(LocalModelPath.problem(with: s.url.appendingPathComponent("qwen").path) == nil)
        #expect(LocalModelPath.problem(with: "models/qwen") == "Use an absolute path.")
        #expect(LocalModelPath.problem(with: "/nonexistent/ambient/model") == "Nothing at /nonexistent/ambient/model.")
        #expect(LocalModelPath.problem(with: s.url.appendingPathComponent("whisper-large").path)?.hasSuffix("Nothing changed.") == true)
        try s.file("empty/readme.md")
        #expect(LocalModelPath.problem(with: s.url.appendingPathComponent("empty").path)
            == "empty: No config.json or .gguf file in this folder. Nothing changed.")
    }

    @Test func foldersThatBringTheirOwnCodeAreRefused() throws {
        let s = try Scratch()
        try s.file("custom/config.json", #"{"model_type":"qwen2_vl","vision_config":{},"model_file":"custom.py"}"#)
        try s.file("custom/model.safetensors")
        let model = try #require(LocalModelPath.inspect(s.url.appendingPathComponent("custom").path))
        #expect(model.format == .unknown)
        #expect(model.note?.contains("model_file") == true)
        #expect(LocalModelPath.problem(with: s.url.appendingPathComponent("custom").path)?.contains("model_file") == true)
    }

    @Test func nullVisionConfigIsATextModel() throws {
        let s = try Scratch()
        try s.file("text/config.json", #"{"model_type":"qwen2","vision_config":null}"#)
        try s.file("text/model.safetensors")
        #expect(LocalModelPath.inspect(s.url.appendingPathComponent("text").path)?.format == .mlxText)
    }

    @Test func ggufRepoWithAConfigFileStaysGGUF() throws {
        let s = try Scratch()
        try s.file("repo/config.json", #"{"model_type":"llama"}"#)
        try s.file("repo/model-Q4.gguf")
        let model = try #require(LocalModelPath.inspect(s.url.appendingPathComponent("repo").path))
        #expect(model.format == .gguf)
        #expect(model.resolved.hasSuffix("repo/model-Q4.gguf"))
    }

    @Test func chosenGGUFFilesGetTheSameChecksAsFolders() throws {
        let s = try Scratch()
        #expect(LocalModelPath.inspect(try s.file("flux1-dev-Q4.gguf").path)?.format == .media)
        #expect(LocalModelPath.inspect(try s.file("whisper-large.gguf").path)?.format == .media)
        let projector = try #require(LocalModelPath.inspect(try s.file("mmproj-f16.gguf").path))
        #expect(projector.format == .unknown)
        #expect(projector.note?.contains("main .gguf") == true)
    }

    @Test func mlxTextAndVisionFolders() throws {
        let s = try Scratch()
        try s.file("qwen/config.json", #"{"model_type":"qwen2"}"#)
        try s.file("qwen/model.safetensors")
        let text = try #require(LocalModelPath.inspect(s.url.appendingPathComponent("qwen").path))
        #expect(text.format == .mlxText)
        #expect(text.resolved == s.url.appendingPathComponent("qwen").path)

        try s.file("vl/config.json", #"{"model_type":"qwen2_vl","vision_config":{}}"#)
        try s.file("vl/model.safetensors.index.json", "{}")
        #expect(LocalModelPath.inspect(s.url.appendingPathComponent("vl").path)?.format == .mlxVision)
    }

    @Test func configWithoutSafetensorsIsUnknownWithAHint() throws {
        let s = try Scratch()
        try s.file("torch/config.json", "{}")
        try s.file("torch/pytorch_model.bin")
        let model = try #require(LocalModelPath.inspect(s.url.appendingPathComponent("torch").path))
        #expect(model.format == .unknown)
        #expect(model.note?.contains("mlx_lm.convert") == true)
    }

    @Test func ggufFileAndFolderSkipProjector() throws {
        let s = try Scratch()
        let file = try s.file("llama.gguf")
        #expect(LocalModelPath.inspect(file.path)?.format == .gguf)

        try s.file("split/mmproj-f16.gguf")
        try s.file("split/model-00002-of-00002.gguf")
        try s.file("split/model-00001-of-00002.gguf")
        let folder = try #require(LocalModelPath.inspect(s.url.appendingPathComponent("split").path))
        #expect(folder.format == .gguf)
        #expect(folder.resolved.hasSuffix("split/model-00001-of-00002.gguf"))
    }

    @Test func huggingFaceCacheRepoLoadsPinnedSnapshot() throws {
        let s = try Scratch()
        let repo = "models--mlx-community--Qwen2.5-0.5B-Instruct-4bit"
        try s.file("\(repo)/refs/main", "def456\n")
        try s.file("\(repo)/snapshots/abc123/config.json", "{}")
        try s.file("\(repo)/snapshots/abc123/model.safetensors")
        try s.file("\(repo)/snapshots/def456/config.json", "{}")
        try s.file("\(repo)/snapshots/def456/model.safetensors")
        let model = try #require(LocalModelPath.inspect(s.url.appendingPathComponent(repo).path))
        #expect(model.format == .mlxText)
        #expect(model.resolved.hasSuffix("snapshots/def456"))
        #expect(model.requested.hasSuffix(repo))
        #expect(model.name == "mlx-community/Qwen2.5-0.5B-Instruct-4bit")
    }

    @Test func speechModelsAreMedia() throws {
        let s = try Scratch()
        try s.file("whisper-large/config.json", #"{"model_type":"whisper"}"#)
        try s.file("whisper-large/model.safetensors")
        try s.file("tts/config.json", #"{"model_type":"kokoro"}"#)
        try s.file("tts/model.safetensors")
        #expect(LocalModelPath.inspect(s.url.appendingPathComponent("whisper-large").path)?.format == .media)
        #expect(LocalModelPath.inspect(s.url.appendingPathComponent("tts").path)?.format == .media)
        #expect(!LocalModelFormat.media.writesText)
    }
}

@Suite struct GatewayInventoryTests {
    @Test func matchesInventoryPathThroughSymlinks() throws {
        let s = try Scratch()
        try s.file("real/config.json", "{}")
        try s.file("real/model.safetensors")
        let link = s.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: s.url.appendingPathComponent("real"))
        let model = try #require(LocalModelPath.inspect(link.path))
        let inventory: [[String: Any]] = [
            ["id": "hf:other", "path": "/elsewhere"],
            ["id": "local:real", "path": s.url.appendingPathComponent("real").path, "kind": "chat"],
        ]
        #expect(TaskSummarizer.entry(for: model, in: inventory)?["id"] as? String == "local:real")
    }

    @Test func onlyTextKindsCanSummarize() {
        #expect(TaskSummarizer.writesText(["kind": "chat"]))
        #expect(TaskSummarizer.writesText(["kind": "vision"]))
        #expect(!TaskSummarizer.writesText(["kind": "speech"]))
        #expect(!TaskSummarizer.writesText(["kind": "unknown"]))
        #expect(TaskSummarizer.writesText(["kind": "custom", "output_name": "reply.txt"]))
        #expect(!TaskSummarizer.writesText(["kind": "custom", "output_name": "song.wav"]))
        #expect(!TaskSummarizer.writesText(["kind": "custom"]))
    }

    @Test func readsTextFromEachResultShape() throws {
        #expect(TaskSummarizer.text(fromResult: ["message": ["role": "assistant", "content": "chat"]]) == "chat")
        #expect(TaskSummarizer.text(fromResult: ["text": "agent"]) == "agent")
        let s = try Scratch()
        let out = try s.file("job/output.txt", #"{"title":"From a command"}"#)
        #expect(TaskSummarizer.text(fromResult: ["files": [out.path]]) == #"{"title":"From a command"}"#)
        #expect(TaskSummarizer.text(fromResult: ["files": ["/nonexistent/out.txt"]]) == nil)
    }

    @Test func readsOnlyRegularTextOutputs() throws {
        let s = try Scratch()
        let key = try s.file("job/id_ed25519", "secret")
        #expect(TaskSummarizer.text(fromResult: ["files": [key.path]]) == nil)
        try FileManager.default.createSymbolicLink(atPath: s.url.appendingPathComponent("job/link.txt").path,
                                                   withDestinationPath: key.path)
        #expect(TaskSummarizer.text(fromResult: ["files": [s.url.appendingPathComponent("job/link.txt").path]]) == nil)
        // A FIFO would block the read forever.
        let fifo = s.url.appendingPathComponent("job/pipe.txt").path
        #expect(mkfifo(fifo, 0o600) == 0)
        #expect(TaskSummarizer.text(fromResult: ["files": [fifo]]) == nil)
        try s.file("job/folder.txt/x")
        #expect(TaskSummarizer.text(fromResult: ["files": [s.url.appendingPathComponent("job/folder.txt").path]]) == nil)
        let upper = try s.file("job/OUT.TXT", "upper")
        #expect(TaskSummarizer.text(fromResult: ["files": [upper.path]]) == "upper")
    }
}

@Suite struct TaskModelRouteTests {
    /// A loopback port nothing listens on, so the gateway check fails fast and resolution goes direct.
    private func config(path: String, python: String = "") -> TaskLLMConfig {
        TaskLLMConfig(enabled: true, mcpURL: "http://127.0.0.1:9/mcp", modelPath: path, pythonPath: python)
    }

    @Test func modelPathSkipsCloudCheckOnModelID() {
        var config = TaskLLMConfig(enabled: true, modelID: "ollama:big:cloud")
        #expect(config.refusesCloudModel)
        config.modelPath = "/models/qwen"
        #expect(!config.refusesCloudModel)
    }

    @Test func mlxFolderRunsDirectlyWithAPythonThatHasMLX() async throws {
        let s = try Scratch()
        try s.file("qwen/config.json", "{}")
        try s.file("qwen/model.safetensors")
        let python = try s.tool("python", "exit 0")
        let resolution = await TaskSummarizer(config: config(path: s.url.appendingPathComponent("qwen").path, python: python)).resolve()
        #expect(resolution == .ready(.mlx(path: s.url.appendingPathComponent("qwen").path, vision: false, python: python)))
    }

    @Test func chosenPythonWithoutMLXSaysSo() async throws {
        let s = try Scratch()
        try s.file("vl/config.json", #"{"vision_config":{}}"#)
        try s.file("vl/model.safetensors")
        let python = try s.tool("python", "exit 1")
        let resolution = await TaskSummarizer(config: config(path: s.url.appendingPathComponent("vl").path, python: python)).resolve()
        guard case let .unavailable(.modelUnavailable(message)) = resolution else {
            Issue.record("Expected modelUnavailable, got \(resolution)")
            return
        }
        #expect(message.contains("can't import mlx_vlm"))
    }

    @Test func missingAndMediaPathsAreUnavailable() async throws {
        let s = try Scratch()
        try s.file("kokoro-82m/config.json", "{}")
        try s.file("kokoro-82m/model.safetensors")
        let media = await TaskSummarizer(config: config(path: s.url.appendingPathComponent("kokoro-82m").path)).resolve()
        #expect(media.route == nil)
        #expect(media.status.label.contains("speech, image or video"))
        let missing = await TaskSummarizer(config: config(path: "/nonexistent/qwen")).resolve()
        #expect(missing.status.label == "Nothing at /nonexistent/qwen.")
    }

    @Test func disabledResolvesToDisabled() async {
        var config = config(path: "/nonexistent")
        config.enabled = false
        #expect(await TaskSummarizer(config: config).resolve() == .unavailable(.disabled))
    }

    @Test func reportSaysHowItRuns() async throws {
        let s = try Scratch()
        try s.file("qwen/config.json", "{}")
        try s.file("qwen/model.safetensors")
        let python = try s.tool("python", "exit 0")
        var config = config(path: s.url.appendingPathComponent("qwen").path, python: python)
        config.enabled = false
        let report = await TaskModelReport.make(config)
        let fields = Dictionary(uniqueKeysWithValues: report.fields.map { ($0.key, $0.value) })
        #expect(fields["summaries"] == "off")
        #expect(fields["format"] == "MLX text model")
        #expect(fields["runs"] == "directly with mlx-lm")
        #expect(fields["runtime"] == python)
    }
}

@Suite struct LocalModelRunnerTests {
    @Test func mlxRouteReadsTheMarkedLineAndIgnoresNoise() async throws {
        let s = try Scratch()
        // Checks the request arrives on stdin, then prints warnings around the result like real runtimes do.
        let python = try s.tool("python", #"""
        grep -q '"prompt"' || exit 3
        echo "W1023 torch warning"
        echo 'AMBIENT_RESULT {"text":"{\"title\":\"Ship it\",\"status\":\"done\"}"}'
        echo "trailing noise"
        """#)
        let text = try await LocalModelRunner.generate(.mlx(path: "/m", vision: false, python: python),
                                                       prompt: "facts", maxTokens: 10, temperature: 0, timeout: 10)
        #expect(TaskSummarizer.parse(text) == TaskSemantics(title: "Ship it", status: .done))
    }

    @Test func failureCarriesTheRuntimeLog() async throws {
        let s = try Scratch()
        let python = try s.tool("python", "echo 'ModuleNotFoundError: mlx_lm' >&2; exit 1")
        await #expect(throws: LocalModelRunner.RunError.failed("ModuleNotFoundError: mlx_lm")) {
            try await LocalModelRunner.generate(.mlx(path: "/m", vision: false, python: python),
                                                prompt: "x", maxTokens: 1, temperature: 0, timeout: 10)
        }
    }

    @Test func slowRuntimeTimesOut() async throws {
        let s = try Scratch()
        let python = try s.tool("python", "exec sleep 20")
        await #expect(throws: LocalModelRunner.RunError.timedOut) {
            try await LocalModelRunner.generate(.mlx(path: "/m", vision: false, python: python),
                                                prompt: "x", maxTokens: 1, temperature: 0, timeout: 0.5)
        }
    }

    /// The shared queue runs one model at a time, so a run that never returns would stall every later one.
    @Test func childHoldingThePipesAfterExitDoesNotHangTheRun() async throws {
        let s = try Scratch()
        // The background sleep inherits both pipes and outlives the runtime.
        let python = try s.tool("python", "sleep 12 &\nexit 0")
        await #expect(throws: LocalModelRunner.RunError.timedOut) {
            try await LocalModelRunner.generate(.mlx(path: "/m", vision: false, python: python),
                                                prompt: "x", maxTokens: 1, temperature: 0, timeout: 30)
        }
    }

    /// mlx-vlm forces `trust_remote_code` on for some tokenizers, so the folder check alone can't stop their code.
    @Test func modelFolderCodeNeverLoads() async throws {
        let s = try Scratch()
        try s.file("site/transformers/__init__.py")
        try s.file("site/transformers/dynamic_module_utils.py", """
        def get_class_in_module(*args, **kwargs): pass
        def get_class_from_dynamic_module(*args, **kwargs): pass
        """)
        // Asks for the folder's code and swallows errors, as mlx-vlm's patched AutoProcessor does.
        try s.file("site/mlx_vlm/__init__.py", """
        import transformers.dynamic_module_utils as dynamic
        def generate(*args, **kwargs): pass
        def load(path):
            try:
                dynamic.get_class_from_dynamic_module()
            except Exception:
                pass
            raise RuntimeError("The folder's code loaded.")
        """)
        try s.file("site/mlx_vlm/prompt_utils.py", "apply_chat_template = None")
        try s.file("site/mlx_vlm/utils.py", "load_config = None")
        let python = try s.tool("python", "PYTHONPATH='\(s.url.path)/site' exec python3 \"$@\"")
        await #expect(throws: LocalModelRunner.RunError.failed("This model runs its own Python code, which Ambient won't load.")) {
            try await LocalModelRunner.generate(.mlx(path: "/m", vision: true, python: python),
                                                prompt: "x", maxTokens: 1, temperature: 0, timeout: 30)
        }
    }

    /// The board's status line shows `localizedDescription`.
    @Test func errorsKeepTheirMessage() {
        #expect(LocalModelRunner.RunError.failed("Model type x not supported").localizedDescription == "Model type x not supported")
        #expect(LocalModelRunner.RunError.timedOut.localizedDescription == "Local model timed out.")
        #expect(LocalAgentMCP.MCPError.transport("Local LLM timed out.").localizedDescription == "Local LLM timed out.")
    }

    @Test func llamaCppGetsThePromptFileAndPlainCompletion() async throws {
        let s = try Scratch()
        // Echoes the prompt file back, as a completion would continue it.
        let llama = try s.tool("llama-completion", #"""
        while [ $# -gt 0 ]; do [ "$1" = "-f" ] && cat "$2"; shift; done
        """#)
        let text = try await LocalModelRunner.generate(.llamaCpp(path: "/m.gguf", binary: llama),
                                                       prompt: "hello gguf", maxTokens: 5, temperature: 0.2, timeout: 10)
        #expect(text == "hello gguf")
        #expect(!LocalModelRunner.llamaArguments(binary: llama, model: "/m", promptFile: "/p", maxTokens: 1, temperature: 0)
            .contains("-no-cnv"))
        #expect(LocalModelRunner.llamaArguments(binary: "/opt/homebrew/bin/llama-cli", model: "/m", promptFile: "/p",
                                                maxTokens: 1, temperature: 0).contains("-no-cnv"))
    }
}

@Suite struct TaskModelWireTests {
    @Test func setAndReplyRoundTrip() throws {
        let change = WireMessage.setTaskModel(TaskModelChange(modelPath: "/models/qwen", enabled: true))
        #expect(try Wire.decode(Wire.encode(change)) == change)
        let reply = WireMessage.taskModel(TaskLLMConfig(enabled: true, modelPath: "/models/qwen", pythonPath: "/py"))
        #expect(try Wire.decode(Wire.encode(reply)) == reply)
        #expect(try Wire.decode(Wire.encode(.taskModelTimedOut)) == .taskModelTimedOut)
    }
}
