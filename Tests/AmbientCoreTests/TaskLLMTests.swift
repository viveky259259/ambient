import Foundation
import Testing
@testable import AmbientCore

@Suite struct TaskLLMParseTests {
    @Test func parsesFencedJSON() {
        let raw = """
        ```json
        {"title":"Ship board","summary":"Wire local LLM summaries on device.","status":"inProgress"}
        ```
        """
        let s = TaskSummarizer.parse(raw)
        #expect(s.title == "Ship board")
        #expect(s.summary == "Wire local LLM summaries on device.")
        #expect(s.status == TaskStatus.inProgress)
    }

    @Test func ignoresDuplicateStatusKeysByTakingLastDecode() {
        // Tiny models sometimes emit repeated keys; JSONSerialization keeps one.
        let raw = #"{"title":"Approve patch","summary":"Needs approval","status":"blocked"}"#
        let s = TaskSummarizer.parse(raw)
        #expect(s.status == TaskStatus.blocked)
        #expect(s.title == "Approve patch")
    }

    @Test func fallsBackToPlainTextSummary() {
        let s = TaskSummarizer.parse("Just a paragraph with no JSON.")
        #expect(s.title == nil)
        #expect(s.summary == "Just a paragraph with no JSON.")
    }
}

@Suite struct TaskLLMConfigTests {
    @Test func blocksCloudTaggedModels() {
        var config = TaskLLMConfig(enabled: true, modelID: "ollama:minimax-m3.1-flash:cloud")
        #expect(config.refusesCloudModel)
        config.modelID = "hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        #expect(!config.refusesCloudModel)
    }

    @Test func acceptsOnlyLoopbackMCPHosts() {
        #expect(TaskLLMConfig.isLoopback(URL(string: "http://127.0.0.1:5051/mcp")!))
        #expect(TaskLLMConfig.isLoopback(URL(string: "http://localhost:5051/mcp")!))
        #expect(TaskLLMConfig.isLoopback(URL(string: "http://[::1]:5051/mcp")!))
        #expect(!TaskLLMConfig.isLoopback(URL(string: "http://example.com:5051/mcp")!))
        #expect(!TaskLLMConfig.isLoopback(URL(string: "https://api.openai.com/v1")!))
        var config = TaskLLMConfig(enabled: true, mcpURL: "http://10.0.0.5:5051/mcp")
        #expect(config.refusesNonLoopback)
        config.mcpURL = "http://127.0.0.1:5051/mcp"
        #expect(!config.refusesNonLoopback)
    }
}

@Suite struct SessionContextBuilderTests {
    @Test func includesAgentAndMood() {
        var s = Session(agent: .codex, sessionId: "abc", at: Date())
        s.cwd = "/Users/me/src/ambient"
        s.activity = .waiting(reason: "permission", message: "Approve?")
        let ctx = SessionContextBuilder.make(session: s)
        #expect(ctx.contains("agent: Codex"))
        #expect(ctx.contains("project: ambient"))
        #expect(ctx.contains("Needs permission"))
    }
}

@Suite struct TaskStoreSemanticsTests {
    @Test func localLLMUpdatesSummaryAndTitle() {
        let store = TaskStore()
        var session = Session(agent: .codex, sessionId: "s1", at: Date())
        session.cwd = "/p/app"
        session.activity = .thinking
        let task = store.observe(SessionChange(session: session, previous: nil, event: .promptSubmitted, removed: false))
        #expect(task != nil)
        let id = task!.id
        let updated = store.applySemantics(
            TaskSemantics(title: "Implement board", summary: "Add local LLM summaries.", status: .inProgress),
            toTaskID: id,
            session: session
        )
        #expect(updated?.title == "Implement board")
        #expect(updated?.summary == "Add local LLM summaries.")
        #expect(updated?.summarySource == .localLLM)
        #expect(updated?.status == TaskStatus.inProgress)
    }

    @Test func waitingStillForcesBlocked() {
        let store = TaskStore()
        var session = Session(agent: .codex, sessionId: "s2", at: Date())
        session.cwd = "/p/app"
        session.activity = .waiting(reason: "permission", message: "ok?")
        let task = store.observe(SessionChange(session: session, previous: .thinking,
                                               event: .needsInput(reason: "permission", message: "ok?"), removed: false))!
        let updated = store.applySemantics(
            TaskSemantics(title: "X", summary: "Y", status: .done),
            toTaskID: task.id,
            session: session
        )
        #expect(updated?.status == TaskStatus.blocked)
    }

    @Test func staleWaitingSessionDoesNotReblockAfterLiveUnblock() {
        let store = TaskStore()
        var waiting = Session(agent: .codex, sessionId: "s3", at: Date())
        waiting.cwd = "/p/app"
        waiting.activity = .waiting(reason: "permission", message: "ok?")
        let task = store.observe(SessionChange(session: waiting, previous: .thinking,
                                               event: .needsInput(reason: "permission", message: "ok?"), removed: false))!
        #expect(task.status == .blocked)

        var working = waiting
        working.activity = .thinking
        let live = store.observe(SessionChange(session: working, previous: .waiting(reason: "permission", message: "ok?"),
                                               event: .promptSubmitted, removed: false))!
        #expect(live.status == .inProgress)

        // LLM returns later with a *captured* waiting copy — AppModel must pass the live session instead.
        let updated = store.applySemantics(
            TaskSemantics(title: "Keep going", summary: "Still working.", status: .inProgress),
            toTaskID: task.id,
            session: working
        )
        #expect(updated?.status == TaskStatus.inProgress)
        #expect(updated?.title == "Keep going")
    }

    @Test func llmCannotClearBlockedWithoutWaitingSession() {
        let store = TaskStore()
        var waiting = Session(agent: .codex, sessionId: "s4", at: Date())
        waiting.cwd = "/p/app"
        waiting.activity = .waiting(reason: "permission", message: "ok?")
        let task = store.observe(SessionChange(session: waiting, previous: .thinking,
                                               event: .needsInput(reason: "permission", message: "ok?"), removed: false))!
        #expect(task.status == .blocked)
        let updated = store.applySemantics(
            TaskSemantics(title: "Done?", summary: "Maybe finished.", status: .done),
            toTaskID: task.id,
            session: nil
        )
        #expect(updated?.status == TaskStatus.blocked)
        #expect(updated?.summary == "Maybe finished.")
    }
}

@Suite struct LocalAgentSSETests {
    @Test func parsesEventStreamDataLine() {
        let body = Data("""
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}

        """.utf8)
        let obj = LocalAgentMCP.parseSSE(body)
        #expect((obj?["result"] as? [String: Any])?["ok"] as? Bool == true)
    }
}

@Suite struct TaskSkillPackTests {
    @Test func bundledSeedInjectsExamplesIntoPrompt() {
        let prompt = TaskSummarizer.prompt(for: "agent: Codex\nmood: Working", skill: .bundledSeed)
        #expect(prompt.contains("Style rules:"))
        #expect(prompt.contains("Example 1 JSON:"))
        #expect(prompt.contains("Session facts:"))
        #expect(prompt.contains("agent: Codex"))
    }

    @Test func saveAndLoadRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-skill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let paths = AmbientPaths(userHome: tmp, home: tmp)
        let pack = TaskSkillPack(
            source: "test",
            hints: ["Keep titles short"],
            examples: [
                .init(facts: "agent: Claude\nmood: Done", title: "Finish docs", summary: "Docs are done.", status: "done"),
            ]
        )
        try TaskSkillStore.save(pack, paths: paths)
        let loaded = TaskSkillStore.load(paths: paths)
        #expect(loaded.source == "test")
        #expect(loaded.examples.count == 1)
        #expect(loaded.examples[0].title == "Finish docs")
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.taskSkill.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        #expect(perms?.intValue == 0o600)
    }

    @Test func bootstrapParserAcceptsLabeledJSON() throws {
        let raw = """
        {
          "hints": ["Title ≤50 chars"],
          "examples": [
            {"facts":"agent: Codex\\nmood: Needs permission","title":"Approve shell","summary":"Waiting on you.","status":"blocked"},
            {"facts":"agent: Claude\\nmood: Working","title":"Wire MCP client","summary":"Building the local client.","status":"inProgress"},
            {"facts":"agent: Cursor\\nmood: Done","title":"Ship board UI","summary":"Board pane is finished.","status":"done"},
            {"facts":"agent: Gemini\\nmood: Idle","title":"Backlog polish","summary":"Queued for later.","status":"backlog"}
          ]
        }
        """
        let payload = try TaskSkillBootstrap.parsePayload(raw)
        #expect(payload.examples.count == 4)
        #expect(payload.hints.first == "Title ≤50 chars")
    }
}
