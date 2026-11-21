import Foundation
import Testing
@testable import AmbientCore

/// SessionTitles' transcript excerpts (opt-in context for the board's local LLM) and the edges of title lookup.
@Suite struct QASessionTitlesExcerptTests {
    let home: URL
    static let id = "0f2c9a1e-1111-4222-8333-444455556666"

    init() throws { home = try shortTempDir() }

    private func write(_ path: String, _ lines: [String]) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    private func session(_ agent: AgentKind, _ id: String = id) -> Session {
        Session(agent: agent, sessionId: id, at: Date())
    }

    private var titles: SessionTitles { SessionTitles(userHome: home) }

    @Test func claudeExcerptTakesUserAndAssistantMessagesInOrder() throws {
        try write(".claude/projects/-src-web/\(Self.id).jsonl", [
            #"{"type":"user","message":{"content":"Please fix the login bug"}}"#,
            #"{"type":"progress","text":"ignored"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at auth.swift"},{"type":"tool_use"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Fixed"},{"type":"text","text":"and tested"}]}}"#,
        ])
        let excerpt = try #require(titles.excerpt(for: session(.claude)))
        // Snippets are joined with "\n---\n", then the final truncate folds whitespace, so they read " --- ".
        #expect(excerpt == "Please fix the login bug --- Looking at auth.swift --- Fixed and tested")
    }

    @Test func claudeExcerptKeepsTheLastFourOfAtMostSixSnippets() throws {
        let lines = (1...9).map { #"{"type":"user","message":{"content":"m\#($0)"}}"# }
        try write(".claude/projects/p/\(Self.id).jsonl", lines)
        let excerpt = try #require(titles.excerpt(for: session(.claude)))
        #expect(excerpt == "m3 --- m4 --- m5 --- m6")
    }

    @Test func claudeExcerptIsTruncatedToMaxChars() throws {
        let long = String(repeating: "x", count: 500)
        try write(".claude/projects/p/\(Self.id).jsonl", [#"{"type":"user","message":{"content":"\#(long)"}}"#])
        let excerpt = try #require(titles.excerpt(for: session(.claude), maxChars: 50))
        #expect(excerpt.count <= 50)
    }

    @Test func messageTextFallsBackToTopLevelText() throws {
        try write(".claude/projects/p/\(Self.id).jsonl", [#"{"type":"user","text":"plain text form"}"#])
        #expect(titles.excerpt(for: session(.claude)) == "plain text form")
    }

    @Test func malformedAndEmptyLinesAreSkipped() throws {
        try write(".claude/projects/p/\(Self.id).jsonl", [
            #"{"type":"user", broken"#,
            #"{"type":"assistant","message":{"content":[]}}"#,
            #"{"type":"user","message":{"content":"survivor"}}"#,
        ])
        #expect(titles.excerpt(for: session(.claude)) == "survivor")
    }

    @Test func transcriptWithoutMessagesHasNoExcerpt() throws {
        try write(".claude/projects/p/\(Self.id).jsonl", [#"{"type":"custom-title","customTitle":"T"}"#])
        #expect(titles.excerpt(for: session(.claude)) == nil)
    }

    @Test func missingTranscriptHasNoExcerpt() {
        #expect(titles.excerpt(for: session(.claude)) == nil)
    }

    @Test func codexExcerptIsOnlyTheThreadName() throws {
        try write(".codex/session_index.jsonl", [
            #"{"id":"\#(Self.id)","thread_name":"First"}"#,
            #"{"id":"\#(Self.id)","thread_name":"Renamed"}"#,
        ])
        #expect(titles.excerpt(for: session(.codex)) == "thread_name: Renamed")
    }

    @Test func codexWithoutIndexHasNoExcerpt() {
        #expect(titles.excerpt(for: session(.codex)) == nil)
    }

    @Test(arguments: [AgentKind.gemini, .antigravity, .cursor, .copilot, .opencode, .custom])
    func otherAgentsHaveNoExcerptOrTitle(agent: AgentKind) throws {
        try write(".claude/projects/p/\(Self.id).jsonl", [#"{"type":"user","message":{"content":"x"}}"#])
        #expect(titles.excerpt(for: session(agent)) == nil)
        #expect(titles.title(for: session(agent)) == nil)
    }

    @Test func remoteSessionsNeverReadLocalFiles() throws {
        try write(".claude/projects/p/\(Self.id).jsonl", [
            #"{"type":"user","message":{"content":"local secret"}}"#,
            #"{"type":"custom-title","customTitle":"Local title"}"#,
        ])
        let remote = Session(agent: .claude, sessionId: Self.id, at: Date(),
                             origin: RemoteOrigin(machine: MachineRef(id: "devbox", label: "Devbox")))
        #expect(titles.excerpt(for: remote) == nil)
        #expect(titles.title(for: remote) == nil)
    }

    @Test(arguments: ["../../etc/passwd", "a/b", "has space", "", String(repeating: "a", count: 65), "id.jsonl"])
    func unsafeIDsAreNeverTurnedIntoPaths(id: String) throws {
        try write(".claude/projects/p/x.jsonl", [#"{"type":"user","message":{"content":"x"}}"#])
        #expect(titles.excerpt(for: session(.claude, id)) == nil)
        #expect(titles.excerpt(for: session(.codex, id)) == nil)
        #expect(titles.transcriptTitle(id) == nil)
        #expect(titles.codexThreadName(id) == nil)
    }

    // MARK: - Desktop titles

    @Test(arguments: [nil, "c1", "local_", "local_../x", "local_has space"])
    func desktopTitleNeedsAValidLocalID(id: String?) throws {
        try write("Library/Application Support/Claude/claude-code-sessions/a/o/local_.json", [#"{"title":"T"}"#])
        #expect(titles.desktopTitle(id) == nil)
    }

    @Test func desktopTitleSkipsUnreadableFilesInOtherOrgs() throws {
        try write("Library/Application Support/Claude/claude-code-sessions/a/o1/local_x1.json", ["not json"])
        try write("Library/Application Support/Claude/claude-code-sessions/a/o2/local_x1.json", [#"{"title":"Found"}"#])
        #expect(titles.desktopTitle("local_x1") == "Found")
    }

    @Test func desktopTitleWithoutTitleFallsBackToTranscript() throws {
        try write("Library/Application Support/Claude/claude-code-sessions/a/o/local_x2.json", [#"{"sessionId":"local_x2"}"#])
        try write(".claude/projects/p/\(Self.id).jsonl", [#"{"type":"custom-title","customTitle":"From transcript"}"#])
        var s = session(.claude)
        s.host = HostInfo(hostSessionId: "local_x2")
        #expect(titles.title(for: s) == "From transcript")
    }

    @Test func emptyTitleIsNil() throws {
        try write(".codex/session_index.jsonl", [#"{"id":"\#(Self.id)","thread_name":"   "}"#])
        #expect(titles.title(for: session(.codex)) == nil)
    }

    @Test func longTitlesAreTruncated() throws {
        let long = String(repeating: "word ", count: 40)
        try write(".codex/session_index.jsonl", [#"{"id":"\#(Self.id)","thread_name":"\#(long)"}"#])
        let title = try #require(titles.title(for: session(.codex)))
        #expect(title.count <= SessionTitles.maxLength)
    }

    @Test func lastValueIgnoresLinesTheFilterRejects() throws {
        try write("f.jsonl", [
            #"{"id":"a","thread_name":"mine"}"#,
            #"{"id":"b","thread_name":"mentions \"a\" but not mine"}"#,
        ])
        let value = SessionTitles.lastValue(in: home.appendingPathComponent("f.jsonl"), marker: "\"a\"", key: "thread_name") {
            $0["id"] as? String == "a"
        }
        #expect(value == "mine")
        #expect(SessionTitles.lastValue(in: home.appendingPathComponent("missing"), marker: "x", key: "k") { _ in true } == nil)
    }
}
