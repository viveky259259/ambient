import Foundation
import Testing
@testable import AmbientCore

private func session(_ agent: AgentKind = .claude, id: String = "3f2a-77", cwd: String? = "/Users/me/src/shop/api",
                     host: HostInfo?) -> Session {
    var s = Session(agent: agent, sessionId: id, at: Date())
    s.cwd = cwd
    s.host = host
    return s
}

private func routes(_ s: Session) -> [FocusRoute] {
    FocusPlanner.routes(for: s, userHome: "/Users/me")
}

@Suite struct FocusPlannerTests {
    @Test func claudeDesktopOpensTheExactChat() {
        let host = HostInfo(bundleId: "com.anthropic.claudefordesktop", hostSessionId: "local_8cfe9451-cdf8-4279-8914-31861d028f4f")
        #expect(routes(session(host: host)).first
                == .openURL("claude://code/continue?session=local_8cfe9451-cdf8-4279-8914-31861d028f4f&source=ambient"))
        #expect(routes(session(host: host)).last == .activate)
    }

    @Test func malformedHostSessionIdsAreNotLinked() {
        let host = HostInfo(bundleId: "com.anthropic.claudefordesktop", hostSessionId: "local_x&session=last")
        #expect(!routes(session(host: host)).contains { if case .openURL = $0 { true } else { false } })
    }

    @Test func codexAppOpensTheThread() {
        let host = HostInfo(bundleId: "com.openai.codex")
        #expect(routes(session(.codex, id: "019a-bc12", host: host)).first == .openURL("codex://threads/019a-bc12"))
    }

    @Test func codexInATerminalGoesToTheTerminalNotTheApp() {
        let host = HostInfo(bundleId: "com.apple.Terminal", tty: "/dev/ttys004")
        let r = routes(session(.codex, host: host))
        #expect(r.first == .terminalTab(.terminal, .device("/dev/ttys004")))
        #expect(!r.contains(.openURL("codex://threads/3f2a-77")))
    }

    @Test func terminalIsRecognizedByTermProgramToo() {
        let host = HostInfo(termProgram: "Apple_Terminal", tty: "/dev/ttys012")
        #expect(routes(session(host: host)).first == .terminalTab(.terminal, .device("/dev/ttys012")))
    }

    @Test func itermSelectsTheSession() {
        let host = HostInfo(bundleId: "com.googlecode.iterm2", tty: "/dev/ttys001")
        #expect(routes(session(host: host)).first == .terminalTab(.iterm, .device("/dev/ttys001")))
    }

    @Test func tmuxSelectsThePaneThenTheClientTab() {
        let host = HostInfo(bundleId: "com.apple.Terminal", tty: "/dev/ttys020",
                            tmuxSocket: "/private/tmp/tmux-501/default", tmuxPane: "%3")
        let r = routes(session(host: host))
        #expect(Array(r.prefix(2)) == [
            .tmuxPane(socket: "/private/tmp/tmux-501/default", pane: "%3"),
            .terminalTab(.terminal, .tmuxClient(socket: "/private/tmp/tmux-501/default", pane: "%3")),
        ])
    }

    @Test func cmuxFocusesTheSurface() {
        let host = HostInfo(bundleId: "com.cmuxterm.app", tty: "/dev/ttys030", cmuxWorkspace: "A1B2", cmuxSurface: "C3D4",
                            cmuxSocket: "/tmp/cmux.sock")
        #expect(routes(session(host: host)).first == .cmux(workspace: "A1B2", surface: "C3D4", socket: "/tmp/cmux.sock"))
    }

    @Test func editorsRaiseTheProjectWindow() {
        let host = HostInfo(bundleId: "com.microsoft.VSCode", termProgram: "vscode", tty: "/dev/ttys040")
        #expect(routes(session(host: host)) == [.window(titleHints: ["api", "shop"]), .activate])
    }

    @Test func hintsStopAtTheHomeDirectory() {
        let host = HostInfo(bundleId: "com.microsoft.VSCode")
        #expect(routes(session(cwd: "/Users/me/shop", host: host)) == [.window(titleHints: ["shop"]), .activate])
        #expect(routes(session(cwd: "/Users/me", host: host)) == [.activate])
    }

    @Test func unsafeValuesAreDropped() {
        let host = HostInfo(bundleId: "com.apple.Terminal", tty: "/dev/ttys004\"; do shell script \"x",
                            tmuxPane: "%3; kill-server", cmuxSurface: "a b")
        let r = routes(session(cwd: nil, host: host))
        #expect(r == [.activate])
    }

    @Test func trailingNewlinesDoNotSlipThrough() {
        let host = HostInfo(bundleId: "com.anthropic.claudefordesktop", tty: "/dev/ttys004\n", hostSessionId: "local_abc\n")
        #expect(routes(session(cwd: nil, host: host)) == [.activate])
    }

    @Test func noHostStillActivatesWhatItCan() {
        #expect(routes(session(cwd: nil, host: nil)) == [.activate])
    }
}

@Suite struct SessionMatcherTests {
    private func store() -> [Session] {
        let s = SessionStore()
        let t = Date()
        s.apply(AgentEvent(agent: .claude, sessionId: "aaa111", cwd: "/src/Web", kind: .promptSubmitted, timestamp: t))
        s.apply(AgentEvent(agent: .codex, sessionId: "bbb222", cwd: "/src/api", kind: .needsInput(reason: "permission", message: nil), timestamp: t))
        s.apply(AgentEvent(agent: .gemini, sessionId: "ccc333", cwd: "/src/api", kind: .promptSubmitted, timestamp: t))
        return s.sessions
    }

    @Test func noQueryPicksTheMostUrgent() {
        #expect(SessionMatcher.find(nil, in: store())?.sessionId == "bbb222")
    }

    @Test func projectNamesMatchCaseInsensitivelyPreferringUrgency() {
        #expect(SessionMatcher.find("web", in: store())?.sessionId == "aaa111")
        #expect(SessionMatcher.find("api", in: store())?.sessionId == "bbb222")
    }

    @Test func idsAndPrefixesMatch() {
        #expect(SessionMatcher.find("gemini:ccc333", in: store())?.sessionId == "ccc333")
        #expect(SessionMatcher.find("ccc", in: store())?.sessionId == "ccc333")
    }

    @Test func unknownQueriesFindNothing() {
        #expect(SessionMatcher.find("nope", in: store()) == nil)
        #expect(SessionMatcher.find(nil, in: []) == nil)
    }

    @Test func openMessagesRoundTrip() throws {
        #expect(try Wire.decode(Wire.encode(.open(query: "api"))) == .open(query: "api"))
        #expect(try Wire.decode(Wire.encode(.open(query: nil))) == .open(query: nil))
    }
}
