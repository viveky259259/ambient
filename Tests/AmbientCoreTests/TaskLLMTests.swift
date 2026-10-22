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
