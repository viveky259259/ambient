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

@Suite struct ToolNameTests {
    @Test func displayNames() {
        #expect(ToolNames.display("Bash") == "Bash")
        #expect(ToolNames.display("mcp__github__create_pull_request") == "github · create_pull_request")
        #expect(ToolNames.display("run_shell_command") == "Shell")
        #expect(ToolNames.display("apply_patch") == "Patch")
        #expect(ToolNames.display("replace") == "Edit")
    }
}
