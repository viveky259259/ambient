@testable import AmbientCore
import AmbientHistory
import Foundation
import Testing
@testable import ambient

/// A repository, a home folder with one Claude transcript about it, and a folder to keep chats in.
private final class World {
    let base: URL
    let repo: String
    let home: URL
    let store: String
    let transcript: String
    let fix: String

    init() throws {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-cli-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        guard let real = realpath(made.path, nil) else { throw HistoryError.message("no real path") }
        defer { free(real) }
        base = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        repo = base.appendingPathComponent("widgets").path
        home = base.appendingPathComponent("home")
        store = base.appendingPathComponent("store").path
        for folder in [repo + "/Sources", home.path + "/.claude/projects/-w", store] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        let repo = repo
        func git(_ arguments: String...) throws -> String {
            let output = Shell.system("git", arguments, in: repo)
            guard output.succeeded else { throw HistoryError.message("git \(arguments): \(output.stderr)") }
            return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git("init", "-q", "-b", "main")
        _ = try git("config", "user.name", "Test Dev")
        _ = try git("config", "user.email", "dev@example.com")
        _ = try git("config", "commit.gpgsign", "false")
        _ = try git("remote", "add", "origin", "https://github.com/acme/widgets.git")
        try Data("let keep = all\n".utf8).write(to: URL(fileURLWithPath: repo + "/Sources/Board.swift"))
        _ = try git("add", "-A")
        let old = "@\(Int(Date().timeIntervalSince1970) - 86_400) +0000"
        _ = Shell.system("env", ["GIT_COMMITTER_DATE=\(old)", "GIT_AUTHOR_DATE=\(old)", "git", "commit", "-qm", "feat: the board"], in: repo)

        // The chat edits the board and commits, a moment ago.
        let started = Date().addingTimeInterval(-20)
        try Data("let keep = all.filter { !$0.expired }\n".utf8).write(to: URL(fileURLWithPath: repo + "/Sources/Board.swift"))
        let committing = Date()
        _ = try git("commit", "-qam", "fix(board): expire finished tasks")
        fix = try git("rev-parse", "HEAD")
        let committed = Date()

        let stamps = ISO8601DateFormatter()
        stamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func line(_ object: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]), as: UTF8.self)
        }
        let lines = [
            line(["type": "custom-title", "customTitle": "Board cleanup"]),
            line(["type": "user", "uuid": "u1", "timestamp": stamps.string(from: started), "cwd": repo, "origin": ["kind": "human"],
                  "message": ["role": "user", "content": "The board is slow. Fix it."]]),
            line(["type": "assistant", "uuid": "a1", "timestamp": stamps.string(from: started.addingTimeInterval(1)),
                  "message": ["role": "assistant", "content": [
                      ["type": "tool_use", "id": "t1", "name": "Edit",
                       "input": ["file_path": repo + "/Sources/Board.swift", "old_string": "all", "new_string": "all.filter { !$0.expired }"]],
                  ]]]),
            line(["type": "assistant", "uuid": "a2", "timestamp": stamps.string(from: committing),
                  "message": ["role": "assistant", "content": [
                      ["type": "tool_use", "id": "t2", "name": "Bash", "input": ["command": "git commit -qam 'fix(board): expire finished tasks'"]],
                  ]]]),
            line(["type": "user", "uuid": "r2", "timestamp": stamps.string(from: committed),
                  "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t2", "content": ""]]]]),
            line(["type": "assistant", "uuid": "a3", "timestamp": stamps.string(from: committed.addingTimeInterval(1)),
                  "message": ["role": "assistant", "content": [["type": "text", "text": "Finished tasks now expire, so the board stays small.\n\nDetails follow."]]]]),
        ]
        transcript = home.path + "/.claude/projects/-w/sess-0001.jsonl"
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: transcript))
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    var paths: AmbientPaths { AmbientPaths(userHome: home, home: home.appendingPathComponent(".ambient")) }

    var command: HistoryCommand {
        var command = HistoryCommand(paths: paths)
        command.folder = repo
        command.findModel = { _ in nil }
        return command
    }
}

@Suite struct HistoryArgumentTests {
    @Test func sortsFlagsValuesAndTheRest() throws {
        let parsed = try HistoryCommand.Arguments(["why", "--file", "a.swift", "--deep", "is", "it", "--json"], valued: ["--file"])
        #expect(parsed.values == ["--file": "a.swift"])
        #expect(parsed.flags == ["--deep", "--json"])
        #expect(parsed.rest == ["why", "is", "it"])
        #expect(throws: HistoryError.self) { try HistoryCommand.Arguments(["--file"], valued: ["--file"]) }
    }

    @Test func aChatsLocalCopyNeverLeavesItsFolder() {
        let session = ChatSession(id: "../../../etc/x y", agent: "cl:aude", repo: "a/b", startedAt: Date(), endedAt: Date())
        let name = HistoryCommand.fileName(for: IndexedSession(key: "cl:aude:../../../etc/x y", session: session, url: nil, folder: "f/"))
        #expect(name.hasPrefix("cl-aude-") && name.hasSuffix("-etc-x-y"))
        #expect(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }

    @Test func readsAFileWithOrWithoutALine() throws {
        let world = try World()
        let command = world.command
        let context = command.context()
        #expect(context.repo == "acme/widgets" && context.root == world.repo)
        #expect(command.fileArgument("Sources/Board.swift:12", in: context) == ("Sources/Board.swift", 12))
        #expect(command.fileArgument(world.repo + "/Sources/Board.swift", in: context) == ("Sources/Board.swift", nil))
        #expect(command.fileArgument("Sources/Board.swift:0", in: context).line == nil)
        #expect(command.fileArgument("weird:name.swift", in: context) == ("weird:name.swift", nil))
    }
}

@Suite struct HistoryCommandTests {
    @Test func nothingWorksUntilARepositoryIsSetUp() throws {
        let world = try World()
        let command = world.command
        #expect(command.run(["why", "Sources/Board.swift"]) == 1)
        #expect(command.run(["sync"]) == 1)
        #expect(command.run(["nonsense"]) == 64)
        #expect(command.run([]) == 0)
        // Capturing with nothing set up is quiet success: the app calls it for every chat that ends.
        #expect(command.run(["capture", "--transcript", world.transcript, "--quiet"]) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.store).isEmpty)
        #expect(command.run(["setup"]) == 1)
        #expect(command.run(["setup", "--store", "s3:/typo"]) == 1)
        // A repository is named by its remote, never by a bare folder name that another folder could share.
        #expect(command.run(["setup", "--store", world.store, "--repo", "widgets"]) == 1)
        var elsewhere = command
        elsewhere.folder = world.base.path
        #expect(elsewhere.run(["setup", "--store", world.store]) == 1)
        #expect(!FileManager.default.fileExists(atPath: world.paths.historyConfig.path))
    }

    @Test func setsUpCapturesAndAnswers() throws {
        let world = try World()
        let command = world.command
        let before = Date()
        #expect(command.run(["setup", "--store", world.store]) == 0)
        let config = HistoryConfig.load(from: world.paths.historyConfig)
        let entry = try #require(config.repos["acme/widgets"])
        // The same folder, however the system spells its path.
        #expect(URL(fileURLWithPath: entry.store).resolvingSymlinksInPath() == URL(fileURLWithPath: world.store).resolvingSymlinksInPath())
        #expect(entry.postLinks == false)
        #expect(try #require(entry.since) >= before.addingTimeInterval(-1))
        // Setting up again keeps the day it was first set up.
        #expect(command.run(["setup", "--store", world.store]) == 0)
        #expect(HistoryConfig.load(from: world.paths.historyConfig).repos["acme/widgets"]?.since == entry.since)

        #expect(command.run(["capture", "--session", "claude:sess-0001"]) == 0)
        #expect(command.run(["capture", "--session", "codex:whatever"]) == 0)
        #expect(command.run(["capture", "--session", "missing0"]) == 1)
        #expect(command.run(["capture"]) == 1)
        #expect(command.run(["capture", "--due", "--since", "soon"]) == 1)
        #expect(command.run(["sync"]) == 0)
        #expect(command.run(["status"]) == 0)

        let context = command.context()
        let (report, note) = try command.whyReport("Sources/Board.swift:1", in: context, sync: true)
        #expect(note == nil)
        #expect(report.changes.count == 1 && report.unexplained.count == 1)
        #expect(report.changes[0].commits.map(\.sha) == [world.fix] && report.changes[0].blamed)
        let text = HistoryCommand.text(report, all: false, terminal: Terminal())
        #expect(text.contains("Sources/Board.swift:1"))
        #expect(text.contains("1 recorded change · 1 commit with no recorded chat"))
        #expect(text.contains("Line 1 was last changed by \(world.fix.prefix(7)) (fix(board): expire finished tasks), marked ◆ below."))
        #expect(text.contains("◆ ") && text.contains("claude · Test Dev · \"Board cleanup\""))
        #expect(text.contains("Asked     The board is slow. Fix it."))
        // A card taken from the chat's own words shows only the opening of what the agent said.
        #expect(text.contains("Did       Finished tasks now expire, so the board stays small.") && !text.contains("Details follow."))
        #expect(text.contains("Commit    \(world.fix.prefix(7)) fix(board): expire finished tasks"))
        #expect(text.contains("Chat      ambient history show sess-000 1-5"))
        #expect(text.contains("Commits with no recorded chat") && text.contains("feat: the board"))

        let json = HistoryCommand.json(report)
        #expect(json["path"] as? String == "Sources/Board.swift" && json["line"] as? Int == 1)
        #expect((json["changes"] as? [[String: Any]])?.first?["session"] as? String == "sess-0001")
        #expect(JSONSerialization.isValidJSONObject(json))

        let (answer, _) = try command.answer("why do finished tasks expire from the board?", files: [], deep: false,
                                             useModel: true, sync: false, in: context)
        #expect(answer.depth == .cards && answer.sources.count == 1)
        #expect(answer.text.contains("Finished tasks now expire"))

        let all = try command.transcript("sess", range: nil, in: context)
        #expect(all.contains("[1] USER: The board is slow. Fix it.") && all.contains("[3] TOOL Bash: git commit"))
        #expect(try command.transcript("sess-0001", range: 2...2, in: context).hasPrefix("[2] TOOL Edit: Sources/Board.swift"))
        #expect(throws: HistoryError.self) { try command.transcript("nope", range: nil, in: context) }
        #expect(command.run(["show", "sess", "5-2"]) == 1)
        #expect(command.run(["show", "sess", "1-2"]) == 0)
        #expect(command.run(["why", "Sources/Board.swift", "--json", "--no-sync"]) == 0)
        #expect(command.run(["ask", "why", "do", "tasks", "expire", "--no-model"]) == 0)
        #expect(command.run(["ask"]) == 1)
    }

    @Test func aCaptureTheAppStartedNeverAsksTheKeychain() throws {
        final class Asked: @unchecked Sendable { var values: [Bool] = [] }
        let asked = Asked()
        let world = try World()
        var command = world.command
        command.findModel = { asking in
            asked.values.append(asking)
            return nil
        }
        #expect(command.run(["setup", "--store", world.store]) == 0)
        // Setting up never looks for the key at all: it must not stop on a permission dialog.
        #expect(asked.values.isEmpty)
        #expect(command.run(["capture", "--transcript", world.transcript, "--quiet"]) == 0)
        #expect(command.run(["capture", "--transcript", world.transcript]) == 0)
        #expect(command.run(["capture", "--transcript", world.transcript, "--no-model"]) == 0)
        #expect(asked.values == [false, true])
    }

    @Test func opensAPageMadeHereNotTheOneInTheStore() throws {
        final class Opened: @unchecked Sendable { var files: [String] = [] }
        let opened = Opened()
        let world = try World()
        var command = world.command
        command.shell = Shell { tool, arguments, folder, input in
            if tool == "open" {
                opened.files += arguments
                return Shell.Output(status: 0)
            }
            return Shell.system(tool, arguments, in: folder, input: input)
        }
        #expect(command.run(["setup", "--store", world.store]) == 0)
        #expect(command.run(["capture", "--transcript", world.transcript, "--no-model"]) == 0)
        // Someone with access to the store swaps the page for one that runs a script.
        let stored = try FolderStore(root: world.store).list(prefix: "").first { $0.key.hasSuffix("page.html") }
        let key = try #require(stored?.key)
        try FolderStore(root: world.store).put(Data("<script>alert('from the store')</script>".utf8), key: key, contentType: "text/html")
        #expect(command.run(["open", "sess"]) == 0)
        let file = try #require(opened.files.first)
        let page = try String(contentsOfFile: file, encoding: .utf8)
        #expect(page.contains("The board is slow. Fix it.") && !page.contains("from the store"))
        #expect(file.hasPrefix(world.paths.historyHome.path))
    }

    @Test func answersFromTheLastSyncWhenTheStoreIsAway() throws {
        let world = try World()
        let command = world.command
        #expect(command.run(["setup", "--store", world.store]) == 0)
        #expect(command.run(["capture", "--transcript", world.transcript, "--no-model"]) == 0)
        try FileManager.default.removeItem(atPath: world.store)
        try Data("not a folder".utf8).write(to: URL(fileURLWithPath: world.store))
        let context = command.context()
        // The index already has the chat, so the question is still answered.
        let (report, _) = try command.whyReport("Sources/Board.swift", in: context, sync: true)
        #expect(report.changes.count == 1)
    }

    @Test func scoresAQuestionsFile() throws {
        let world = try World()
        let command = world.command
        #expect(command.run(["setup", "--store", world.store]) == 0)
        #expect(command.run(["capture", "--transcript", world.transcript, "--no-model"]) == 0)
        let good = world.base.appendingPathComponent("good.json").path
        try Data(#"{"questions":[{"ask":"why do finished tasks expire?","expectSession":"sess-0001","expectFiles":["Sources/Board.swift"]}]}"#.utf8)
            .write(to: URL(fileURLWithPath: good))
        #expect(command.run(["eval", good]) == 0)
        let bad = world.base.appendingPathComponent("bad.json").path
        try Data(#"{"questions":[{"ask":"why do finished tasks expire?","expectSession":"someone-else"}]}"#.utf8)
            .write(to: URL(fileURLWithPath: bad))
        #expect(command.run(["eval", bad]) == 1)
        #expect(command.run(["eval", "/nonexistent.json"]) == 1)
        // Scoring answers needs a model, and there is none here.
        #expect(command.run(["eval", good, "--answers"]) == 1)
    }
}

@Suite struct HistoryMCPTests {
    private func server(_ world: World) -> MCPServer {
        let request: (WireMessage) -> WireMessage? = { _ in nil }
        return MCPServer(request: request, memory: MemoryClient(paths: world.paths, request: request))
    }

    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any]) throws -> (text: String, isError: Bool) {
        let message: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
        let reply = try #require(server.handle(line))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        let content = try #require((result["content"] as? [[String: Any]])?.first)
        return (try #require(content["text"] as? String), try #require(result["isError"] as? Bool))
    }

    @Test func listsTheHistoryToolsAsReadOnly() {
        let tools = MCPServer.tools.filter { ($0["name"] as? String)?.hasPrefix("history_") == true }
        #expect(tools.compactMap { $0["name"] as? String } == ["history_why", "history_search", "history_read"])
        for tool in tools {
            #expect((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true)
            #expect((tool["inputSchema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
        }
    }

    @Test func answersAnAgentsQuestionsAboutAFile() throws {
        let world = try World()
        let server = server(world)
        let unset = try call(server, "history_why", ["path": "Sources/Board.swift", "project": world.repo])
        #expect(unset.isError && unset.text.contains("History isn't set up for acme/widgets"))

        #expect(world.command.run(["setup", "--store", world.store]) == 0)
        #expect(world.command.run(["capture", "--transcript", world.transcript, "--no-model"]) == 0)

        let why = try call(server, "history_why", ["path": "Sources/Board.swift", "line": 1, "project": world.repo])
        #expect(!why.isError)
        #expect(why.text.contains("Asked     The board is slow. Fix it.") && why.text.contains("fix(board): expire finished tasks"))
        // No colour codes in what an agent reads.
        #expect(!why.text.contains("\u{1B}["))

        let search = try call(server, "history_search", ["query": "finished tasks expire board", "project": world.repo])
        #expect(!search.isError && search.text.contains("<card id=\"C1\">") && search.text.contains("ambient history show sess-000 1-5"))
        let nothing = try call(server, "history_search", ["query": "zzzz qqqq", "project": world.repo])
        #expect(!nothing.isError && nothing.text == "No recorded chat is about that.")

        let read = try call(server, "history_read", ["session": "sess-0001", "from": 2, "to": 3, "project": world.repo])
        #expect(!read.isError && read.text.hasPrefix("[2] TOOL Edit: Sources/Board.swift") && read.text.contains("[3] TOOL Bash"))
        #expect(try call(server, "history_read", ["session": "sess-0001", "from": 3, "to": 2, "project": world.repo]).isError)
        // One bound alone still narrows it.
        let tail = try call(server, "history_read", ["session": "sess-0001", "from": 4, "project": world.repo])
        #expect(tail.text.hasPrefix("[4] RESULT") && !tail.text.contains("[1] USER"))
        let head = try call(server, "history_read", ["session": "sess-0001", "to": 1, "project": world.repo])
        #expect(head.text.hasPrefix("[1] USER") && !head.text.contains("[2] TOOL"))
        #expect(try call(server, "history_read", ["session": "nope", "project": world.repo]).isError)
        #expect(try call(server, "history_why", ["project": world.repo]).text == "path is required.")
        #expect(try call(server, "history_search", ["project": world.repo]).text == "query is required.")
    }
}
