import Foundation
import Testing
@testable import AmbientCore

@Suite struct SessionTitlesTests {
    let home: URL

    init() throws {
        home = try shortTempDir()
    }

    private func write(_ path: String, _ text: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func claude(_ id: String, desktop: String? = nil) -> Session {
        var s = Session(agent: .claude, sessionId: id, at: Date())
        s.cwd = "/src/web"
        if let desktop {
            s.host = HostInfo(bundleId: "com.anthropic.claudefordesktop")
            s.host?.hostSessionId = desktop
        }
        return s
    }

    @Test func claudeDesktopChatTitle() throws {
        try write("Library/Application Support/Claude/claude-code-sessions/acct/org/local_ab-12.json",
                  #"{"sessionId":"local_ab-12","cliSessionId":"c1","title":"Fix the  login\nflow","titleSource":"auto"}"#)
        #expect(SessionTitles(userHome: home).title(for: claude("c1", desktop: "local_ab-12")) == "Fix the login flow")
    }

    @Test func claudeTranscriptLatestCustomTitle() throws {
        try write(".claude/projects/-src-web/0f2c9a1e-1111-4222-8333-444455556666.jsonl", [
            #"{"type":"user","message":{"content":"hi"}}"#,
            #"{"type":"custom-title","customTitle":"Old name","sessionId":"0f2c9a1e-1111-4222-8333-444455556666"}"#,
            #"{"type":"assistant","message":{"content":"custom-title in prose must not count"}}"#,
            #"{"type":"custom-title","customTitle":"Release checklist","sessionId":"0f2c9a1e-1111-4222-8333-444455556666"}"#,
        ].joined(separator: "\n"))
        #expect(SessionTitles(userHome: home).title(for: claude("0f2c9a1e-1111-4222-8333-444455556666")) == "Release checklist")
    }

    @Test func desktopFallsBackToTheTranscript() throws {
        try write(".claude/projects/-src-web/c2.jsonl", #"{"type":"custom-title","customTitle":"From transcript"}"#)
        #expect(SessionTitles(userHome: home).title(for: claude("c2", desktop: "local_missing")) == "From transcript")
    }

    @Test func codexThreadNameLatestWins() throws {
        try write(".codex/session_index.jsonl", [
            #"{"id":"01a0a9a2-71a1-72a3-b157-ee03ee229ef3","thread_name":"Reddit model","updated_at":"2026-09-26T10:00:00Z"}"#,
            #"{"id":"01a0e3dd-9fa0-7930-ac46-be74be3f40ce","thread_name":"Something else"}"#,
            "not json",
            #"{"id":"01a0a9a2-71a1-72a3-b157-ee03ee229ef3","thread_name":"Build Reddit post generator"}"#,
        ].joined(separator: "\n"))
        let s = Session(agent: .codex, sessionId: "01a0a9a2-71a1-72a3-b157-ee03ee229ef3", at: Date())
        #expect(SessionTitles(userHome: home).title(for: s) == "Build Reddit post generator")
    }

    @Test func noSourceNoTitle() {
        let titles = SessionTitles(userHome: home)
        #expect(titles.title(for: claude("nothing-here")) == nil)
        #expect(titles.title(for: Session(agent: .gemini, sessionId: "g1", at: Date())) == nil)
        #expect(titles.title(for: Session(agent: .codex, sessionId: "x", at: Date())) == nil)
    }

    @Test func idsFromHooksNeverBecomePaths() throws {
        try write("Library/Application Support/Claude/claude-code-sessions/a/b/secret.json", #"{"title":"leak"}"#)
        try write(".claude/projects/p/secret.jsonl", #"{"type":"custom-title","customTitle":"leak"}"#)
        let titles = SessionTitles(userHome: home)
        #expect(titles.title(for: claude("../p/secret", desktop: "local_../../a/b/secret")) == nil)
        #expect(titles.title(for: claude("*", desktop: "local_*")) == nil)
    }

    @Test func longTitlesAreTrimmed() throws {
        try write(".claude/projects/-src-web/c3.jsonl",
                  #"{"type":"custom-title","customTitle":"\#(String(repeating: "word ", count: 30))"}"#)
        let title = try #require(SessionTitles(userHome: home).title(for: claude("c3")))
        #expect(title.count == SessionTitles.maxLength)
        #expect(title.hasSuffix("…"))
    }
}
