import Foundation
import Testing
@testable import AmbientHistory

private func line(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]), as: UTF8.self)
}

private func user(_ text: String, uuid: String, at: String, extra: [String: Any] = [:]) -> String {
    var object: [String: Any] = ["type": "user", "uuid": uuid, "timestamp": at, "cwd": "/repo",
                                 "gitBranch": "feat/x", "message": ["role": "user", "content": text],
                                 "origin": ["kind": "human"]]
    object.merge(extra) { _, new in new }
    return line(object)
}

private func assistant(_ blocks: [[String: Any]], uuid: String, at: String) -> String {
    line(["type": "assistant", "uuid": uuid, "timestamp": at, "message": ["role": "assistant", "content": blocks]])
}

private func results(_ blocks: [[String: Any]], uuid: String, at: String, extra: [String: Any] = [:]) -> String {
    var object: [String: Any] = ["type": "user", "uuid": uuid, "timestamp": at, "message": ["role": "user", "content": blocks]]
    object.merge(extra) { _, new in new }
    return line(object)
}

@Suite struct ClaudeTranscriptTests {
    /// A session with every kind of line the reader cares about, and one subagent.
    private func write(into scratch: Scratch) throws -> String {
        let lines = [
            line(["type": "custom-title", "customTitle": "First title", "sessionId": "s1"]),
            user("Fix the board", uuid: "u1", at: "2026-11-10T10:00:00.250Z"),
            assistant([["type": "thinking", "thinking": "", "signature": "x"],
                       ["type": "thinking", "thinking": "It must be the sort."],
                       ["type": "text", "text": "Looking."],
                       ["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "ls Sources", "description": "List sources"]]],
                      uuid: "a1", at: "2026-11-10T10:00:05.000Z"),
            results([["type": "tool_result", "tool_use_id": "t1", "content": "Board.swift\n"]], uuid: "r1", at: "2026-11-10T10:00:06.000Z"),
            assistant([["type": "tool_use", "id": "t2", "name": "Edit",
                        "input": ["file_path": "/repo/Sources/Board.swift", "old_string": "a", "new_string": "b"]],
                       ["type": "tool_use", "id": "t3", "name": "Write", "input": ["file_path": "/repo/NOTES.md", "content": "one\ntwo\n"]],
                       ["type": "tool_use", "id": "t4", "name": "Read", "input": ["file_path": "/repo/README.md"]],
                       ["type": "tool_use", "id": "t5", "name": "Agent", "input": ["description": "Write tests", "prompt": "Test the board."]],
                       ["type": "tool_use", "id": "t6", "name": "mcp__x__y", "input": ["b": 1, "a": "/p/q"]]],
                      uuid: "a2", at: "2026-11-10T10:00:10.000Z"),
            results([["type": "tool_result", "tool_use_id": "t2", "content": [["type": "text", "text": "Updated."]]]],
                    uuid: "r2", at: "2026-11-10T10:00:11.000Z",
                    extra: ["toolUseResult": ["structuredPatch": [["oldStart": 3, "oldLines": 1, "newStart": 3, "newLines": 1,
                                                                 "lines": ["-let x = a", "+let x = b"]]]]]),
            results([["type": "tool_result", "tool_use_id": "t3", "content": "Wrote it."],
                     ["type": "tool_result", "tool_use_id": "t5", "content": "Launched.", "is_error": true]],
                    uuid: "r3", at: "2026-11-10T10:00:12.000Z"),
            user("<task-notification>done</task-notification>", uuid: "u2", at: "2026-11-10T10:05:00.000Z"),
            user("Summary of earlier work", uuid: "u3", at: "2026-11-10T10:06:00.000Z", extra: ["isCompactSummary": true]),
            user("Injected skill text", uuid: "u4", at: "2026-11-10T10:06:30.000Z", extra: ["isMeta": true]),
            user("From another session", uuid: "u5", at: "2026-11-10T10:06:40.000Z", extra: ["origin": ["kind": "peer"]]),
            line(["type": "user", "uuid": "side", "isSidechain": true, "timestamp": "2026-11-10T10:06:50.000Z",
                  "message": ["role": "user", "content": "old inline subagent line"]]),
            user("Thanks, ship it", uuid: "u6", at: "2026-11-10T10:07:00.000Z"),
            user("Thanks, ship it", uuid: "u6", at: "2026-11-10T10:07:00.000Z"),
            line(["type": "pr-link", "prNumber": 35, "prRepository": "acme/widgets", "prUrl": "https://github.com/acme/widgets/pull/35"]),
            line(["type": "pr-link", "prNumber": 35, "prRepository": "acme/widgets"]),
            line(["type": "custom-title", "customTitle": "Board cleanup", "sessionId": "s1"]),
            "not json at all",
        ]
        let path = try scratch.write(lines.joined(separator: "\n") + "\n", to: "projects/-repo/s1.jsonl")
        let sub = [
            // A forked subagent's file starts with a copy of its parent's lines.
            user("Fix the board", uuid: "u1", at: "2026-11-10T10:00:00.250Z"),
            user("Test the board.", uuid: "su1", at: "2026-11-10T10:00:10.500Z"),
            assistant([["type": "text", "text": "Tests written."]], uuid: "sa1", at: "2026-11-10T10:00:20.000Z"),
        ]
        try scratch.write(sub.joined(separator: "\n"), to: "projects/-repo/s1/subagents/agent-abc.jsonl")
        try scratch.write(#"{"description":"Board tests","toolUseId":"t5","agentType":"fork"}"#,
                          to: "projects/-repo/s1/subagents/agent-abc.meta.json")
        return path
    }

    @Test func readsEveryKindOfLine() throws {
        let scratch = try Scratch()
        let chat = try ClaudeTranscript.read(path: try write(into: scratch))
        #expect(chat.sessionID == "s1")
        #expect(chat.title == "Board cleanup")
        #expect(chat.folder == "/repo")
        #expect(chat.branch == "feat/x")
        #expect(chat.pullRequests == [.init(repo: "acme/widgets", number: 35)])
        #expect(chat.startedAt == ISO8601DateFormatter().date(from: "2026-11-10T10:00:00Z")?.addingTimeInterval(0.25))

        let kinds = chat.events.map { "\($0.kind.rawValue)\($0.actor.map { "@\($0)" } ?? "")" }
        #expect(kinds == [
            "user", "thinking", "agent", "tool", "result",
            "tool", "tool", "tool", "tool", "tool", "result", "result", "result",
            // The subagent's lines sit right after the result of the call that started it, without the copied line.
            "system@Board tests", "agent@Board tests",
            "system", "system", "system", "system", "user",
        ])
        #expect(chat.events[1].text == "It must be the sort.")
        #expect(chat.events.last?.text == "Thanks, ship it")
    }

    @Test func turnsToolCallsIntoPathsAndDiffs() throws {
        let scratch = try Scratch()
        let chat = try ClaudeTranscript.read(path: try write(into: scratch))
        let tools = chat.events.filter { $0.kind == .tool }
        #expect(tools.map(\.tool) == ["Bash", "Edit", "Write", "Read", "Agent", "mcp__x__y"])
        #expect(tools[0].text == "ls Sources")
        #expect(tools[0].label == "List sources")
        #expect(tools[0].folder == "/repo")
        // The edit carries Claude's own patch from the result line, not the bare old and new strings.
        #expect(tools[1].diff == "@@ -3,1 +3,1 @@\n-let x = a\n+let x = b")
        #expect(tools[1].paths == [FileTouch(path: "/repo/Sources/Board.swift", how: .edit)])
        #expect(tools[2].diff == "+one\n+two")
        #expect(tools[2].paths == [FileTouch(path: "/repo/NOTES.md", how: .write)])
        #expect(tools[3].paths == [FileTouch(path: "/repo/README.md", how: .read)])
        #expect(tools[4].text == "Write tests\n\nTest the board.")
        #expect(tools[5].text == #"{"a":"/p/q","b":1}"#)

        let failed = chat.events.filter { $0.kind == .result && $0.failed }
        #expect(failed.map(\.callID) == ["t5"])
    }

    @Test func anEditWithoutAPatchShowsWhatItReplaced() {
        let event = ClaudeTranscript.Reader.toolCall(name: "Edit", input: ["file_path": "/a", "old_string": "x\ny", "new_string": "z"])
        #expect(event.diff == "-x\n-y\n+z")
        let inserted = ClaudeTranscript.Reader.toolCall(name: "Edit", input: ["file_path": "/a", "old_string": "", "new_string": "z"])
        #expect(inserted.diff == "+z")
        let many = ClaudeTranscript.Reader.toolCall(name: "MultiEdit", input: ["file_path": "/a", "edits": [
            ["old_string": "1", "new_string": "2"], ["old_string": "3", "new_string": ""],
        ]])
        #expect(many.diff == "-1\n+2\n-3")
    }

    @Test func longToolOutputKeepsBothEnds() throws {
        let scratch = try Scratch()
        let output = "START" + String(repeating: "x", count: 50_000) + "END"
        let lines = [user("go", uuid: "u1", at: "2026-11-10T10:00:00Z"),
                     results([["type": "tool_result", "tool_use_id": "t1", "content": output]], uuid: "r1", at: "2026-11-10T10:00:01Z")]
        let chat = try ClaudeTranscript.read(path: try scratch.write(lines.joined(separator: "\n"), to: "p/s.jsonl"))
        let text = try #require(chat.events.last?.text)
        #expect(text.hasPrefix("START") && text.hasSuffix("END"))
        #expect(text.count == ClaudeTranscript.resultLimit + 3)
    }

    @Test func findsTranscriptsByIdAndListsThem() throws {
        let scratch = try Scratch()
        try scratch.write("{}", to: ".claude/projects/-a/abc123.jsonl")
        try scratch.write("{}\n{}", to: ".claude/projects/-b/def456.jsonl")
        try scratch.write("x", to: ".claude/projects/-b/notes.txt")
        #expect(ClaudeTranscript.find(sessionID: "def456", home: scratch.path) == scratch.path + "/.claude/projects/-b/def456.jsonl")
        #expect(ClaudeTranscript.find(sessionID: "nope00", home: scratch.path) == nil)
        // An id is never a path.
        #expect(ClaudeTranscript.find(sessionID: "../-a/abc123", home: scratch.path) == nil)
        let all = ClaudeTranscript.all(home: scratch.path)
        #expect(all.map(\.sessionID) == ["abc123", "def456"])
        #expect(all.map(\.size) == [2, 5])
    }

    @Test func aMissingTranscriptIsAnError() {
        #expect(throws: HistoryError.self) { try ClaudeTranscript.read(path: "/nonexistent/s.jsonl") }
    }

    @Test(arguments: ["<task-notification>x", "\n  <ci-monitor-event>", "This session is being continued from",
                      "[Request interrupted by user]", "The app was quit while you were working. Please continue"])
    func knowsHarnessTextFromTyping(_ text: String) {
        #expect(ClaudeTranscript.isInjected(text))
        #expect(!ClaudeTranscript.isInjected("Please continue with the <task-notification> work"))
    }
}

@Suite struct PathFinderTests {
    private let finder = PathFinder(roots: ["/repo", "/repo/.claude/worktrees/w1"], home: "/Users/pat",
                                    known: ["Sources/Board.swift", "Sources/Deep/Card.swift", "Tests/BoardTests.swift",
                                            "README.md", "a/Card.swift"])

    @Test(arguments: [
        ("/repo/Sources/Board.swift", nil, "Sources/Board.swift"),
        ("Sources/Board.swift", "/repo", "Sources/Board.swift"),
        ("Board.swift", "/repo/Sources", "Sources/Board.swift"),
        ("../README.md", "/repo/Sources", "README.md"),
        // Another worktree of the same repository names the same file.
        ("/repo/.claude/worktrees/w1/Sources/Board.swift", nil, "Sources/Board.swift"),
        // So does a checkout that is gone, or a sibling clone: the tracked tail wins.
        ("/Users/pat/old-clone/Sources/Board.swift", nil, "Sources/Board.swift"),
        ("~/notes/todo.md", nil, "~/notes/todo.md"),
        ("/Users/pat/notes/todo.md", nil, "~/notes/todo.md"),
        ("/etc/hosts", nil, "/etc/hosts"),
        // Worked out from the text alone, so a file that no longer exists is named the same way.
        ("/repo/./Sources//Deleted/../Gone.swift", nil, "Sources/Gone.swift"),
        ("/private/tmp/x/Sources/Board.swift", nil, "Sources/Board.swift"),
        ("/private/var/data.bin", nil, "/var/data.bin"),
    ] as [(String, String?, String)])
    func namesEachFileOneWay(_ path: String, _ folder: String?, _ expected: String) {
        #expect(finder.relative(path, from: folder) == expected)
    }

    @Test func findsFilesNamedInACommand() {
        let command = "cd /repo && sed -i '' 's/a/b/' Sources/Board.swift && swift test --filter BoardTests 2>&1 | tail -5; cat ./README.md:12"
        #expect(finder.paths(in: command, from: "/repo") == ["Sources/Board.swift", "README.md"])
    }

    @Test func findsFilesNamedInProse() {
        let text = "I changed `Sources/Board.swift` and BoardTests.swift. See a/Sources/Deep/Card.swift, not Card.swift or version 1.2.3."
        // A bare name counts only when one tracked file has it: Card.swift has two.
        #expect(finder.paths(in: text, from: "/repo") == ["Sources/Board.swift", "Tests/BoardTests.swift", "Sources/Deep/Card.swift"])
    }

    @Test func withoutARepositoryTakesOnlyWhatLooksLikeAFile() {
        let bare = PathFinder(roots: [], home: "/Users/pat", known: [])
        #expect(bare.paths(in: "edit src/app/main.py then run make and see README.md v1.2", from: "/work") == ["/work/src/app/main.py"])
    }

    @Test(arguments: [
        ("sed -i '' 's/a/b/' f.swift", true), ("python3 - <<'EOF'\nopen(p,'w').write(s)\nEOF", true),
        ("cat > f.swift <<'EOF'\nx\nEOF", true), ("echo hi >> log.txt", true), ("git apply fix.patch", true),
        ("rm -rf build", true), ("mv a b", true), ("perl -pi -e 's/a/b/' f", true), ("git checkout -- f.swift", true),
        ("swift build 2>&1 | tail -5", false), ("grep -n 'func x() -> Int' f.swift", false),
        ("cat f.swift > /dev/null", false), ("ls -la; git status", false), ("git log --oneline | head", false),
        ("swift test 2>/dev/null", false), ("echo a=>b", false), ("diff <(a) <(b)", false),
    ] as [(String, Bool)])
    func tellsWritingCommandsFromReadingOnes(_ command: String, _ writes: Bool) {
        #expect(PathFinder.writes(command) == writes, "\(command)")
    }

    @Test(arguments: [
        ("git commit -qam 'x'", true), ("git add -A && git commit -q -F - <<'EOF'\nmsg\nEOF", true),
        ("git -C /repo commit -m x", true), ("git merge origin/main", true), ("git cherry-pick abc", true),
        ("git log --grep commit", false), ("echo git commit", true), ("git status", false), ("gh pr merge 3", false),
        ("git pull --no-rebase origin main", true),
    ] as [(String, Bool)])
    func tellsCommandsThatMayCommit(_ command: String, _ commits: Bool) {
        #expect(PathFinder.commits(command) == commits, "\(command)")
    }

    @Test func tellsCommandsThatMerge() {
        #expect(PathFinder.merges("git fetch -q && git merge -q origin/main"))
        #expect(PathFinder.merges("git -C /repo pull"))
        #expect(!PathFinder.merges("git commit -m 'merge the lists'"))
        #expect(!PathFinder.merges("gh pr merge 3"))
    }
}
