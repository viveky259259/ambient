import AmbientBase
import Foundation
import Testing
@testable import AmbientHistory

/// A second chat, later than `Sample`'s, that changes the same file with a script and never commits.
private func laterFile() -> CardFile {
    let session = ChatSession(id: "99999999-aaaa-bbbb-cccc-dddddddddddd", agent: "claude", repo: "acme/widgets",
                              developer: "Other Dev", title: "Remote open", startedAt: Sample.at(5_000), endedAt: Sample.at(6_000))
    let card = ChangeCard(episode: 1, firstEvent: 1, lastEvent: 20, at: Sample.at(5_000),
                          request: "Clicking a card from another Mac should open its chat there.",
                          summary: "RemoteOpen runs ambient open over ssh; TaskStore remembers each task's last chat.",
                          why: "A task forgot its chat once the session ended.", files: ["Sources/Board.swift", "Sources/RemoteOpen.swift"],
                          landed: .uncommitted, evidence: [7], source: "claude-haiku-5-5")
    return CardFile(session: session, url: "https://example.com/later", commits: [],
                    touches: [PlacedTouch(path: "Sources/Board.swift", how: .shell, episode: 1, event: 7),
                              PlacedTouch(path: "Sources/RemoteOpen.swift", how: .write, episode: 1, event: 9),
                              PlacedTouch(path: "README.md", how: .read, episode: 1, event: 2)],
                    cards: [card])
}

private func index(with files: [CardFile] = [Sample.cardFile(), laterFile()]) throws -> HistoryIndex {
    let index = try HistoryIndex(path: ":memory:")
    for file in files { try index.upsert(file, folder: HistoryKeys.folder(for: file.session), revision: "r1") }
    return index
}

@Suite struct IndexTests {
    @Test func findsRequestsByFileNewestFirst() throws {
        let index = try index()
        let hits = try index.requests(touching: ["Sources/Board.swift"], changesOnly: true)
        #expect(hits.map(\.chat.session.title) == ["Remote open", "Board cleanup"])
        #expect(hits.map(\.how) == [.shell, .edit])
        #expect(hits.map(\.event) == [7, 4])
        #expect(hits[1].card == Sample.cardFile().cards[0])
        #expect(hits[0].chat.url == "https://example.com/later")
        #expect(hits[0].chat.key == "claude:99999999-aaaa-bbbb-cccc-dddddddddddd")

        #expect(try index.requests(touching: ["README.md"], changesOnly: true).isEmpty)
        #expect(try index.requests(touching: ["README.md"], changesOnly: false).map(\.how) == [.read])
        #expect(try index.requests(touching: [], changesOnly: false).isEmpty)
        #expect(try index.requests(touching: ["Sources/RemoteOpen.swift", "Sources/Board.swift"], changesOnly: true).count == 2)
        #expect(try index.knownPaths() == ["Sources/Board.swift", "Sources/RemoteOpen.swift", "README.md"])
    }

    @Test func findsTheChatAndRequestThatMadeACommit() throws {
        let index = try index()
        #expect(try index.sessions(makingCommit: "aaaaaaa") == ["claude:11111111-2222-3333-4444-555555555555"])
        #expect(try index.sessions(makingCommit: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA").count == 1)
        #expect(try index.sessions(makingCommit: "bbbbbbb").isEmpty)
        // Too short, or not a hash at all: never a wildcard.
        #expect(try index.sessions(makingCommit: "aaa").isEmpty)
        #expect(try index.sessions(makingCommit: "%%%%%%%").isEmpty)
        #expect(try index.requests(makingCommit: "aaaaaaaa").map(\.card.episode) == [1])
    }

    @Test func searchesByWordsAndByPartsOfNames() throws {
        let index = try index()
        #expect(try index.search("why do finished tasks expire?").first?.chat.session.title == "Board cleanup")
        #expect(try index.search("opening a chat on another Mac over ssh").first?.chat.session.title == "Remote open")
        // "RemoteOpen.swift" is found by the words in its name.
        #expect(try index.search("remote open").first?.chat.session.title == "Remote open")
        #expect(try index.search("why is the the of?").isEmpty)
        #expect(try index.search("\"quotes\" AND (parens) *").isEmpty)
        #expect(HistoryIndex.match(for: "Why did TaskStore change?") == "\"taskstore\" OR \"change\"")
        #expect(HistoryIndex.camelParts("TaskStoreTests2") == "Task Store Tests2")
        #expect(HistoryIndex.camelParts("board") == "")
    }

    @Test func aChatCapturedAgainReplacesItself() throws {
        let index = try index()
        var again = Sample.cardFile()
        again.cards = [again.cards[0]]
        again.cards[0].summary = "Rewritten."
        again.touches = []
        try index.upsert(again, folder: HistoryKeys.folder(for: again.session), revision: "r2")
        #expect(try index.counts().chats == 2)
        #expect(try index.counts().cards == 2)
        #expect(try index.cards(inSession: "claude:11111111-2222-3333-4444-555555555555").map(\.card.summary) == ["Rewritten."])
        #expect(try index.requests(touching: ["Sources/Board.swift"], changesOnly: true).count == 1)
        #expect(try index.search("weekend").isEmpty)
        #expect(try index.revisions()[HistoryKeys.folder(for: again.session)]?.revision == "r2")

        try index.remove(sessionKey: "claude:11111111-2222-3333-4444-555555555555")
        #expect(try index.counts().chats == 1)
        #expect(try index.sessions(makingCommit: "aaaaaaa").isEmpty)
    }

    @Test func findsAChatByTheStartOfItsId() throws {
        let index = try index()
        #expect(try index.session(matching: "11111111")?.session.title == "Board cleanup")
        #expect(try index.session(matching: "claude:9999")?.session.title == "Remote open")
        #expect(try index.session(matching: "zzzz") == nil)
        // Two chats start with nothing in particular: neither is "the" one.
        #expect(try index.session(matching: "") == nil)
    }

    @Test func survivesBeingReopenedAndStartsOverAfterAFormatChange() throws {
        let scratch = try Scratch()
        let path = scratch.path + "/deep/index.sqlite"
        do {
            let index = try HistoryIndex(path: path)
            try index.upsert(Sample.cardFile(), folder: "f/", revision: "r1")
        }
        #expect(try HistoryIndex(path: path).counts().chats == 1)
        let raw = try SQLite(path: path)
        try raw.run("UPDATE meta SET value='0' WHERE key='schema'")
        #expect(try HistoryIndex(path: path).counts().chats == 0)
    }
}

@Suite struct SyncTests {
    @Test func bringsTheIndexInLineWithTheStore() throws {
        let scratch = try Scratch()
        let store = FolderStore(root: scratch.path)
        let index = try HistoryIndex(path: ":memory:")
        let first = Sample.cardFile(), second = laterFile()
        let firstKey = HistoryKeys.folder(for: first.session) + HistoryKeys.cards
        let secondKey = HistoryKeys.folder(for: second.session) + HistoryKeys.cards
        try store.put(try HistoryCoding.encode(first), key: firstKey, contentType: "application/json")
        try store.put(try HistoryCoding.encode(second), key: secondKey, contentType: "application/json")
        try store.put(Data("<html>".utf8), key: HistoryKeys.folder(for: first.session) + HistoryKeys.page, contentType: "text/html")
        try store.put(Data("{}".utf8), key: "other/repo/sessions/2026/01/01/claude-x/cards.json", contentType: "application/json")

        #expect(try HistorySync().sync(repo: "acme/widgets", store: store, index: index) == .init(added: 2, removed: 0, unreadable: 0))
        #expect(try index.counts().chats == 2)
        #expect(try HistorySync().sync(repo: "acme/widgets", store: store, index: index) == .init())

        // One captured again, one deleted from the store, one that this version can't read.
        var changed = first
        changed.cards[0].summary = "Changed upstream, and longer than before."
        try store.put(try HistoryCoding.encode(changed), key: firstKey, contentType: "application/json")
        try FileManager.default.removeItem(atPath: scratch.path + "/" + secondKey)
        try store.put(Data(#"{"version":99}"#.utf8), key: "acme/widgets/sessions/2027/01/01/claude-new/cards.json", contentType: "application/json")
        #expect(try HistorySync().sync(repo: "acme/widgets", store: store, index: index) == .init(added: 1, removed: 1, unreadable: 1))
        #expect(try index.cards(inSession: "claude:11111111-2222-3333-4444-555555555555").first?.card.summary.hasPrefix("Changed upstream") == true)
        #expect(try index.counts().chats == 1)
    }

    @Test func aStoreThatSuddenlyHasNothingRemovesNothing() throws {
        let scratch = try Scratch()
        let index = try index()
        // The folder is there but empty: an unmounted share looks like this.
        #expect(try HistorySync().sync(repo: "acme/widgets", store: FolderStore(root: scratch.path), index: index) == .init())
        #expect(try index.counts().chats == 2)
    }

    @Test func aStoreThatCantBeListedRemovesNothing() throws {
        let fake = FakeShell()
        fake.when("aws", containing: "list-objects-v2", status: 255, stderr: "Unable to locate credentials")
        let index = try index()
        #expect(throws: HistoryError.self) {
            try HistorySync().sync(repo: "acme/widgets", store: S3Store(bucket: "team-history", region: "us-east-1", shell: fake.shell), index: index)
        }
        #expect(try index.counts().chats == 2)
    }
}

@Suite struct PipelineTests {
    /// A home folder with one Claude transcript, for a chat that ran in `repo`.
    private func home(for repo: Repo, session: String = "sess-0001") throws -> (scratch: Scratch, transcript: String) {
        let scratch = try Scratch()
        func line(_ object: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]), as: UTF8.self)
        }
        let lines = [
            line(["type": "user", "uuid": "u1", "timestamp": "2026-11-18T10:00:00.000Z", "cwd": repo.root,
                  "message": ["role": "user", "content": "Make a.txt say two"], "origin": ["kind": "human"]]),
            line(["type": "assistant", "uuid": "a1", "timestamp": "2026-11-18T10:00:05.000Z",
                  "message": ["role": "assistant", "content": [
                      ["type": "tool_use", "id": "t1", "name": "Edit", "input": ["file_path": repo.root + "/a.txt", "old_string": "one", "new_string": "two"]],
                  ]]]),
            line(["type": "user", "uuid": "r1", "timestamp": "2026-11-18T10:00:06.000Z",
                  "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "ok"]]]]),
            line(["type": "assistant", "uuid": "a2", "timestamp": "2026-11-18T10:00:07.000Z",
                  "message": ["role": "assistant", "content": [["type": "text", "text": "a.txt now says two."]]]]),
        ]
        let path = try scratch.write(lines.joined(separator: "\n") + "\n", to: ".claude/projects/-work/\(session).jsonl")
        return (scratch, path)
    }

    private func pipeline(home: Scratch, store: String, now: Date = Date(), model: (any TextModel)? = nil,
                          since: Date? = nil, shell: Shell = .system) -> HistoryPipeline {
        var config = HistoryConfig()
        config.repos["acme/widgets"] = .init(store: store, postLinks: true, since: since)
        let paths = AmbientPaths(userHome: home.url, home: home.url.appendingPathComponent(".ambient"))
        return HistoryPipeline(paths: paths, config: config, shell: shell, model: model, now: { now })
    }

    @Test func storesAChatAndIndexesIt() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a", at: Date().addingTimeInterval(-86_400 * 30))
        try repo.scratch.write("two\n", to: "a.txt")
        let (home, transcript) = try home(for: repo)
        let storeFolder = try Scratch()
        let model = FakeModel(fallback: #"{"summary":"a.txt says two.","why":"Asked to.","rejected":"","verified":"","evidence":[2]}"#)
        let pipeline = pipeline(home: home, store: storeFolder.path, model: model)

        guard case let .stored(stored) = try pipeline.capture(transcript: transcript) else {
            Issue.record("the chat wasn't stored")
            return
        }
        #expect(stored.events == 4 && stored.cards.count == 1 && stored.commits == 0)
        #expect(stored.cards[0].why == "Asked to." && stored.cards[0].files == ["a.txt"] && stored.cards[0].landed == .uncommitted)
        #expect(stored.folder == "acme/widgets/sessions/2026/11/18/claude-sess-0001/")
        // A folder has no address worth leaving on a pull request, so nothing is posted.
        #expect(stored.pullRequests.isEmpty)

        let store = FolderStore(root: storeFolder.path)
        let record = try HistoryCoding.decode(ChatRecord.self, from: try #require(try store.get(stored.folder + "chat.json")))
        #expect(record.events.count == 4 && record.uncommitted?.contains("+two") == true)
        let cards = try HistoryCoding.decode(CardFile.self, from: try #require(try store.get(stored.folder + "cards.json")))
        #expect(cards.cards == stored.cards && cards.touches == [PlacedTouch(path: "a.txt", how: .edit, episode: 1, event: 2)])
        #expect(String(decoding: try #require(try store.get(stored.folder + "page.html")), as: UTF8.self).contains("a.txt now says two."))

        let index = try HistoryIndex(path: pipeline.paths.historyIndex(for: "acme/widgets").path)
        #expect(try index.requests(touching: ["a.txt"], changesOnly: true).count == 1)
        let ledger = CaptureLedger.load(from: pipeline.paths.historyLedger)
        #expect(ledger.captured["claude:sess-0001"]?.folder == stored.folder)
        // The next sync sees the same chat and has nothing to change but its revision.
        #expect(try HistorySync().sync(repo: "acme/widgets", store: store, index: index).added == 1)
        #expect(try HistorySync().sync(repo: "acme/widgets", store: store, index: index) == .init())
    }

    @Test func aDryRunWritesNothing() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: repo)
        let storeFolder = try Scratch()
        let pipeline = pipeline(home: home, store: storeFolder.path)
        guard case .stored = try pipeline.capture(transcript: transcript, dryRun: true) else {
            Issue.record("the dry run reported nothing")
            return
        }
        #expect(try FolderStore(root: storeFolder.path).list(prefix: "").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pipeline.paths.historyLedger.path))
    }

    @Test func leavesAloneWhatIsNotSetUp() throws {
        let other = try Repo(remote: "git@github.com:someone/private.git")
        try other.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: other)
        let storeFolder = try Scratch()
        let pipeline = pipeline(home: home, store: storeFolder.path)
        guard case let .skipped(reason) = try pipeline.capture(transcript: transcript) else {
            Issue.record("a chat from a repository that isn't set up was stored")
            return
        }
        #expect(reason.contains("someone/private isn't set up"))
        #expect(try FolderStore(root: storeFolder.path).list(prefix: "").isEmpty)

        let empty = try home.write("{\"type\":\"custom-title\",\"customTitle\":\"x\"}\n", to: ".claude/projects/-work/empty000.jsonl")
        guard case .skipped = try pipeline.capture(transcript: empty) else {
            Issue.record("an empty chat was stored")
            return
        }
    }

    @Test func leavesALinkOnThePullRequestsThatHoldItsWork() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: repo)
        try home.write(try String(contentsOfFile: transcript, encoding: .utf8)
            + #"{"type":"pr-link","prNumber":7,"prRepository":"acme/widgets"}"# + "\n", to: ".claude/projects/-work/sess-0001.jsonl")
        let fake = FakeShell()
        fake.rules.append(({ $0.tool == "git" }, Shell.Output(status: 0)))
        fake.when("aws", containing: "put-object")
        fake.when("gh", containing: "issues/7/comments", "--paginate", reply: "")
        fake.when("gh", containing: "POST", "issues/7/comments")
        // git is real; aws and gh are stand-ins.
        let shell = Shell { tool, arguments, folder, input in
            tool == "git" ? Shell.system(tool, arguments, in: folder, input: input) : fake.shell(tool, arguments, in: folder, input: input)
        }
        var pipeline = pipeline(home: home, store: "s3://team-history/agent", shell: shell)
        pipeline.config.repos["acme/widgets"]?.region = "eu-north-1"
        guard case let .stored(stored) = try pipeline.capture(transcript: transcript) else {
            Issue.record("the chat wasn't stored")
            return
        }
        #expect(stored.pullRequests == [7])
        #expect(stored.url?.hasPrefix("https://s3.console.aws.amazon.com/s3/object/team-history?region=eu-north-1&prefix=agent/acme/widgets/sessions/") == true)
        let uploads = fake.calls.filter { $0.arguments.contains("put-object") }
        // The chat goes up before its cards: a reader never finds cards whose chat isn't there yet.
        #expect(uploads.map { String($0.arguments[5].split(separator: "/").last ?? "") } == ["chat.json", "page.html", "cards.json"])
        let post = try #require(fake.calls.last { $0.arguments.contains("POST") })
        #expect(post.input?.contains("ambient-agent-history") == true)
        #expect(post.input?.contains("chat:claude:sess-0001") == true)

        // Asked not to, it doesn't.
        let before = fake.calls.count
        _ = try pipeline.capture(transcript: transcript, postLinks: false)
        #expect(!fake.calls[before...].contains { $0.tool == "gh" })
    }

    @Test func aStoreThatIsDownCostsNoModelCalls() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: repo)
        let fake = FakeShell()
        fake.when("aws", containing: "get-object", status: 254, stderr: "An error occurred (NoSuchKey)")
        fake.when("aws", containing: "put-object", status: 255, stderr: "Error when retrieving token from sso: Token has expired")
        let shell = Shell { tool, arguments, folder, input in
            tool == "git" ? Shell.system(tool, arguments, in: folder, input: input) : fake.shell(tool, arguments, in: folder, input: input)
        }
        let model = FakeModel()
        var pipeline = pipeline(home: home, store: "s3://team-history/agent", model: model, shell: shell)
        pipeline.config.repos["acme/widgets"]?.region = "eu-north-1"
        #expect { try pipeline.capture(transcript: transcript) } throws: { "\($0)".contains("Token has expired") }
        // The upload is tried before any card is written, so an expired sign-in, retried every hour, costs nothing.
        #expect(model.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pipeline.paths.historyLedger.path))
    }

    @Test func aRepositoryOnAnotherHostGetsNoPullRequestComment() throws {
        let repo = try Repo(remote: "git@gitlab.internal:acme/widgets.git")
        try repo.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: repo)
        let fake = FakeShell()
        fake.when("aws", containing: "put-object")
        let shell = Shell { tool, arguments, folder, input in
            tool == "git" ? Shell.system(tool, arguments, in: folder, input: input) : fake.shell(tool, arguments, in: folder, input: input)
        }
        var config = HistoryConfig()
        config.repos["gitlab.internal/acme/widgets"] = .init(store: "s3://team-history/agent", region: "eu-north-1")
        let paths = AmbientPaths(userHome: home.url, home: home.url.appendingPathComponent(".ambient"))
        let pipeline = HistoryPipeline(paths: paths, config: config, shell: shell)
        guard case let .stored(stored) = try pipeline.capture(transcript: transcript) else {
            Issue.record("the chat wasn't stored")
            return
        }
        #expect(stored.folder.hasPrefix("gitlab.internal/acme/widgets/sessions/"))
        #expect(!fake.calls.contains { $0.tool == "gh" })
        // The same owner and name on GitHub is a different repository, and isn't set up.
        let onGitHub = try Repo()
        try onGitHub.commit("a.txt", "one\n", message: "a")
        let (otherHome, otherTranscript) = try self.home(for: onGitHub)
        let other = HistoryPipeline(paths: AmbientPaths(userHome: otherHome.url, home: otherHome.url.appendingPathComponent(".ambient")),
                                    config: config, shell: shell)
        guard case .skipped = try other.capture(transcript: otherTranscript) else {
            Issue.record("a repository on another host was taken for the one set up")
            return
        }
    }

    @Test func findsChatsThatWentQuietAfterSetup() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a")
        let (home, transcript) = try home(for: repo)
        let modified = try #require(try FileManager.default.attributesOfItem(atPath: transcript)[.modificationDate] as? Date)
        let storeFolder = try Scratch()
        func due(after seconds: TimeInterval, since: Date? = nil, lookback: Double? = nil) -> [String] {
            pipeline(home: home, store: storeFolder.path, now: modified.addingTimeInterval(seconds), since: since)
                .due(lookbackDays: lookback).map(\.file.sessionID)
        }
        // Still warm: it may not be finished.
        #expect(due(after: 3_600).isEmpty)
        #expect(due(after: 25 * 3_600) == ["sess-0001"])
        // Set up after the chat went quiet: its past stays put unless asked for.
        #expect(due(after: 25 * 3_600, since: modified.addingTimeInterval(60)).isEmpty)
        #expect(due(after: 25 * 3_600, since: modified.addingTimeInterval(60), lookback: 7) == ["sess-0001"])
        #expect(due(after: 40 * 86_400).isEmpty)
        #expect(due(after: 10 * 86_400, lookback: 7).isEmpty)

        // Once captured, it isn't due again until it grows.
        let capturing = pipeline(home: home, store: storeFolder.path, now: modified.addingTimeInterval(25 * 3_600))
        _ = try capturing.capture(transcript: transcript)
        #expect(due(after: 25 * 3_600).isEmpty)
    }

    @Test func readsAChatsFolderFromItsFirstLines() throws {
        let scratch = try Scratch()
        let path = try scratch.write(#"{"type":"x"}"# + "\n" + #"{"type":"user","cwd":"/Users/pat/my \"odd\" repo","x":1}"#, to: "t.jsonl")
        #expect(HistoryPipeline.folder(ofTranscript: path) == "/Users/pat/my \"odd\" repo")
        #expect(HistoryPipeline.folder(ofTranscript: try scratch.write("{}", to: "none.jsonl")) == nil)
        #expect(HistoryPipeline.folder(ofTranscript: "/nonexistent") == nil)
    }
}

@Suite struct QueryTests {
    @Test func explainsAFileFromGitAndTheIndex() throws {
        let repo = try Repo()
        let old = try repo.commit("Sources/Board.swift", "let keep = all\n", message: "feat: the board", at: Date().addingTimeInterval(-86_400))
        let fix = try repo.commit("Sources/Board.swift", "let keep = all.filter { !$0.expired }\n// Finished tasks expire.\n",
                                  message: "fix(board): expire finished tasks")
        var file = Sample.cardFile()
        file.commits[0].sha = fix
        file.cards[0].commits = [fix]
        let index = try index(with: [file, laterFile()])
        let query = HistoryQuery(index: index, root: repo.root)

        let report = try query.why(path: "Sources/Board.swift", line: 2)
        #expect(report.changes.map(\.hit.chat.session.title) == ["Remote open", "Board cleanup"])
        // The chat that committed gets its commit; the one that never did has none.
        #expect(report.changes.map { $0.commits.map(\.sha) } == [[], [fix]])
        #expect(report.changes.map(\.blamed) == [false, true])
        #expect(report.blamedCommit?.sha == fix)
        // The commit before any chat was recorded is listed as unexplained, not guessed at.
        #expect(report.unexplained.map(\.sha) == [old])
        #expect(report.references.isEmpty)

        let readme = try query.why(path: "README.md")
        #expect(readme.changes.isEmpty && readme.references.count == 1 && readme.unexplained.isEmpty)
        let nothing = try query.why(path: "Nope.swift", line: 3)
        #expect(nothing.changes.isEmpty && nothing.blamedCommit == nil)
    }

    @Test func aCommitWithNoVisibleEditStillPointsAtItsRequest() throws {
        let repo = try Repo()
        let sha = try repo.commit("Generated.swift", "x\n", message: "chore: regenerate")
        var file = Sample.cardFile()
        file.commits = [ChatCommit(sha: sha, subject: "chore: regenerate", at: Date(), files: ["Generated.swift"], event: 10)]
        let query = HistoryQuery(index: try index(with: [file]), root: repo.root)
        let report = try query.why(path: "Generated.swift")
        #expect(report.unexplained.isEmpty)
        #expect(report.changes.map(\.hit.card.episode) == [2])
        #expect(report.changes.first?.commits.map(\.sha) == [sha])
    }

    @Test func followsAFileAcrossARename() throws {
        let repo = try Repo()
        try repo.commit("Sources/Board.swift", "one\ntwo\nthree\nfour\n", message: "add")
        try repo.git("mv", "Sources/Board.swift", "Sources/TaskBoard.swift")
        try repo.git("commit", "-qm", "rename")
        let query = HistoryQuery(index: try index(), root: repo.root)
        // Chats from before the rename indexed the old name.
        #expect(try query.why(path: "Sources/TaskBoard.swift").changes.count == 2)
    }

    @Test func retrievesFileChangesFirstThenMatchingWords() throws {
        let query = HistoryQuery(index: try index(), root: nil)
        let byFile = try query.retrieve("what happened to Sources/RemoteOpen.swift?")
        #expect(byFile.first?.chat.session.title == "Remote open")
        let byWords = try query.retrieve("why three days for finished tasks")
        #expect(byWords.first?.chat.session.title == "Board cleanup")
        #expect(try query.retrieve("README.md", files: ["README.md"]).map(\.how) == [.read])
        #expect(try query.retrieve("zzzz qqqq").isEmpty)
        // A card found two ways appears once.
        let both = try query.retrieve("RemoteOpen ssh chat", files: ["Sources/RemoteOpen.swift"])
        #expect(both.filter { $0.chat.session.title == "Remote open" }.count == 1)
    }
}

@Suite struct AnswerTests {
    private func answerer(_ model: (any TextModel)?, useModel: Bool = true, chat: ChatRecord? = Sample.record) throws -> HistoryAnswerer {
        var config = HistoryConfig()
        config.useModel = useModel
        return HistoryAnswerer(query: HistoryQuery(index: try index(), root: nil), config: config, model: model) { _ in chat }
    }

    @Test func withoutAModelTheCardsAreTheAnswer() throws {
        let answer = try answerer(nil).ask("why do finished tasks expire?")
        #expect(answer.depth == .cards && !answer.sources.isEmpty)
        #expect(answer.text.contains("Finished tasks now expire after three days."))
        #expect(answer.note?.contains("No Claude API key") == true)
        #expect(try answerer(FakeModel(), useModel: false).ask("finished tasks").note?.contains("turned off") == true)
        let nothing = try answerer(FakeModel()).ask("zzzz qqqq")
        #expect(nothing.text == "No recorded chat is about that." && nothing.sources.isEmpty)
    }

    @Test func aSmallModelAnswersFromTheCardsWhenTheySettleIt() throws {
        let model = FakeModel([#"{"answer":"So Friday's tasks last the weekend (C1).","cited":["C1"],"sufficient":true,"need":[]}"#])
        let answer = try answerer(model).ask("why do finished tasks expire after three days?")
        #expect(answer.depth == .quick)
        #expect(answer.text == "So Friday's tasks last the weekend (C1).")
        #expect(answer.sources.count == 1)
        #expect(model.requests.count == 1)
        let request = try #require(model.requests.first)
        #expect(request.model == "claude-haiku-5-5")
        #expect(request.user.hasPrefix("Question: why do finished tasks expire after three days?"))
        #expect(request.user.contains("<card id=\"C1\">") && request.user.contains("Landed: committed (aaaaaaa)"))
    }

    @Test func aStrongerModelReadsTheChatsWhenTheCardsFallShort() throws {
        let model = FakeModel([#"{"answer":"The cards don't say.","cited":[],"sufficient":false,"need":["C1","C9","C1"]}"#,
                               #"{"answer":"The edit filters expired tasks (C1 e4).","cited":["C1 e4"]}"#])
        let answer = try answerer(model).ask("what exactly did the edit to the board change?")
        #expect(answer.depth == .deep)
        #expect(answer.text == "The edit filters expired tasks (C1 e4).")
        #expect(answer.sources.count == 1 && answer.note == nil)
        #expect(model.requests.map(\.model) == ["claude-haiku-5-5", "claude-opus-5-5"])
        let deep = model.requests[1]
        #expect(deep.effort == "medium")
        #expect(deep.user.contains("<chat card=\"C1\">"))
        // The chat's own events, with the diff, are what the deep pass adds.
        #expect(deep.user.contains("let keep = all.filter"))
        #expect(!deep.user.contains("<chat card=\"C9\">"))
    }

    @Test func aModelThatFailsCostsTheWordsNotTheAnswer() throws {
        let failing = FakeModel()
        failing.fail("The model's answer was cut off.")
        let quick = try answerer(failing).ask("why do finished tasks expire?")
        #expect(quick.depth == .cards && !quick.sources.isEmpty)
        #expect(quick.text.contains("Finished tasks now expire") && quick.note?.contains("cut off") == true)

        let deepFailing = FakeModel([#"{"answer":"?","cited":["C1"],"sufficient":false,"need":["C1"]}"#])
        deepFailing.fail("The Claude API answered 529.")
        let deep = try answerer(deepFailing).ask("why do finished tasks expire?")
        #expect(deep.depth == .cards && deep.note?.contains("529") == true)
        #expect(deepFailing.requests.last?.maxTokens == 16_000)
    }

    @Test func askedToGoDeepItSkipsTheQuickPass() throws {
        let model = FakeModel([#"{"answer":"Deep.","cited":[]}"#])
        let answer = try answerer(model, chat: nil).ask("finished tasks expire", deep: true)
        #expect(answer.depth == .deep && model.requests.map(\.model) == ["claude-opus-5-5"])
        // The chats couldn't be had, and it says so instead of passing cards off as chats.
        #expect(answer.note?.contains("cards alone") == true)
        // With nothing cited, every card it was given is listed.
        #expect(answer.sources.count >= 1)
    }

    @Test func readsModelRepliesTolerantly() {
        #expect(HistoryAnswerer.parse("plain words").answer == "plain words")
        #expect(HistoryAnswerer.positions(["C2", "c1", "C2 e4", "C0", "C7", "x"], count: 3) == [1, 0])
        #expect(HistoryAnswerer.positions([], count: 3).isEmpty)
    }
}

@Suite struct PullRequestLinkTests {
    @Test func writesOneLinePerChatAndReplacesItsOwn() {
        let line = PullRequestLinks.line(for: Sample.record, url: "https://example.com/x", changes: 1)
        #expect(line == "- [claude chat of 2026-11-18](https://example.com/x) — 1 request changed code <!-- chat:claude:11111111-2222-3333-4444-555555555555 -->")
        let tag = "<!-- chat:claude:11111111-2222-3333-4444-555555555555 -->"
        let first = PullRequestLinks.body(adding: line, sessionTag: tag, to: nil)
        #expect(first.hasPrefix(PullRequestLinks.marker) && first.contains(line))
        let other = "- [codex chat of 2026-11-17](https://example.com/o) — 2 requests changed code <!-- chat:codex:zzz -->"
        let existing = first + other + "\n"
        let newer = line.replacingOccurrences(of: "1 request", with: "3 requests")
        let updated = PullRequestLinks.body(adding: newer, sessionTag: tag, to: existing)
        #expect(updated.components(separatedBy: "\n").filter { $0.hasPrefix("- ") } == [other, newer])
    }

    @Test func thePublicLineSaysNothingTheChatSaid() {
        var private_ = Sample.record
        private_.session.title = "Rotate the leaked prod key for @octocat"
        private_.session.developer = "Pat Example"
        private_.session.agent = "cl[au]de(x) <b>"
        private_.session.id = "id --> <!-- chat:x"
        let line = PullRequestLinks.line(for: private_, url: "u", changes: 2)
        // A pull request may be public: no title, no name, and nothing free-form that could become markup.
        #expect(line == "- [claudexb chat of 2026-11-18](u) — 2 requests changed code <!-- chat:claudexb:id----chatx -->")
    }

    @Test func findsThePullRequestsHoldingAChatsCommits() {
        let fake = FakeShell()
        fake.when("gh", containing: "commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/pulls", reply: "35\n36\n")
        let links = PullRequestLinks(shell: fake.shell)
        let found = links.pullRequests(for: Sample.record, recorded: [.init(repo: "Acme/Widgets", number: 12), .init(repo: "other/repo", number: 99)])
        #expect(found == [12, 35, 36])
        #expect(fake.calls.first?.arguments.first == "api")
    }

    @Test func createsUpdatesOrLeavesTheComment() throws {
        let url = "https://example.com/x"
        let line = PullRequestLinks.line(for: Sample.record, url: url, changes: 1)
        let tag = "<!-- chat:claude:11111111-2222-3333-4444-555555555555 -->"
        let current = PullRequestLinks.body(adding: line, sessionTag: tag, to: nil)

        let fake = FakeShell()
        fake.when("gh", containing: "issues/1/comments", "--paginate", reply: "")
        fake.when("gh", containing: "POST", "issues/1/comments")
        fake.when("gh", containing: "issues/2/comments", "--paginate", reply: "555\u{1f}\(PullRequestLinks.marker)\n- [Old](u) <!-- chat:codex:old -->\u{1e}\n")
        fake.when("gh", containing: "PATCH", "issues/comments/555")
        fake.when("gh", containing: "issues/3/comments", "--paginate", reply: "777\u{1f}\(current)\u{1e}\n")
        fake.when("gh", containing: "issues/4/comments", "--paginate", status: 1, stderr: "HTTP 404")
        let posted = PullRequestLinks(shell: fake.shell).post(for: Sample.record, url: url, changes: 1, to: [1, 2, 3, 4])
        #expect(posted == [1, 2, 3])
        let writes = fake.calls.filter { $0.input != nil }
        #expect(writes.map { $0.arguments[2] } == ["POST", "PATCH"])
        let sent = try #require(writes[1].input)
        let patched = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: String])
        #expect(patched["body"]?.contains("- [Old](u) <!-- chat:codex:old -->\n" + line) == true)
        // Pull request 3 already says exactly this: nothing is written.
        #expect(!fake.calls.contains { $0.arguments.contains("repos/acme/widgets/issues/comments/777") })
    }
}

@Suite struct PageAndEvalTests {
    @Test func rendersAChatAsAPageThatTrustsNothingInIt() {
        var record = Sample.record
        record.events[1].text = "Use <script>alert(1)</script> & \"quotes\".\n\n```swift\nlet a = 1 < 2\n```"
        record.uncommitted = "diff --git a/x b/x\n@@ -1 +1 @@\n-old\n+new"
        let page = HistoryPage.render(record, cards: Sample.cardFile().cards)
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(!page.contains("<script>alert"))
        #expect(page.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quotes&quot;."))
        #expect(page.contains("<span class=\"l \">let a = 1 &lt; 2</span>"))
        #expect(page.contains("<span class=\"l del\">-let keep = all</span>"))
        #expect(page.contains("<span class=\"l add\">+let keep = all.filter { !$0.expired }</span>"))
        #expect(page.contains("<span class=\"l hunk\">@@ -1,1 +1,2 @@</span>"))
        #expect(page.contains("<section id=\"e4\" class=\"tool\"><h4>Code change · <code>Edit</code>"))
        #expect(page.contains("<a href=\"#e9\">Why three days and not one?</a>"))
        #expect(page.contains("id=\"uncommitted\"") && page.contains("<span class=\"l meta\">diff --git a/x b/x</span>"))
        #expect(page.contains("<code>aaaaaaa</code> fix(board): expire finished tasks"))
    }

    @Test func scoresRetrievalAndAnswers() throws {
        let questions = try HistoryEval.load(Data(#"""
            {"questions":[
              {"ask":"why do finished tasks expire?","expectSession":"11111111","expectFiles":["Sources/Board.swift"],"expectWords":["three days","weekend|friday"]},
              {"ask":"what about remote open?","expectSession":"99999999"}]}
            """#.utf8))
        #expect(questions.count == 2 && questions[1].expectFiles.isEmpty && questions[1].expectWords.isEmpty)
        let hits = try index().requests(touching: ["Sources/Board.swift"], changesOnly: true)
        #expect(HistoryEval.found(questions[0], in: hits))
        #expect(HistoryEval.found(questions[1], in: hits))
        #expect(!HistoryEval.found(questions[0], in: Array(hits.prefix(1))))
        var wrongFile = questions[0]
        wrongFile.expectFiles = ["Elsewhere.swift"]
        #expect(!HistoryEval.found(wrongFile, in: hits))

        #expect(HistoryEval.answered(questions[0], by: "They expire after Three Days so FRIDAY's work survives."))
        #expect(!HistoryEval.answered(questions[0], by: "They expire after three days."))
        #expect(HistoryEval.answered(questions[1], by: "anything"))
        let summary = HistoryEval.summary([.init(question: questions[0], found: true, answered: true, depth: .deep),
                                           .init(question: questions[1], found: false, answered: false, depth: .quick)])
        #expect(summary == "Retrieval: 1/2 questions found their chat in the first five cards.\nAnswers: 1/2 held the expected words; 1 needed the deep pass.")
        #expect(throws: HistoryError.self) { try HistoryEval.load(Data("[]".utf8)) }
    }
}
