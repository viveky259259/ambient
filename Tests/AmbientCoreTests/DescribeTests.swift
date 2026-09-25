import Foundation
import Testing
@testable import AmbientCore

@Suite struct DescribeTests {
    @Test func activities() {
        #expect(Describe.activity(.thinking) == "Thinking")
        #expect(Describe.activity(.tool(name: "Bash", detail: "npm test")) == "Bash · npm test")
        #expect(Describe.activity(.tool(name: "mcp__linear__get_issue", detail: nil)) == "linear · get_issue")
        #expect(Describe.activity(.waiting(reason: "permission", message: "Bash: rm -rf build")) == "Needs permission · Bash: rm -rf build")
        #expect(Describe.activity(.waiting(reason: "question", message: nil)) == "Has a question")
        #expect(Describe.activity(.done(summary: "Fixed it")) == "Done · Fixed it")
        #expect(Describe.activity(.done(summary: nil)) == "Done")
        #expect(Describe.activity(.error(message: "Rate limited")) == "Failed · Rate limited")
        #expect(Describe.activity(.compacting) == "Compacting context")
        #expect(Describe.activity(.idle) == "Idle")
    }

    @Test func shortActivityForTightSpaces() {
        #expect(Describe.shortActivity(.tool(name: "run_shell_command", detail: "ls")) == "Shell")
        #expect(Describe.shortActivity(.waiting(reason: "permission", message: "x")) == "Needs you")
        #expect(Describe.shortActivity(.done(summary: "x")) == "Done")
    }

    @Test func durations() {
        #expect(Describe.duration(4) == "4s")
        #expect(Describe.duration(59.6) == "59s")
        #expect(Describe.duration(61) == "1m")
        #expect(Describe.duration(3_599) == "59m")
        #expect(Describe.duration(3_900) == "1h 5m")
        #expect(Describe.duration(7_200) == "2h")
        #expect(Describe.duration(-3) == "0s")
    }

    @Test func sessionTitleFallsBackToAgent() {
        var s = Session(agent: .codex, sessionId: "x", at: Date())
        #expect(Describe.title(s) == "Codex")
        s.cwd = "/src/web"
        #expect(Describe.title(s) == "web")
    }
}

@Suite struct DemoTests {
    @Test(arguments: Mood.allCases)
    func demoEventsProduceTheRequestedMood(mood: Mood) {
        let store = SessionStore()
        store.apply(AgentEvent(agent: .claude, sessionId: "demo-claude-ambient-demo", cwd: nil, kind: .promptSubmitted,
                               timestamp: Date().addingTimeInterval(-500)))
        for e in Demo.events(for: mood) { store.apply(e) }
        #expect(store.mood == mood)
    }

    @Test func moodNames() {
        #expect(Demo.mood(named: "Waiting") == .waiting)
        #expect(Demo.mood(named: "nope") == nil)
    }
}
