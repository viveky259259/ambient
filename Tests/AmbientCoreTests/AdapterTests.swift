import Foundation
import Testing
@testable import AmbientCore

private func payload(_ json: String) -> HookPayload {
    HookPayload(json: Data(json.utf8))!
}

private func claude(_ json: String, hint: String? = nil) -> EventKind? {
    AdapterRegistry.event(agent: .claude, payload: payload(json), eventHint: hint)?.kind
}

private func gemini(_ json: String) -> EventKind? {
    AdapterRegistry.event(agent: .gemini, payload: payload(json), eventHint: nil)?.kind
}

/// Antigravity's payloads don't name the event; the hook command passes it.
private func antigravity(_ event: String, _ json: String) -> EventKind? {
    AdapterRegistry.event(agent: .antigravity, payload: payload(json), eventHint: event)?.kind
}

@Suite struct ClaudeAdapterTests {
    @Test func sessionStart() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"SessionStart","source":"startup"}"#) == .sessionStarted)
    }

    @Test func sessionStartAfterCompactFinishesCompaction() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"SessionStart","source":"compact"}"#) == .compactFinished)
    }

    @Test func promptSubmitNeverCarriesThePrompt() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"UserPromptSubmit","prompt":"secret plans"}"#) == .promptSubmitted)
    }

    @Test func bashToolDetailIsTheCommand() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm   test -- --watch=false"}}"#)
        #expect(kind == .toolStarted(name: "Bash", detail: "npm test -- --watch=false"))
    }

    @Test func fileToolDetailIsTheBasename() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/Users/me/src/app/Sources/main.swift","old_string":"x"}}"#)
        #expect(kind == .toolStarted(name: "Edit", detail: "main.swift"))
    }

    @Test func webFetchDetailIsTheHost() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"WebFetch","tool_input":{"url":"https://docs.swift.org/x/y","prompt":"p"}}"#)
        #expect(kind == .toolStarted(name: "WebFetch", detail: "docs.swift.org"))
    }

    @Test func longCommandsAreTruncatedTo80() {
        let long = String(repeating: "a", count: 200)
        let kind = claude(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(long)"}}"#)
        guard case .toolStarted(_, let detail?) = kind else { Issue.record("no detail"); return }
        #expect(detail.count == 80)
    }

    @Test func mcpToolHasNoDetail() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"mcp__github__create_pr","tool_input":{"title":"t"}}"#)
        #expect(kind == .toolStarted(name: "mcp__github__create_pr", detail: nil))
    }

    @Test func postToolUseAndFailure() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{},"tool_response":{"stdout":"lots"}}"#)
                == .toolFinished(name: "Bash", failed: false))
        #expect(claude(#"{"session_id":"a","hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"exit 1"}"#)
                == .toolFinished(name: "Bash", failed: true))
    }

    @Test func permissionRequestNeedsInput() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#)
        #expect(kind == .needsInput(reason: "permission", message: "Bash: rm -rf build"))
    }

    @Test func permissionNotificationNeedsInput() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#)
        #expect(kind == .needsInput(reason: "permission", message: "Claude needs your permission to use Bash"))
    }

    @Test func elicitationNeedsInput() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"Pick one"}"#)
        #expect(kind == .needsInput(reason: "question", message: "Pick one"))
    }

    @Test func idlePromptChangesNothing() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#) == nil)
    }

    @Test func otherNotificationsAreNotices() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"Notification","notification_type":"auth_success","message":"Logged in"}"#)
                == .notice(message: "Logged in"))
    }

    @Test func stopCompletesTurnWithSummary() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"Stop","last_assistant_message":"All 42 tests pass.\n\nDetails below"}"#)
        #expect(kind == .turnCompleted(summary: "All 42 tests pass. Details below"))
        #expect(claude(#"{"session_id":"a","hook_event_name":"Stop"}"#) == .turnCompleted(summary: nil))
    }

    @Test func stopFailureFailsTurn() {
        let kind = claude(#"{"session_id":"a","hook_event_name":"StopFailure","error_type":"rate_limit","error_message":"Rate limited"}"#)
        #expect(kind == .turnFailed(message: "Rate limited"))
    }

    @Test func compactionAndSubagents() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"PreCompact","trigger":"auto"}"#) == .compactStarted)
        #expect(claude(#"{"session_id":"a","hook_event_name":"PostCompact"}"#) == .compactFinished)
        #expect(claude(#"{"session_id":"a","hook_event_name":"SubagentStart","agent_type":"Explore"}"#) == .subagentStarted)
        #expect(claude(#"{"session_id":"a","hook_event_name":"SubagentStop"}"#) == .subagentFinished)
    }

    @Test func sessionEnd() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"SessionEnd","reason":"prompt_input_exit"}"#) == .sessionEnded)
    }

    @Test func eventNameFallsBackToHint() {
        #expect(claude(#"{"session_id":"a"}"#, hint: "Stop") == .turnCompleted(summary: nil))
    }

    @Test func unknownEventIsIgnored() {
        #expect(claude(#"{"session_id":"a","hook_event_name":"FileChanged"}"#) == nil)
    }

    @Test func missingSessionIdIsIgnored() {
        #expect(AdapterRegistry.event(agent: .claude, payload: payload(#"{"hook_event_name":"Stop"}"#), eventHint: nil) == nil)
    }

    @Test func eventCarriesSessionCwdAndHost() {
        let host = HostInfo(bundleId: "com.googlecode.iterm2", termProgram: "iTerm.app", pids: [3])
        let now = Date(timeIntervalSince1970: 100)
        let e = AdapterRegistry.event(agent: .claude,
                                      payload: payload(#"{"session_id":"abc","cwd":"/src/web","hook_event_name":"Stop"}"#),
                                      eventHint: nil, now: now, host: host)
        #expect(e == AgentEvent(agent: .claude, sessionId: "abc", cwd: "/src/web", kind: .turnCompleted(summary: nil), timestamp: now, host: host))
    }
}

@Suite struct CodexAdapterTests {
    @Test func codexUsesClaudeCompatibleNames() {
        let p = payload(#"{"session_id":"c","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cargo test"}}"#)
        #expect(AdapterRegistry.event(agent: .codex, payload: p, eventHint: nil)?.kind == .toolStarted(name: "Bash", detail: "cargo test"))
    }

    @Test func applyPatchDetailIsFirstFile() {
        let patch = "*** Begin Patch\n*** Update File: src/lib/parser.rs\n@@\n-a\n+b\n*** End Patch"
        let json = #"{"session_id":"c","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"input":"\#(patch.replacingOccurrences(of: "\n", with: "\\n"))"}}"#
        #expect(AdapterRegistry.event(agent: .codex, payload: payload(json), eventHint: nil)?.kind
                == .toolStarted(name: "apply_patch", detail: "parser.rs"))
    }
}

@Suite struct GeminiAdapterTests {
    @Test func agentLifecycle() {
        #expect(gemini(#"{"session_id":"g","hook_event_name":"BeforeAgent","prompt":"hi"}"#) == .promptSubmitted)
        #expect(gemini(#"{"session_id":"g","hook_event_name":"AfterAgent","prompt_response":"Done. Updated 3 files."}"#)
                == .turnCompleted(summary: "Done. Updated 3 files."))
    }

    @Test func tools() {
        #expect(gemini(#"{"session_id":"g","hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls -la"}}"#)
                == .toolStarted(name: "run_shell_command", detail: "ls -la"))
        #expect(gemini(#"{"session_id":"g","hook_event_name":"BeforeTool","tool_name":"read_file","tool_input":{"absolute_path":"/a/b/c.txt"}}"#)
                == .toolStarted(name: "read_file", detail: "c.txt"))
        #expect(gemini(#"{"session_id":"g","hook_event_name":"AfterTool","tool_name":"read_file","tool_response":{"error":"ENOENT"}}"#)
                == .toolFinished(name: "read_file", failed: true))
        #expect(gemini(#"{"session_id":"g","hook_event_name":"AfterTool","tool_name":"read_file","tool_response":{"llmContent":"x","error":null}}"#)
                == .toolFinished(name: "read_file", failed: false))
    }

    @Test func toolPermissionNotificationNeedsInput() {
        #expect(gemini(#"{"session_id":"g","hook_event_name":"Notification","notification_type":"ToolPermission","message":"Allow shell?"}"#)
                == .needsInput(reason: "permission", message: "Allow shell?"))
    }

    @Test func compressAndSession() {
        #expect(gemini(#"{"session_id":"g","hook_event_name":"PreCompress","trigger":"auto"}"#) == .compactStarted)
        #expect(gemini(#"{"session_id":"g","hook_event_name":"SessionStart","source":"startup"}"#) == .sessionStarted)
        #expect(gemini(#"{"session_id":"g","hook_event_name":"SessionEnd","reason":"exit"}"#) == .sessionEnded)
    }
}

@Suite struct AntigravityAdapterTests {
    @Test func sessionIsTheConversationAndProjectTheFirstWorkspace() {
        let json = #"{"conversationId":"0b1c-22","workspacePaths":["/src/app","/src/lib"],"modelName":"gemini-3-pro"}"#
        let event = AdapterRegistry.event(agent: .antigravity, payload: payload(json), eventHint: "SessionStart")
        #expect(event?.sessionId == "0b1c-22")
        #expect(event?.cwd == "/src/app")
        #expect(event?.kind == .sessionStarted)
    }

    @Test func withoutAConversationThereIsNoEvent() {
        #expect(antigravity("SessionStart", #"{"session_id":"a"}"#) == nil)
    }

    @Test func onlyTheFirstModelCallOfATurnIsAPrompt() {
        #expect(antigravity("PreInvocation", #"{"conversationId":"a","invocationNum":0,"initialNumSteps":4}"#) == .promptSubmitted)
        #expect(antigravity("PreInvocation", #"{"conversationId":"a","invocationNum":3,"initialNumSteps":4}"#) == nil)
        #expect(antigravity("PostInvocation", #"{"conversationId":"a","invocationNum":0}"#) == nil)
    }

    @Test func tools() {
        #expect(antigravity("PreToolUse", #"{"conversationId":"a","toolCall":{"name":"run_command","args":{"CommandLine":"npm test","Cwd":"/src/app"}},"stepIdx":2}"#)
                == .toolStarted(name: "run_command", detail: "npm test"))
        #expect(antigravity("PreToolUse", #"{"conversationId":"a","toolCall":{"name":"view_file","args":{"AbsolutePath":"/src/app/main.swift"}}}"#)
                == .toolStarted(name: "view_file", detail: "main.swift"))
        #expect(antigravity("PostToolUse", #"{"conversationId":"a","toolCall":{"name":"run_command","args":{}},"error":""}"#)
                == .toolFinished(name: "run_command", failed: false))
        #expect(antigravity("PostToolUse", #"{"conversationId":"a","toolCall":{"name":"run_command","args":{}},"error":"exit status 1"}"#)
                == .toolFinished(name: "run_command", failed: true))
    }

    @Test func stop() {
        #expect(antigravity("Stop", #"{"conversationId":"a","executionNum":1,"terminationReason":"model_stop","fullyIdle":true}"#)
                == .turnCompleted(summary: nil))
        #expect(antigravity("Stop", #"{"conversationId":"a","terminationReason":"error","error":"Quota exceeded"}"#)
                == .turnFailed(message: "Quota exceeded"))
        #expect(antigravity("Stop", #"{"conversationId":"a","terminationReason":"max_steps_exceeded"}"#)
                == .turnFailed(message: "Reached its step limit"))
    }

    /// Payloads as agy 1.4.1 sent them, trimmed of paths.
    @Test func realAgyPayloads() {
        let tool = #"{"artifactDirectoryPath":"/b","conversationId":"63d70cb9","modelName":"gemini-3.8-flash-medium","stepIdx":2,"toolCall":{"args":{"AbsolutePath":"/w/notes.txt","toolAction":"Reading notes.txt","toolSummary":"Read notes file"},"name":"view_file"},"transcriptPath":"/t","workspacePaths":["/w"]}"#
        #expect(antigravity("PreToolUse", tool) == .toolStarted(name: "view_file", detail: "notes.txt"))
        #expect(antigravity("PreToolUse", #"{"conversationId":"a","toolCall":{"args":{"toolAction":"Searching the web"},"name":"search_web"}}"#)
                == .toolStarted(name: "search_web", detail: "Searching the web"))
        let stop = #"{"conversationId":"d5ffbc7b","error":"","executionNum":0,"fullyIdle":true,"terminationReason":"NO_TOOL_CALL","workspacePaths":["/w"]}"#
        #expect(antigravity("Stop", stop) == .turnCompleted(summary: nil))
        #expect(antigravity("Stop", #"{"conversationId":"a","terminationReason":"MAX_STEPS_EXCEEDED"}"#) == .turnFailed(message: "Reached its step limit"))
    }

    @Test func repliesWithADecisionWhereOneIsRequired() {
        #expect(AdapterRegistry.reply(agent: .antigravity, event: "PreToolUse") == #"{"decision":"allow"}"# + "\n")
        #expect(AdapterRegistry.reply(agent: .antigravity, event: "Stop") == #"{"decision":"allow"}"# + "\n")
        #expect(AdapterRegistry.reply(agent: .antigravity, event: "PostToolUse") == "{}\n")
        #expect(AdapterRegistry.reply(agent: .antigravity, event: nil) == "{}\n")
        #expect(AdapterRegistry.reply(agent: .gemini, event: nil) == "{}\n")
        #expect(AdapterRegistry.reply(agent: .claude, event: "Stop") == nil)
    }
}

private func event(_ agent: AgentKind, _ json: String, hint: String? = nil) -> AgentEvent? {
    AdapterRegistry.event(agent: agent, payload: payload(json), eventHint: hint)
}

@Suite struct CursorAdapterTests {
    @Test func sessionIsTheConversationAndProjectTheFirstWorkspaceRoot() {
        let e = event(.cursor, #"{"conversation_id":"c-1","generation_id":"g","hook_event_name":"beforeSubmitPrompt","workspace_roots":["/src/web"],"prompt":"secret"}"#)
        #expect(e?.sessionId == "c-1")
        #expect(e?.cwd == "/src/web")
        #expect(e?.kind == .promptSubmitted)
    }

    @Test func toolsShowWhenTheyFinish() {
        #expect(event(.cursor, #"{"conversation_id":"c","hook_event_name":"postToolUse","tool_name":"Shell","tool_input":{"command":"ls"}}"#)?.kind
                == .toolFinished(name: "Shell", failed: false))
        #expect(event(.cursor, #"{"conversation_id":"c","hook_event_name":"postToolUseFailure","tool_name":"Shell","failure_type":"error"}"#)?.kind
                == .toolFinished(name: "Shell", failed: true))
    }

    @Test func stopAndSession() {
        #expect(event(.cursor, #"{"conversation_id":"c","hook_event_name":"stop","status":"completed","loop_count":0}"#)?.kind == .turnCompleted(summary: nil))
        #expect(event(.cursor, #"{"conversation_id":"c","hook_event_name":"stop","status":"error"}"#)?.kind == .turnFailed(message: nil))
        #expect(event(.cursor, #"{"conversation_id":"c","session_id":"c","hook_event_name":"sessionStart"}"#)?.kind == .sessionStarted)
        #expect(event(.cursor, #"{"conversation_id":"c","hook_event_name":"sessionEnd","reason":"window_close"}"#)?.kind == .sessionEnded)
    }

    @Test func neverRepliesSoItNeverDecidesAnything() {
        #expect(AdapterRegistry.reply(agent: .cursor, event: "beforeSubmitPrompt") == nil)
    }
}

@Suite struct CopilotAdapterTests {
    @Test func toolArgsMayBeAJSONString() {
        let kind = event(.copilot, #"{"sessionId":"s","timestamp":1704614600000,"cwd":"/src/app","toolName":"bash","toolArgs":"{\"command\":\"npm test\"}"}"#, hint: "preToolUse")?.kind
        #expect(kind == .toolStarted(name: "bash", detail: "npm test"))
        let object = event(.copilot, #"{"sessionId":"s","toolName":"view","toolArgs":{"path":"/src/app/main.ts"}}"#, hint: "preToolUse")?.kind
        #expect(object == .toolStarted(name: "view", detail: "main.ts"))
    }

    @Test func lifecycle() {
        let start = event(.copilot, #"{"sessionId":"s","cwd":"/src/app","source":"new"}"#, hint: "sessionStart")
        #expect(start?.kind == .sessionStarted)
        #expect(start?.cwd == "/src/app")
        #expect(event(.copilot, #"{"sessionId":"s","prompt":"secret"}"#, hint: "userPromptSubmitted")?.kind == .promptSubmitted)
        #expect(event(.copilot, #"{"sessionId":"s","stopReason":"end_turn"}"#, hint: "agentStop")?.kind == .turnCompleted(summary: nil))
        #expect(event(.copilot, #"{"sessionId":"s","toolName":"bash","error":"exit 1"}"#, hint: "postToolUseFailure")?.kind
                == .toolFinished(name: "bash", failed: true))
        #expect(event(.copilot, #"{"sessionId":"s","reason":"user_exit"}"#, hint: "sessionEnd")?.kind == .sessionEnded)
    }

    @Test func permissionPromptsNeedYouAndIdleRemindersDont() {
        // The payload names the event in PascalCase; the command passes camelCase.
        #expect(event(.copilot, #"{"sessionId":"s","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow bash?"}"#, hint: "notification")?.kind
                == .needsInput(reason: "permission", message: "Allow bash?"))
        #expect(event(.copilot, #"{"sessionId":"s","hook_event_name":"Notification","notification_type":"agent_idle","message":"Idle"}"#, hint: "notification") == nil)
    }

    @Test func onlyUnrecoverableErrorsFailTheTurn() {
        #expect(event(.copilot, #"{"sessionId":"s","error":{"message":"Rate limited","name":"E"},"recoverable":false}"#, hint: "errorOccurred")?.kind
                == .turnFailed(message: "Rate limited"))
        #expect(event(.copilot, #"{"sessionId":"s","error":{"message":"Retrying"},"recoverable":true}"#, hint: "errorOccurred")?.kind
                == .notice(message: "Retrying"))
    }
}

@Suite struct OpenCodeAdapterTests {
    @Test func itsPluginSpeaksClaudesFormat() {
        let e = event(.opencode, #"{"session_id":"ses_1","hook_event_name":"PreToolUse","cwd":"/src/app","tool_name":"bash","tool_input":{"command":"bun test"}}"#)
        #expect(e?.agent == .opencode)
        #expect(e?.kind == .toolStarted(name: "bash", detail: "bun test"))
    }
}

@Suite struct CustomAdapterTests {
    @Test func everyEvent() {
        func kind(_ json: String) -> EventKind? { event(.custom, json)?.kind }
        #expect(kind(#"{"session_id":"b","event":"start"}"#) == .sessionStarted)
        #expect(kind(#"{"session_id":"b","event":"working"}"#) == .promptSubmitted)
        #expect(kind(#"{"session_id":"b","event":"working","tool":"pytest","detail":"tests/  unit"}"#) == .toolStarted(name: "pytest", detail: "tests/ unit"))
        #expect(kind(#"{"session_id":"b","event":"waiting","message":"Apply the edit?"}"#) == .needsInput(reason: "question", message: "Apply the edit?"))
        #expect(kind(#"{"session_id":"b","event":"waiting","reason":"permission"}"#) == .needsInput(reason: "permission", message: nil))
        #expect(kind(#"{"session_id":"b","event":"done","message":"Shipped"}"#) == .turnCompleted(summary: "Shipped"))
        #expect(kind(#"{"session_id":"b","event":"error","message":"Build failed"}"#) == .turnFailed(message: "Build failed"))
        #expect(kind(#"{"session_id":"b","event":"end"}"#) == .sessionEnded)
        #expect(kind(#"{"session_id":"b","event":"idle"}"#) == .sessionEnded)
        #expect(kind(#"{"session_id":"b","event":"dance"}"#) == nil)
        #expect(kind(#"{"event":"done"}"#) == nil)
    }

    @Test func theAgentNamesItselfBriefly() {
        let e = event(.custom, #"{"session_id":"b","event":"working","agent":"Aider","cwd":"/src/cli"}"#)
        #expect(e?.agentName == "Aider")
        #expect(e?.cwd == "/src/cli")
        let long = event(.custom, #"{"session_id":"b","event":"working","agent":"\#(String(repeating: "x", count: 60))"}"#)
        #expect((long?.agentName?.count ?? 0) <= 24)
    }

    @Test func theEventCanComeFromTheCommandInstead() {
        #expect(event(.custom, #"{"session_id":"b"}"#, hint: "done")?.kind == .turnCompleted(summary: nil))
    }

    @Test func longSessionIdsAreCut() {
        let e = event(.custom, #"{"session_id":"\#(String(repeating: "s", count: 500))","event":"start"}"#)
        #expect((e?.sessionId.count ?? 0) <= 128)
    }
}

@Suite struct ToolNameTests {
    @Test func displayNames() {
        #expect(ToolNames.display("Bash") == "Bash")
        #expect(ToolNames.display("mcp__github__create_pull_request") == "github · create_pull_request")
        #expect(ToolNames.display("run_shell_command") == "Shell")
        #expect(ToolNames.display("replace_file_content") == "Edit")
        #expect(ToolNames.display("bash") == "Shell")
        #expect(ToolNames.display("apply_patch") == "Patch")
        #expect(ToolNames.display("replace") == "Edit")
    }
}
