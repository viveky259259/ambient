import Foundation
import Testing
@testable import AmbientCore

@Suite struct NeedTests {
    @Test func toolsDecideTheNeed() {
        #expect(Need.forTool("Bash") == .command)
        #expect(Need.forTool("run_shell_command") == .command)
        #expect(Need.forTool("exec_command") == .command)
        #expect(Need.forTool("bash") == .command)
        #expect(Need.forTool("apply_patch") == .edit)
        #expect(Need.forTool("write_file") == .edit)
        #expect(Need.forTool("webfetch") == .web)
        #expect(Need.forTool("google_web_search") == .web)
        #expect(Need.forTool("ExitPlanMode") == .plan)
        #expect(Need.forTool("AskUserQuestion") == .question)
        #expect(Need.forTool("question") == .question)
        #expect(Need.forTool("shell") == .command)
        #expect(ToolNames.display("subagent") == "Task")
        #expect(Need.forTool("Grep") == .permission)
        #expect(Need.forTool("mcp__linear__get_issue") == .permission)
    }

    @Test func oldReasonsStillRead() {
        #expect(Need(reason: "permission") == .permission)
        #expect(Need(reason: "question") == .question)
        #expect(Need.permission.isPermission)
        #expect(Need.plan.isPermission)
        #expect(!Need.question.isPermission)
    }
}

@Suite struct WaitingStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ kind: EventKind, _ offset: TimeInterval, agent: AgentKind = .claude) -> AgentEvent {
        AgentEvent(agent: agent, sessionId: "s", cwd: "/src/app", kind: kind, timestamp: t0.addingTimeInterval(offset))
    }

    private func activity(_ store: SessionStore, agent: AgentKind = .claude) -> Activity? {
        store.session(id: "\(agent.rawValue):s")?.activity
    }

    /// Claude's PermissionRequest hook, then its notification of the same prompt, which says less.
    @Test func aPromptThatSaysLessDoesntReplaceOneThatSaysMore() {
        let store = SessionStore()
        store.apply(event(.promptSubmitted, 0))
        store.apply(event(.needsInput(reason: "command", message: "rm -rf build"), 1))
        store.apply(event(.needsInput(reason: "command", message: nil), 2))
        #expect(activity(store) == .waiting(reason: "command", message: "rm -rf build"))
        store.apply(event(.needsInput(reason: "permission", message: "Bash"), 3))
        #expect(activity(store) == .waiting(reason: "command", message: "rm -rf build"))

        store.apply(event(.needsInput(reason: "permission", message: "Read: secrets.txt"), 4))
        store.apply(event(.needsInput(reason: "question", message: "Ship it?"), 5))
        #expect(activity(store) == .waiting(reason: "question", message: "Ship it?"))
    }

    @Test func aPromptWithNewDetailReplacesTheOneOnShow() {
        let store = SessionStore()
        store.apply(event(.needsInput(reason: "permission", message: "Read: secrets.txt"), 0))
        store.apply(event(.needsInput(reason: "permission", message: "Read"), 1))
        #expect(activity(store) == .waiting(reason: "permission", message: "Read: secrets.txt"))
        store.apply(event(.needsInput(reason: "permission", message: "Deploy to prod?"), 2))
        #expect(activity(store) == .waiting(reason: "permission", message: "Deploy to prod?"))
        // A session saved by an older version said only "permission"; anything more specific says more.
        store.apply(event(.needsInput(reason: "command", message: "make deploy"), 3))
        #expect(activity(store) == .waiting(reason: "command", message: "make deploy"))
    }

    /// OpenCode says when a prompt is answered: the session goes back to the tool it interrupted.
    @Test func anAnsweredPromptReturnsToWhatItInterrupted() {
        let store = SessionStore()
        store.apply(event(.promptSubmitted, 0, agent: .opencode))
        store.apply(event(.toolStarted(name: "bash", detail: "bun test"), 1, agent: .opencode))
        let waiting = store.apply(event(.needsInput(reason: "command", message: "bun test"), 2, agent: .opencode))
        #expect(waiting?.session.mood == .waiting)
        let answered = store.apply(event(.answered, 3, agent: .opencode))
        #expect(answered?.session.activity == .tool(name: "bash", detail: "bun test"))
        #expect(answered?.session.mood == .working)
        #expect(store.session(id: "opencode:s")?.toolCount == 1)

        // An answer to a prompt that's gone already changes nothing.
        store.apply(event(.toolFinished(name: "bash", failed: false), 4, agent: .opencode))
        store.apply(event(.answered, 5, agent: .opencode))
        #expect(activity(store, agent: .opencode) == .thinking)

        // A prompt between tools goes back to thinking.
        store.apply(event(.needsInput(reason: "question", message: "Which?"), 6, agent: .opencode))
        store.apply(event(.answered, 7, agent: .opencode))
        #expect(activity(store, agent: .opencode) == .thinking)
    }

    /// The tool and its permission prompt leave OpenCode a millisecond apart, in separate processes. The prompt must
    /// stay on show whichever reaches the app first.
    @Test func aToolThatArrivesAfterItsPromptDoesntHideIt() {
        let store = SessionStore()
        store.apply(event(.promptSubmitted, 0, agent: .opencode))
        store.apply(event(.needsInput(reason: "command", message: "bun test"), 0.002, agent: .opencode))
        #expect(store.apply(event(.toolStarted(name: "bash", detail: "bun test"), 0.001, agent: .opencode)) == nil)
        #expect(activity(store, agent: .opencode) == .waiting(reason: "command", message: "bun test"))
    }

    /// A subagent run in OpenCode 2.2.6, in the order its events reached the socket, with OpenCode's own times. The
    /// shell call's start landed after its permission prompt.
    @Test func aLiveOpenCodeRunReadsRightInTheOrderItArrived() {
        let store = SessionStore()
        func at(_ ms: Double, _ kind: EventKind) -> Activity? {
            store.apply(event(kind, ms / 1000, agent: .opencode))
            return activity(store, agent: .opencode)
        }
        _ = at(0, .sessionStarted)
        _ = at(4, .promptSubmitted)
        _ = at(2157, .toolStarted(name: "subagent", detail: "Create sub.txt"))
        #expect(at(3707, .needsInput(reason: "edit", message: "sub.txt")) == .waiting(reason: "edit", message: "sub.txt"))
        #expect(at(3710, .answered) == .tool(name: "subagent", detail: "Create sub.txt"))
        #expect(at(5120, .needsInput(reason: "command", message: "printf 'hi' > sub.txt")) == .waiting(reason: "command", message: "printf 'hi' > sub.txt"))
        #expect(at(5124, .answered) == .tool(name: "subagent", detail: "Create sub.txt"))
        #expect(at(6991, .toolFinished(name: "subagent", failed: false)) == .thinking)
        #expect(at(11994, .needsInput(reason: "command", message: "ls -la sub.txt 2>&1")) == .waiting(reason: "command", message: "ls -la sub.txt 2>&1"))
        #expect(at(11988, .toolStarted(name: "shell", detail: "ls -la sub.txt 2>&1")) == .waiting(reason: "command", message: "ls -la sub.txt 2>&1"))
        #expect(at(11997, .answered) == .thinking)
        _ = at(11998, .toolFinished(name: "shell", failed: true))
        _ = at(14265, .toolStarted(name: "write", detail: "sub.txt"))
        #expect(at(14271, .needsInput(reason: "edit", message: "sub.txt")) == .waiting(reason: "edit", message: "sub.txt"))
        #expect(at(14274, .answered) == .tool(name: "write", detail: "sub.txt"))
        _ = at(14275, .toolFinished(name: "write", failed: true))
        #expect(at(15878, .turnCompleted(summary: nil)) == .done(summary: nil))
    }

    @Test func questionsAreNeverAnsweredFromTheIsland() {
        let question = AgentEvent(agent: .claude, sessionId: "s", cwd: nil, kind: .needsInput(reason: "question", message: "Ship it?"))
        let payload = HookPayload(["hook_event_name": "PermissionRequest", "tool_name": "AskUserQuestion"])
        #expect(PermissionAsk.make(event: question, payload: payload) == nil)

        let command = AgentEvent(agent: .claude, sessionId: "s", cwd: nil, kind: .needsInput(reason: "command", message: "ls"))
        let bash = HookPayload(["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "ls"]])
        #expect(PermissionAsk.make(event: command, payload: bash)?.hint == "ls")
    }

    @Test func remotePromptsGetTheirNeedFromWhatTheMachineSends() {
        func kind(_ reason: String?, _ message: String?) -> EventKind? {
            RemoteEvent(seq: 1, id: String(repeating: "a", count: 32), ts: t0, agent: .claude, session: "s",
                        kind: .needsInput, reason: reason, message: message).eventKind
        }
        // The full level sends the tool's name for a permission request, and Claude's words for its notification.
        #expect(kind("permission", "Bash") == .needsInput(reason: "command", message: nil))
        #expect(kind("permission", "Claude needs your permission to use Edit") == .needsInput(reason: "edit", message: nil))
        #expect(kind("permission", "mcp__github__create_pr") == .needsInput(reason: "permission", message: "github · create_pr"))
        // The standard level sends no message: the reason alone still says what's needed.
        #expect(kind("permission", nil) == .needsInput(reason: "permission", message: nil))
        #expect(kind("question", "Pick one") == .needsInput(reason: "question", message: "Pick one"))
        #expect(kind(nil, nil) == .needsInput(reason: "question", message: nil))
    }

    /// From `ambient-remote` 1.0.7 a permission request names its tool at the standard level too. The decoder is the
    /// one hubs have had since 0.8.0, so this is also what an older hub reads: the same reason, and `tool` it allowed.
    @Test func remotePromptsNameTheirToolFromTheStandardLevelOn() throws {
        func line(_ more: String, reason: String = "permission") throws -> RemoteEvent {
            let id = String(repeating: "a", count: 32)
            return try RemoteEventDecoder.decode(Data(#"{"v":1,"seq":1,"id":"\#(id)","ts":1800000000,"agent":"claude","session":"s","kind":"needsInput","reason":"\#(reason)"\#(more)}"#.utf8))
        }
        let bash = try line(#","tool":"Bash""#)
        #expect(bash.reason == "permission" && bash.tool == "Bash")
        let standard = bash.redacted(to: .standard).eventKind
        #expect(standard == .needsInput(reason: "command", message: nil))
        if case let .needsInput(reason, message)? = standard {
            #expect(Describe.activity(.waiting(reason: reason, message: message)) == "Approve a command")
        }
        #expect(try line(#","tool":"Edit""#).redacted(to: .standard).eventKind == .needsInput(reason: "edit", message: nil))
        #expect(try line(#","tool":"WebFetch""#).redacted(to: .standard).eventKind == .needsInput(reason: "web", message: nil))
        #expect(try line(#","tool":"AskUserQuestion""#).redacted(to: .standard).eventKind == .needsInput(reason: "question", message: nil))
        // No need fits this tool, so its name is the detail, as at the full level.
        #expect(try line(#","tool":"mcp__github__create_pr""#).redacted(to: .standard).eventKind
            == .needsInput(reason: "permission", message: "github · create_pr"))
        // At full the message is the same name, which adds nothing to the headline.
        #expect(try line(#","tool":"Bash","message":"Bash""#).redacted(to: .full).eventKind == .needsInput(reason: "command", message: nil))
        #expect(try line(#","tool":"mcp__github__create_pr","message":"mcp__github__create_pr""#).redacted(to: .full).eventKind
            == .needsInput(reason: "permission", message: "github · create_pr"))
        // The agent's own words for the prompt are kept when they say more, and the tool still gives the need.
        #expect(try line(#","tool":"Bash","message":"Run the migration on prod?""#).redacted(to: .full).eventKind
            == .needsInput(reason: "command", message: "Run the migration on prod?"))
        #expect(try line(#","tool":"Bash","message":"Claude needs your permission to use Bash""#).redacted(to: .full).eventKind
            == .needsInput(reason: "command", message: nil))
        // Without a tool, as from a shim before 1.0.7, the message gives both.
        #expect(try line(#","message":"Claude needs your permission to use Edit""#).redacted(to: .full).eventKind
            == .needsInput(reason: "edit", message: nil))
        #expect(try line("").redacted(to: .full).eventKind == .needsInput(reason: "permission", message: nil))
        // At metadata the name stays on the machine, and the hub drops one spooled before the level was tightened.
        #expect(bash.redacted(to: .metadata).tool == nil)
        #expect(bash.redacted(to: .metadata).eventKind == .needsInput(reason: "permission", message: nil))
        // A question is a question whatever tool it came with.
        #expect(try line(#","tool":"Bash""#, reason: "question").eventKind == .needsInput(reason: "question", message: nil))
        // Older hubs refuse any reason but these two, which is why the machine never sends the finer need.
        #expect(throws: RemoteRejection.invalid("reason")) { try line("", reason: "command") }
    }

    @Test func answeredRoundTripsOverTheWire() throws {
        let e = AgentEvent(agent: .opencode, sessionId: "s", cwd: nil, kind: .answered, timestamp: t0)
        #expect(try Wire.decode(Wire.encode(.event(e))) == .event(e))
    }
}
