import Foundation
import Testing
@testable import AmbientCore

@Suite struct EventTests {
    static let allKinds: [EventKind] = [
        .sessionStarted,
        .promptSubmitted,
        .toolStarted(name: "Bash", detail: "npm test"),
        .toolStarted(name: "Read", detail: nil),
        .toolFinished(name: "Bash", failed: true),
        .needsInput(reason: "permission", message: "Allow Bash?"),
        .compactStarted,
        .compactFinished,
        .subagentStarted,
        .subagentFinished,
        .turnCompleted(summary: "Fixed it"),
        .turnFailed(message: nil),
        .sessionEnded,
        .notice(message: "Logged in"),
    ]

    @Test(arguments: allKinds)
    func eventRoundTripsThroughJSON(kind: EventKind) throws {
        let event = AgentEvent(
            agent: .codex, sessionId: "s1", cwd: "/tmp/api-server", kind: kind,
            timestamp: Date(timeIntervalSince1970: 1_790_000_000.123),
            host: HostInfo(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal", pids: [10, 1])
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func projectIsLastPathComponentOfCwd() {
        let e = AgentEvent(agent: .claude, sessionId: "s", cwd: "/Users/me/src/api-server/", kind: .sessionStarted)
        #expect(e.project == "api-server")
        let none = AgentEvent(agent: .claude, sessionId: "s", cwd: nil, kind: .sessionStarted)
        #expect(none.project == nil)
    }

    @Test func agentDisplayNames() {
        #expect(AgentKind.claude.displayName == "Claude")
        #expect(AgentKind.codex.displayName == "Codex")
        #expect(AgentKind.gemini.displayName == "Gemini")
    }
}

@Suite struct TrimTests {
    @Test func shortTextIsUnchanged() {
        #expect(Trim.truncate("hello", max: 10) == "hello")
    }

    @Test func longTextIsCutWithEllipsis() {
        let out = Trim.truncate("abcdefghijklmnop", max: 8)
        #expect(out == "abcdefg…")
        #expect(out.count == 8)
    }

    @Test func whitespaceIsCollapsed() {
        #expect(Trim.truncate("  git   status\n\n --short \t", max: 80) == "git status --short")
    }

    @Test func emojiAreNotSplit() {
        let out = Trim.truncate("👩‍💻👩‍💻👩‍💻👩‍💻", max: 3)
        #expect(out == "👩‍💻👩‍💻…")
    }

    @Test func emptyOrBlankBecomesNil() {
        #expect(Trim.clean("   \n ", max: 10) == nil)
        #expect(Trim.clean(nil, max: 10) == nil)
        #expect(Trim.clean(" x ", max: 10) == "x")
    }
}
