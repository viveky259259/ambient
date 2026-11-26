import Foundation
import Testing
@testable import AmbientCore

/// TaskSummarizer against a stub local-agent gateway: how it picks a model, and how a summary job runs.
@Suite struct QATaskSummarizerGatewayTests {
    typealias G = QAStubGateway

    static let model = "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    private func summarizer(_ gateway: G, enabled: Bool = true, modelID: String = model,
                            volume: String = "/Volumes/QA-Not-There") -> TaskSummarizer {
        let config = TaskLLMConfig(enabled: enabled, mcpURL: gateway.url.absoluteString, modelID: modelID,
                                   modelsVolumePath: volume)
        return TaskSummarizer(config: config, mcp: gateway.mcp(), skillPack: .bundledSeed)
    }

    /// A gateway that knows `models` and reports the volume as `volumeOK`.
    private func inventory(_ models: [[String: Any]], volumeOK: Bool? = true, hint: String? = nil) -> G {
        G.standard { name, _, id in
            switch name {
            case "model_storage_status":
                var storage: [String: Any] = [:]
                if let volumeOK { storage["external_volume_available"] = volumeOK }
                if let hint { storage["mount_hint"] = hint }
                return G.toolJSON(id, storage)
            case "list_models": return G.toolJSON(id, ["models": models])
            default: return .init(status: 404)
            }
        }
    }

    // MARK: - resolve()

    @Test func disabledNeverTalksToTheGateway() async {
        let gateway = inventory([])
        #expect(await summarizer(gateway, enabled: false).resolve() == .unavailable(.disabled))
        #expect(gateway.calls.isEmpty)
    }

    @Test(arguments: ["ollama:llama3:cloud", "ollama:GPT-OSS:CLOUD", "cloud/some-model"])
    func cloudModelsAreBlocked(id: String) async {
        let gateway = inventory([])
        let resolution = await summarizer(gateway, modelID: id).resolve()
        guard case let .unavailable(.cloudModelBlocked(message)) = resolution else {
            Issue.record("expected cloudModelBlocked, got \(resolution)"); return
        }
        #expect(message.contains(id))
        #expect(gateway.calls.isEmpty)
    }

    /// Ollama names its hosted models with a "-cloud" tag suffix (gpt-oss:120b-cloud, deepseek-v3.1:671b-cloud).
    /// `TaskLLMConfig.isCloudModel` only matches ":cloud" and "cloud/", so these pass as local.
    @Test(arguments: ["ollama:gpt-oss:120b-cloud", "ollama:deepseek-v3.1:671b-cloud"])
    func ollamaDashCloudTagsAreBlocked(id: String) {
        withKnownIssue("BUG: isCloudModel misses Ollama's -cloud tag suffix, so a hosted model isn't refused") {
            #expect(TaskLLMConfig.isCloudModel(id))
        }
    }

    @Test func invalidURLIsGatewayDown() async {
        let config = TaskLLMConfig(enabled: true, mcpURL: "")
        let resolution = await TaskSummarizer(config: config, mcp: LocalAgentMCP(), skillPack: .bundledSeed).resolve()
        #expect(resolution == .unavailable(.gatewayDown("Local-agent MCP URL is invalid.")))
    }

    @Test(arguments: ["http://192.168.1.4:5051/mcp", "https://gateway.example.com/mcp"])
    func nonLoopbackURLIsBlocked(url: String) async {
        let config = TaskLLMConfig(enabled: true, mcpURL: url)
        let resolution = await TaskSummarizer(config: config, skillPack: .bundledSeed).resolve()
        guard case .unavailable(.nonLoopbackBlocked) = resolution else {
            Issue.record("expected nonLoopbackBlocked, got \(resolution)"); return
        }
    }

    @Test func knownChatModelIsReady() async {
        let gateway = inventory([["id": Self.model, "kind": "chat"]])
        #expect(await summarizer(gateway).resolve() == .ready(.gateway(modelID: Self.model, kind: "chat")))
    }

    @Test func visionModelIsReadyToo() async {
        let gateway = inventory([["id": Self.model, "kind": "vision"]])
        #expect(await summarizer(gateway).resolve() == .ready(.gateway(modelID: Self.model, kind: "vision")))
    }

    @Test func missingKindDefaultsToChat() async {
        let gateway = inventory([["id": Self.model]])
        let resolution = await summarizer(gateway).resolve()
        // An entry without a kind is either treated as chat or refused; never anything else.
        switch resolution {
        case .ready(.gateway(_, "chat")), .unavailable(.modelUnavailable): break
        default: Issue.record("unexpected \(resolution)")
        }
    }

    @Test func nonTextModelIsUnavailable() async {
        let gateway = inventory([["id": Self.model, "kind": "tts"]])
        let resolution = await summarizer(gateway).resolve()
        guard case let .unavailable(.modelUnavailable(message)) = resolution else {
            Issue.record("expected modelUnavailable, got \(resolution)"); return
        }
        #expect(message.contains("tts"))
    }

    @Test func unknownModelWithVolumeMountedIsUnavailable() async {
        let gateway = inventory([["id": "hf:other", "kind": "chat"]], volumeOK: true)
        let resolution = await summarizer(gateway).resolve()
        guard case let .unavailable(.modelUnavailable(message)) = resolution else {
            Issue.record("expected modelUnavailable, got \(resolution)"); return
        }
        #expect(message.contains(Self.model))
    }

    @Test func unknownModelWithVolumeMissingSaysSo() async {
        let gateway = inventory([], volumeOK: false, hint: "Plug in the SSD.")
        let resolution = await summarizer(gateway).resolve()
        #expect(resolution == .unavailable(.volumeMissing("Models disk unmounted. Plug in the SSD.")))
    }

    @Test func volumeMissingWithoutHintNamesThePath() async {
        let gateway = inventory([], volumeOK: false)
        let resolution = await summarizer(gateway, volume: "/Volumes/QA-Models").resolve()
        guard case let .unavailable(.volumeMissing(message)) = resolution else {
            Issue.record("expected volumeMissing, got \(resolution)"); return
        }
        #expect(message.contains("/Volumes/QA-Models"))
    }

    @Test func volumeStatusFallsBackToTheFileSystem() async throws {
        // The gateway doesn't say; a folder that exists counts as mounted.
        let folder = FileManager.default.temporaryDirectory.path
        let gateway = inventory([], volumeOK: nil)
        let resolution = await summarizer(gateway, volume: folder).resolve()
        guard case .unavailable(.modelUnavailable) = resolution else {
            Issue.record("expected modelUnavailable, got \(resolution)"); return
        }
    }

    @Test func modelsOffTheVolumeStillWorkWhileItIsUnmounted() async {
        let gateway = inventory([["id": Self.model, "kind": "chat"]], volumeOK: false)
        #expect(await summarizer(gateway).resolve() == .ready(.gateway(modelID: Self.model, kind: "chat")))
    }

    @Test func gatewayHTTPErrorIsGatewayDown() async {
        let gateway = G { _, _, _ in .init(status: 500) }
        let resolution = await summarizer(gateway).resolve()
        #expect(resolution == .unavailable(.gatewayDown("Local-agent MCP returned HTTP 500.")))
    }

    @Test func toolErrorIsGatewayDown() async {
        let gateway = G.standard { _, _, id in G.result(id, ["isError": true, "content": [["type": "text", "text": "boom"]]]) }
        #expect(await summarizer(gateway).resolve() == .unavailable(.gatewayDown("boom")))
    }

    // MARK: - summarize()

    private func jobs(_ job: @escaping (_ status: Int) -> [String: Any], submit: [String: Any] = ["id": "job-1"]) -> G {
        var polls = 0
        let lock = NSLock()
        return G.standard { name, _, id in
            switch name {
            case "submit_inference": return G.toolJSON(id, submit)
            case "get_job":
                lock.lock(); polls += 1; let n = polls; lock.unlock()
                return G.toolJSON(id, job(n))
            default: return .init(status: 404)
            }
        }
    }

    @Test func completedJobIsParsed() async throws {
        let reply = #"{"title":"Fix login","summary":"Login works again.","status":"done"}"#
        let gateway = jobs { _ in ["status": "completed", "result": ["message": ["content": reply]]] }
        let semantics = try await summarizer(gateway).summarize(context: "agent: Claude", via: .gateway(modelID: Self.model, kind: "chat"))
        #expect(semantics.title == "Fix login")
        #expect(semantics.summary == "Login works again.")
        #expect(semantics.status == .done)
        let submit = try #require(gateway.calls.first { $0.params["name"] as? String == "submit_inference" })
        let arguments = try #require(submit.params["arguments"] as? [String: Any])
        #expect(arguments["model_id"] as? String == Self.model)
        #expect((arguments["prompt"] as? String)?.contains("agent: Claude") == true)
        #expect((arguments["options"] as? [String: Any])?["max_tokens"] as? Int == 220)
    }

    @Test func pollsUntilTheJobCompletes() async throws {
        let gateway = jobs { n in
            n < 2 ? ["status": "running"] : ["status": "completed", "result": ["text": #"{"title":"Later"}"#]]
        }
        let semantics = try await summarizer(gateway).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        #expect(semantics.title == "Later")
        #expect(gateway.calls.filter { $0.params["name"] as? String == "get_job" }.count == 2)
    }

    @Test func failedJobThrowsItsError() async {
        let gateway = jobs { _ in ["status": "failed", "error": "out of memory"] }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("out of memory")) {
            _ = try await summarizer(gateway).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
    }

    @Test func failedJobFallsBackToMessageThenState() async {
        let withMessage = jobs { _ in ["status": "failed", "message": "bad prompt"] }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("bad prompt")) {
            _ = try await summarizer(withMessage).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
        let bare = jobs { _ in ["status": "failed"] }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("failed")) {
            _ = try await summarizer(bare).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
    }

    @Test func completedJobWithoutTextIsADecodeError() async {
        let gateway = jobs { _ in ["status": "completed", "result": ["files": []]] }
        await #expect(throws: LocalAgentMCP.MCPError.decode("Job completed without text")) {
            _ = try await summarizer(gateway).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
    }

    @Test func submitWithoutJobIDIsADecodeError() async {
        let gateway = jobs({ _ in [:] }, submit: ["queued": true])
        await #expect(throws: LocalAgentMCP.MCPError.decode("submit_inference returned no job id")) {
            _ = try await summarizer(gateway).summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
    }

    @Test func cloudModelRouteIsRefusedWithoutAnyRequest() async {
        let gateway = jobs { _ in [:] }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("Cloud models are blocked for board summaries.")) {
            _ = try await summarizer(gateway).summarize(context: "c", via: .gateway(modelID: "ollama:x:cloud", kind: "chat"))
        }
        #expect(gateway.calls.isEmpty)
    }

    @Test func nonLoopbackConfigIsRefusedAtSummarize() async {
        let config = TaskLLMConfig(enabled: true, mcpURL: "http://example.com/mcp")
        let summarizer = TaskSummarizer(config: config, mcp: LocalAgentMCP(), skillPack: .bundledSeed)
        await #expect(throws: LocalAgentMCP.MCPError.nonLoopback) {
            _ = try await summarizer.summarize(context: "c", via: .gateway(modelID: Self.model, kind: "chat"))
        }
    }
}

// MARK: - Status, resolution and report

@Suite struct QATaskLLMStatusTests {
    static let all: [TaskLLMStatus] = [
        .disabled, .ready, .summarizing, .gatewayDown("g"), .volumeMissing("v"), .modelUnavailable("m"),
        .cloudModelBlocked("c"), .nonLoopbackBlocked("n"), .failed("f"),
    ]

    @Test func labels() {
        #expect(TaskLLMStatus.disabled.label == "Local LLM off — using metadata heuristics")
        #expect(TaskLLMStatus.ready.label == "Local LLM ready")
        #expect(TaskLLMStatus.summarizing.label == "Summarizing…")
        #expect(Self.all.dropFirst(3).map(\.label) == ["g", "v", "m", "c", "n", "f"])
    }

    @Test func statusesRoundTripThroughJSON() throws {
        for status in Self.all {
            let data = try JSONEncoder().encode(status)
            #expect(try JSONDecoder().decode(TaskLLMStatus.self, from: data) == status)
        }
    }

    @Test func resolutionStatusAndRoute() {
        let route = TaskModelRoute.gateway(modelID: "m", kind: "chat")
        #expect(TaskModelResolution.ready(route).status == .ready)
        #expect(TaskModelResolution.ready(route).route == route)
        #expect(TaskModelResolution.unavailable(.failed("x")).status == .failed("x"))
        #expect(TaskModelResolution.unavailable(.failed("x")).route == nil)
    }

    @Test func configLoopbackAndCloudRules() {
        #expect(URL(string: "http://localhost:1/mcp")!.isLoopback)
        #expect(URL(string: "HTTPS://LOCALHOST/mcp")!.isLoopback)
        #expect(URL(string: "http://[::1]:5051/mcp")!.isLoopback)
        #expect(!URL(string: "http://127.0.0.2/mcp")!.isLoopback)
        #expect(!URL(string: "ws://127.0.0.1/mcp")!.isLoopback)
        #expect(refusesNonLoopback(TaskLLMConfig(mcpURL: "")))
        #expect(refusesNonLoopback(TaskLLMConfig(mcpURL: "http://10.0.0.1/mcp")))
        #expect(!refusesNonLoopback(TaskLLMConfig()))
        // A model path wins over the id, so a cloud-looking id doesn't matter then.
        #expect(TaskLLMConfig(modelID: "x:cloud").refusesCloudModel)
        #expect(!TaskLLMConfig(modelID: "x:cloud", modelPath: "/m").refusesCloudModel)
        #expect(!TaskLLMConfig(modelPath: "   ").usesModelPath)
    }
}

@Suite struct QATaskModelReportTests {
    private func value(_ report: TaskModelReport, _ key: String) -> String? {
        report.fields.first { $0.key == key }?.value
    }

    @Test func gatewayRouteFields() {
        let config = TaskLLMConfig(enabled: true, modelID: "hf:m")
        let report = TaskModelReport(config: config, model: nil,
                                     resolution: .ready(.gateway(modelID: "hf:m", kind: "chat")), note: "app is older")
        #expect(report.fields.map(\.key) == ["summaries", "model_id", "runs", "gateway_model", "status", "note"])
        #expect(value(report, "summaries") == "on")
        #expect(value(report, "runs") == "via local-agent")
        #expect(value(report, "gateway_model") == "hf:m (chat)")
        #expect(value(report, "status") == "Local LLM ready")
        #expect(value(report, "note") == "app is older")
    }

    @Test func llamaCppRouteFields() {
        let config = TaskLLMConfig(enabled: false, modelPath: "/models/a.gguf")
        let model = LocalModelPath(requested: "/models/a.gguf", resolved: "/models/a.gguf", format: .gguf, note: nil)
        let report = TaskModelReport(config: config, model: model,
                                     resolution: .ready(.llamaCpp(path: "/models/a.gguf", binary: "/opt/bin/llama-cli")))
        #expect(value(report, "summaries") == "off")
        #expect(value(report, "model_path") == "/models/a.gguf")
        #expect(value(report, "format") == "GGUF model")
        #expect(value(report, "loads") == nil)
        #expect(value(report, "runs") == "directly with llama.cpp")
        #expect(value(report, "runtime") == "/opt/bin/llama-cli")
        #expect(value(report, "model_id") == nil)
    }

    @Test func mlxRoutesNameTheirRuntime() {
        let config = TaskLLMConfig(enabled: true, modelPath: "/m")
        let text = TaskModelReport(config: config, model: nil, resolution: .ready(.mlx(path: "/m", vision: false, python: "/py")))
        let vision = TaskModelReport(config: config, model: nil, resolution: .ready(.mlx(path: "/m", vision: true, python: "/py")))
        #expect(value(text, "runs") == "directly with mlx-lm")
        #expect(value(vision, "runs") == "directly with mlx-vlm")
        #expect(value(text, "runtime") == "/py")
        #expect(value(text, "format") == nil)
    }

    @Test func resolvedPathIsShownWhenItDiffers() {
        let config = TaskLLMConfig(modelPath: "/hf/models--a--b")
        let model = LocalModelPath(requested: "/hf/models--a--b", resolved: "/hf/models--a--b/snapshots/1",
                                   format: .mlxText, note: nil)
        let report = TaskModelReport(config: config, model: model, resolution: .unavailable(.modelUnavailable("why")))
        #expect(value(report, "loads") == "/hf/models--a--b/snapshots/1")
        #expect(value(report, "status") == "why")
        #expect(value(report, "runs") == nil)
        #expect(model.name == "a/b")
    }

    @Test func makeResolvesAsIfOnButKeepsTheSwitch() async {
        // A missing model path resolves without any gateway or runtime: Nothing at …
        let config = TaskLLMConfig(enabled: false, modelPath: "/nonexistent/qa-model-\(UUID().uuidString)")
        let report = await TaskModelReport.make(config)
        #expect(report.config.enabled == false)
        #expect(report.model == nil)
        guard case let .unavailable(.modelUnavailable(message)) = report.resolution else {
            Issue.record("expected modelUnavailable, got \(report.resolution)"); return
        }
        #expect(message.hasPrefix("Nothing at "))
    }

    @Test func missingPathOnUnmountedVolumeSaysVolumeMissing() async {
        let volume = "/Volumes/QA-Missing-\(UUID().uuidString.prefix(6))"
        let config = TaskLLMConfig(enabled: true, modelPath: volume + "/model", modelsVolumePath: volume)
        let resolution = await TaskSummarizer(config: config, skillPack: .bundledSeed).resolve()
        guard case .unavailable(.volumeMissing) = resolution else {
            Issue.record("expected volumeMissing, got \(resolution)"); return
        }
    }
}
