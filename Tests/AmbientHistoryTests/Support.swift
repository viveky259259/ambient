import Foundation
import Testing
@testable import AmbientHistory

/// Golden files for the two formats history stores (`docs/superpowers/specs/2026-11-13-modular-packages-design.md`,
/// rule 4). A released fixture is never edited: a format change adds a new one (`.v2`) and the old one must still
/// decode. `AMBIENT_RECORD_FIXTURES=1` writes fixtures that are missing, and never overwrites one.
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// Checks `value` encodes to the fixture's JSON, and that the fixture decodes back to `value`.
    static func roundTrip<T: Codable & Equatable>(_ name: String, _ value: T,
                                                  sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = directory.appendingPathComponent(name)
        let written = try HistoryCoding.encode(value)
        if ProcessInfo.processInfo.environment["AMBIENT_RECORD_FIXTURES"] == "1", !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try canonical(written, pretty: true).write(to: url)
        }
        let fixture = try Data(contentsOf: url)
        #expect(try canonical(fixture) == canonical(written), "\(name) no longer matches what the code writes",
                sourceLocation: sourceLocation)
        #expect(try HistoryCoding.decode(T.self, from: fixture) == value, "\(name) decodes to something else",
                sourceLocation: sourceLocation)
    }

    static func canonical(_ data: Data, pretty: Bool = false) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }
}

/// A folder that is removed when the test is done with it.
final class Scratch {
    let url: URL
    var path: String { url.path }

    init() throws {
        let made = FileManager.default.temporaryDirectory
            .appendingPathComponent("ambient-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        // The real path, so it compares equal to the one git reports: /private/var, not /var. Foundation's own
        // symlink resolving takes /private back off.
        guard let real = realpath(made.path, nil) else { throw HistoryError.message("no real path for \(made.path)") }
        defer { free(real) }
        url = URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ text: String, to relative: String) throws -> String {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file.path
    }
}

/// A real git repository in a scratch folder: git is the thing being asked, so nothing stands in for it.
struct Repo {
    let scratch: Scratch
    var root: String { scratch.path }

    init(remote: String? = "git@github.com:acme/widgets.git") throws {
        scratch = try Scratch()
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "Test Dev")
        try git("config", "user.email", "dev@example.com")
        try git("config", "commit.gpgsign", "false")
        if let remote { try git("remote", "add", "origin", remote) }
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let output = Shell.system("git", arguments, in: root)
        guard output.succeeded else { throw HistoryError.message("git \(arguments.joined(separator: " ")): \(output.stderr)") }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes a file and commits it, returning the commit's full hash. `at` backdates the commit, for history that
    /// was there before a chat began.
    @discardableResult
    func commit(_ path: String, _ text: String, message: String, at: Date? = nil) throws -> String {
        try scratch.write(text, to: path)
        try git("add", "--", path)
        if let at {
            let stamp = "@\(Int(at.timeIntervalSince1970)) +0000"
            let output = Shell.system("env", ["GIT_COMMITTER_DATE=\(stamp)", "GIT_AUTHOR_DATE=\(stamp)", "git", "commit", "-q", "-m", message], in: root)
            guard output.succeeded else { throw HistoryError.message("git commit: \(output.stderr)") }
        } else {
            try git("commit", "-q", "-m", message)
        }
        return try git("rev-parse", "HEAD")
    }
}

/// Stands in for `aws` and `gh`: answers by the first matching rule and keeps every call.
final class FakeShell: @unchecked Sendable {
    struct Call: Equatable {
        var tool: String
        var arguments: [String]
        var input: String?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var rules: [(matches: (Call) -> Bool, output: Shell.Output)] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func when(_ tool: String, containing words: String..., reply stdout: String = "", status: Int32 = 0, stderr: String = "") {
        rules.append(({ call in call.tool == tool && words.allSatisfy { word in call.arguments.contains { $0.contains(word) } } },
                      Shell.Output(status: status, stdout: stdout, stderr: stderr)))
    }

    var shell: Shell {
        Shell { tool, arguments, _, input in
            let call = Call(tool: tool, arguments: arguments, input: input.map { String(decoding: $0, as: UTF8.self) })
            self.lock.lock()
            self.recorded.append(call)
            self.lock.unlock()
            return self.rules.first { $0.matches(call) }?.output ?? Shell.Output(status: 1, stderr: "unexpected: \(tool) \(arguments)")
        }
    }
}

/// A model that answers from a list, in order, and keeps what it was asked.
final class FakeModel: TextModel, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<String, HistoryError>]
    private var asked: [ModelRequest] = []
    /// Used once the list runs out.
    var fallback: String

    init(_ replies: [String] = [], fallback: String = "{}") {
        self.replies = replies.map { .success($0) }
        self.fallback = fallback
    }

    func fail(_ message: String) {
        lock.lock()
        replies.append(.failure(.message(message)))
        lock.unlock()
    }

    var requests: [ModelRequest] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func answer(_ request: ModelRequest) throws -> String {
        lock.lock()
        asked.append(request)
        let next = replies.isEmpty ? nil : replies.removeFirst()
        lock.unlock()
        return try next?.get() ?? fallback
    }
}

enum Sample {
    static let start = Date(timeIntervalSince1970: 1_795_000_000)

    static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    static let session = ChatSession(id: "11111111-2222-3333-4444-555555555555", agent: "claude", repo: "acme/widgets",
                                     branch: "feat/board", developer: "Test Dev", title: "Board cleanup",
                                     startedAt: at(0), endedAt: at(900))

    /// Two requests: the first edits a file and commits it, the second only asks a question.
    static let record = ChatRecord(
        session: session,
        commits: [ChatCommit(sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", subject: "fix(board): expire finished tasks",
                             at: at(300), files: ["Sources/Board.swift"], event: 6)],
        uncommitted: nil,
        events: [
            ChatEvent(n: 1, at: at(0), kind: .user, text: "The board is slow. Fix it.",
                      touches: nil),
            ChatEvent(n: 2, at: at(5), kind: .agent, text: "Finished tasks never leave the board, so every event re-sorts thousands."),
            ChatEvent(n: 3, at: at(10), kind: .tool, text: "Sources/Board.swift", tool: "Read",
                      touches: [FileTouch(path: "Sources/Board.swift", how: .read)]),
            ChatEvent(n: 4, at: at(20), kind: .tool, text: "Sources/Board.swift", tool: "Edit",
                      diff: "@@ -1,1 +1,2 @@\n-let keep = all\n+let keep = all.filter { !$0.expired }\n+// Finished tasks expire after three days.",
                      touches: [FileTouch(path: "Sources/Board.swift", how: .edit)]),
            ChatEvent(n: 5, at: at(21), kind: .result, text: "The file was updated.", of: 4),
            ChatEvent(n: 6, at: at(299), kind: .tool, text: "git commit -qam 'fix(board): expire finished tasks'", tool: "Bash",
                      label: "Commit the fix"),
            ChatEvent(n: 7, at: at(301), kind: .result, text: "", of: 6),
            ChatEvent(n: 8, at: at(310), kind: .agent, text: "Finished tasks now expire after three days. All 12 tests pass."),
            ChatEvent(n: 9, at: at(600), kind: .user, text: "Why three days and not one?"),
            ChatEvent(n: 10, at: at(610), kind: .agent, text: "A weekend: a task finished on Friday should still be there on Monday."),
        ])

    static func cardFile(url: String? = nil) -> CardFile {
        let episodes = Episodes.split(record)
        return CardFile(session: session, url: url, commits: record.commits,
                        touches: Episodes.touches(in: record, episodes: episodes),
                        cards: episodes.map { Episodes.card(for: $0, in: record) })
    }
}
