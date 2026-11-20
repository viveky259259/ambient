import Foundation
import Testing
@testable import AmbientHistory

@Suite struct GitFactsTests {
    private let git = GitFacts()

    @Test(arguments: [
        ("git@github.com:acme/widgets.git", "acme/widgets"), ("https://github.com/acme/widgets", "acme/widgets"),
        ("https://github.com/acme/widgets.git", "acme/widgets"), ("ssh://git@gitlab.example.com:22/group/sub/widgets.git", "sub/widgets"),
        ("/local/path/widgets", nil), ("https://github.com/widgets", nil), ("git@github.com:acme/wid gets.git", nil),
    ] as [(String, String?)])
    func readsTheRepositoryNameFromItsRemote(_ url: String, _ slug: String?) {
        #expect(GitFacts.slug(fromRemote: url) == slug)
    }

    @Test func describesACheckout() throws {
        let repo = try Repo()
        try repo.commit("Sources/Board.swift", "let a = 1\n", message: "first")
        try repo.scratch.write("x", to: "Sources/Deep/untracked.txt")
        #expect(git.root(of: repo.root + "/Sources") == repo.root)
        #expect(git.root(of: "/nonexistent/folder") == nil)
        #expect(git.slug(of: repo.root) == "acme/widgets")
        #expect(git.branch(of: repo.root) == "main")
        #expect(git.developer(of: repo.root) == "Test Dev")
        #expect(git.trackedFiles(in: repo.root) == ["Sources/Board.swift"])
        #expect(try Repo(remote: nil).git("status", "--short") == "")
        #expect(git.slug(of: try Repo(remote: nil).root) == nil)
    }

    @Test func listsCommitsInAWindowWithTheirFiles() throws {
        let repo = try Repo()
        let before = Date().addingTimeInterval(-5)
        let first = try repo.commit("a.txt", "1\n", message: "add a")
        try repo.git("checkout", "-q", "-b", "side")
        let second = try repo.commit("dir/b c.txt", "2\n", message: "add b: with \u{1f}odd text")
        let found = git.commits(in: repo.root, from: before, to: Date().addingTimeInterval(5))
        // Both branches are searched: a chat may commit on one that isn't checked out here.
        #expect(Set(found.map(\.sha)) == [first, second])
        #expect(found.first { $0.sha == second }?.files == ["dir/b c.txt"])
        #expect(found.first { $0.sha == first }?.subject == "add a")
        #expect(git.commits(in: repo.root, from: before.addingTimeInterval(-100), to: before).isEmpty)
    }

    @Test func aMergeListsWhatItBroughtIn() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "1\n", message: "base")
        try repo.git("checkout", "-q", "-b", "side")
        try repo.commit("b.txt", "2\n", message: "side work")
        try repo.git("checkout", "-q", "main")
        try repo.commit("c.txt", "3\n", message: "main work")
        try repo.git("merge", "-q", "--no-ff", "-m", "merge side", "side")
        let merge = try repo.git("rev-parse", "HEAD")
        let found = git.commits(in: repo.root, from: Date().addingTimeInterval(-60), to: Date().addingTimeInterval(5))
        #expect(found.first { $0.sha == merge }?.files == ["b.txt"])
    }

    @Test func showsOnlyTheNamedFilesUncommittedChanges() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a")
        try repo.commit("b.txt", "one\n", message: "b")
        try repo.scratch.write("one\ntwo\n", to: "a.txt")
        try repo.scratch.write("changed\n", to: "b.txt")
        try repo.scratch.write("brand new\n", to: "new.txt")
        let diff = git.uncommitted(["a.txt", "new.txt", "missing.txt"], in: repo.root)
        #expect(diff.contains("+two"))
        #expect(diff.contains("+brand new"))
        // b.txt changed too, but it wasn't asked about: another chat may be working in the same checkout.
        #expect(!diff.contains("changed"))
        #expect(git.uncommitted([], in: repo.root) == "")
        #expect(git.uncommitted(["a.txt"], in: repo.root, limit: 20).contains("more characters cut"))
    }

    @Test func followsAFilesHistoryAndBlamesALine() throws {
        let repo = try Repo()
        let first = try repo.commit("old.swift", "line one\nline two\nline three\n", message: "add")
        try repo.git("mv", "old.swift", "new.swift")
        try repo.git("commit", "-q", "-m", "rename")
        let third = try repo.commit("new.swift", "line one\nline 2\nline three\n", message: "edit two")
        let history = git.history(of: "new.swift", in: repo.root)
        #expect(history.map(\.subject) == ["edit two", "rename", "add"])
        #expect(history.map(\.path) == ["new.swift", "new.swift", "old.swift"])
        #expect(history.first?.author == "Test Dev")
        #expect(git.blame("new.swift", line: 2, in: repo.root) == third)
        #expect(git.blame("new.swift", line: 1, in: repo.root)?.hasPrefix(String(first.prefix(39))) == true)
        #expect(git.blame("new.swift", line: 99, in: repo.root) == nil)
        try repo.scratch.write("line one\nline 2\nline three\nnot committed\n", to: "new.swift")
        #expect(git.blame("new.swift", line: 4, in: repo.root) == nil)
        #expect(git.patch(of: third, path: "new.swift", in: repo.root).contains("+line 2"))
    }
}

@Suite struct CaptureTests {
    /// A chat in `repo`: reads a file, edits one with the edit tool, changes one with a script, and commits.
    private func chat(in repo: Repo, commitAt: Date, commitDone: Date) -> RawChat {
        let start = commitAt.addingTimeInterval(-60)
        return RawChat(sessionID: "sess-1", agent: "claude", title: nil, folder: repo.root, branch: "feat/x", events: [
            .init(at: start, kind: .user, text: "Speed up Sources/Board.swift please.\nIt is slow.", folder: repo.root),
            .init(at: start.addingTimeInterval(1), kind: .tool, text: repo.root + "/README.md", tool: "Read",
                  paths: [FileTouch(path: repo.root + "/README.md", how: .read)], callID: "c1", folder: repo.root),
            .init(at: start.addingTimeInterval(2), kind: .result, text: String(repeating: "r", count: 5_000), callID: "c1"),
            .init(at: start.addingTimeInterval(3), kind: .tool, text: repo.root + "/Sources/Board.swift", tool: "Edit",
                  diff: "-let a = 1\n+let a = 2", paths: [FileTouch(path: repo.root + "/Sources/Board.swift", how: .edit)],
                  callID: "c2", folder: repo.root),
            .init(at: start.addingTimeInterval(4), kind: .tool,
                  text: "python3 - <<'EOF'\np='Sources/Card.swift'\nopen(p,'w').write('x')\nEOF\ncat README.md > /dev/null; export API_TOKEN=abcdefghijklmnop",
                  tool: "Bash", label: "Patch the card in \(repo.root)", callID: "c3", folder: repo.root),
            .init(at: commitAt, kind: .tool, text: "git add -A && git commit -qm 'speed up the board'", tool: "Bash",
                  callID: "c4", folder: repo.root),
            .init(at: commitDone, kind: .result, text: "", callID: "c4"),
            .init(at: commitDone.addingTimeInterval(1), kind: .agent, text: "Done: Sources/Board.swift is faster.", folder: repo.root),
        ], pullRequests: [])
    }

    @Test func buildsTheRecordAChatIsStoredAs() throws {
        let repo = try Repo()
        let earlier = Date().addingTimeInterval(-3_600)
        try repo.commit("README.md", "readme\n", message: "readme", at: earlier)
        try repo.commit("Sources/Board.swift", "let a = 1\n", message: "board", at: earlier)
        try repo.commit("Sources/Card.swift", "c\n", message: "card", at: earlier)
        try repo.commit("Sources/Other.swift", "o\n", message: "other", at: earlier)
        let commitAt = Date()
        try repo.scratch.write("let a = 2\n", to: "Sources/Board.swift")
        try repo.scratch.write("x", to: "Sources/Card.swift")
        try repo.git("add", "-A")
        try repo.git("commit", "-qm", "speed up the board")
        let sha = try repo.git("rev-parse", "HEAD")
        let commitDone = Date()
        // Work the chat never committed, and a change that isn't the chat's at all.
        try repo.scratch.write("let a = 3\n", to: "Sources/Board.swift")
        try repo.scratch.write("someone else\n", to: "Sources/Other.swift")

        let capture = Capture(git: GitFacts(), home: "/Users/pat")
        let record = capture.record(from: chat(in: repo, commitAt: commitAt, commitDone: commitDone), now: Date())

        #expect(record.session.repo == "acme/widgets")
        #expect(record.session.developer == "Test Dev")
        #expect(record.session.branch == "feat/x")
        #expect(record.session.title == "Speed up Sources/Board.swift please.")
        #expect(record.events.map(\.n) == Array(1...8))

        // Paths are relative to the repository, whatever folder the machine keeps it in.
        #expect(record.events[0].touches == [FileTouch(path: "Sources/Board.swift", how: .mention)])
        #expect(record.events[1].text == "README.md")
        #expect(record.events[1].touches == [FileTouch(path: "README.md", how: .read)])
        #expect(record.events[3].text == "Sources/Board.swift")
        #expect(record.events[3].touches == [FileTouch(path: "Sources/Board.swift", how: .edit)])
        // A script that writes files changed the one git saw change afterwards; the one it only read stays a read.
        #expect(record.events[4].touches == [FileTouch(path: "Sources/Card.swift", how: .shell), FileTouch(path: "README.md", how: .read)])
        #expect(record.events[4].text.contains("API_TOKEN=[redacted: credential]"))
        #expect(record.events[4].label?.contains(repo.root) == true)

        // Long output keeps both ends and says what it dropped; results point at their calls.
        #expect(record.events[2].text.count == 3_003)
        #expect(record.events[2].cut == 2_000)
        #expect(record.events[2].of == 2)
        #expect(record.events[6].of == 6)

        // The commit made while the commit command ran is this chat's, tied to that command.
        #expect(record.commits.map(\.sha) == [sha])
        #expect(record.commits.first?.event == 6)
        #expect(record.commits.first?.files.sorted() == ["Sources/Board.swift", "Sources/Card.swift"])

        // What its files still differ by, and nothing about the file it never touched.
        let uncommitted = try #require(record.uncommitted)
        #expect(uncommitted.contains("+let a = 3"))
        #expect(!uncommitted.contains("someone else"))
    }

    @Test func anEditThatFailedChangedNothing() throws {
        let repo = try Repo()
        try repo.commit("a.txt", "one\n", message: "a", at: Date().addingTimeInterval(-3_600))
        let chat = RawChat(sessionID: "s", agent: "claude", title: "t", folder: repo.root, branch: nil, events: [
            .init(at: Date(), kind: .user, text: "change it", folder: repo.root),
            .init(at: Date(), kind: .tool, text: repo.root + "/a.txt", tool: "Edit", diff: "-nope\n+two",
                  paths: [FileTouch(path: repo.root + "/a.txt", how: .edit)], callID: "c1", folder: repo.root),
            .init(at: Date(), kind: .result, text: "String to replace not found", callID: "c1", failed: true),
            .init(at: Date(), kind: .tool, text: repo.root + "/a.txt", tool: "Edit", diff: "-one\n+two",
                  paths: [FileTouch(path: repo.root + "/a.txt", how: .edit)], callID: "c2", folder: repo.root),
            .init(at: Date(), kind: .result, text: "Updated.", callID: "c2"),
        ], pullRequests: [])
        let events = Capture(git: GitFacts(), home: "/Users/pat").record(from: chat, now: Date()).events
        #expect(events[1].touches == [FileTouch(path: "a.txt", how: .read)])
        #expect(events[2].failed == true)
        #expect(events[3].touches == [FileTouch(path: "a.txt", how: .edit)])
    }

    @Test func aCommitSomeoneElseMadeMeanwhileIsNotThisChats() throws {
        let repo = try Repo()
        try repo.commit("mine.txt", "one\n", message: "base", at: Date().addingTimeInterval(-3_600))
        // A long command: the tests run, then the commit. While it runs, another chat commits an unrelated file.
        let began = Date()
        let theirs = try repo.commit("theirs.txt", "x\n", message: "feat: someone else's work")
        try repo.scratch.write("two\n", to: "mine.txt")
        try repo.git("commit", "-qam", "fix: mine")
        let mine = try repo.git("rev-parse", "HEAD")
        try repo.git("commit", "-q", "--allow-empty", "-m", "chore: an empty marker")
        let empty = try repo.git("rev-parse", "HEAD")
        let done = Date()
        let chat = RawChat(sessionID: "s", agent: "claude", title: "t", folder: repo.root, branch: nil, events: [
            .init(at: began, kind: .user, text: "fix it", folder: repo.root),
            .init(at: began, kind: .tool, text: "swift test && sed -i '' 's/one/two/' mine.txt && git commit -qam 'fix: mine'",
                  tool: "Bash", callID: "c1", folder: repo.root),
            .init(at: done, kind: .result, text: "", callID: "c1"),
        ], pullRequests: [])
        let record = Capture(git: GitFacts(), home: "/Users/pat").record(from: chat, now: Date())
        #expect(!record.commits.map(\.sha).contains(theirs))
        #expect(record.commits.map(\.sha).contains(mine))
        // A commit with no files can only be judged by when it was made.
        #expect(record.commits.map(\.sha).contains(empty))
    }

    @Test func aMergeTheChatRanIsItsOwnWhateverItBroughtIn() throws {
        let repo = try Repo()
        let earlier = Date().addingTimeInterval(-3_600)
        try repo.commit("mine.txt", "one\n", message: "base", at: earlier)
        try repo.git("checkout", "-q", "-b", "other")
        try repo.commit("far/away.txt", "x\n", message: "feat: elsewhere", at: earlier)
        try repo.git("checkout", "-q", "main")
        try repo.commit("mine.txt", "two\n", message: "fix: mine", at: earlier)
        let began = Date()
        try repo.git("merge", "-q", "--no-ff", "-m", "Merge branch 'other'", "other")
        let merge = try repo.git("rev-parse", "HEAD")
        let chat = RawChat(sessionID: "s", agent: "claude", title: "t", folder: repo.root, branch: nil, events: [
            .init(at: began, kind: .user, text: "bring main up to date", folder: repo.root),
            .init(at: began, kind: .tool, text: "git fetch -q; git merge -q --no-ff other", tool: "Bash", callID: "c1", folder: repo.root),
            .init(at: Date(), kind: .result, text: "", callID: "c1"),
        ], pullRequests: [])
        let record = Capture(git: GitFacts(), home: "/Users/pat").record(from: chat, now: Date())
        // The merge brought in a file the chat never named, and its message isn't in the command: it is still the
        // chat's, because the chat's command was a merge and the commit is one.
        #expect(record.commits.map(\.sha) == [merge])
        #expect(record.commits.first?.files == ["far/away.txt"])
    }

    @Test func aChatWhoseFolderIsGoneIsStillRecorded() {
        let capture = Capture(git: GitFacts(), home: "/Users/pat")
        let chat = RawChat(sessionID: "s", agent: "claude", title: "Gone", folder: "/Users/pat/removed/widgets", branch: nil, events: [
            .init(at: Sample.at(0), kind: .user, text: "edit /Users/pat/removed/widgets/src/app/main.py", folder: "/Users/pat/removed/widgets"),
            .init(at: Sample.at(1), kind: .tool, text: "sed -i '' 's/a/b/' src/app/main.py", tool: "Bash", folder: "/Users/pat/removed/widgets"),
        ], pullRequests: [])
        #expect(capture.place(of: chat) == .init(root: nil, repo: "widgets"))
        let record = capture.record(from: chat, now: Sample.at(100))
        #expect(record.session.repo == "widgets")
        #expect(record.commits.isEmpty && record.uncommitted == nil)
        #expect(record.events[0].text == "edit ~/removed/widgets/src/app/main.py")
        // With no repository to ask, a writing command's word is taken for it.
        #expect(record.events[1].touches == [FileTouch(path: "~/removed/widgets/src/app/main.py", how: .shell)])
    }

    @Test func cutsLongTextAndCountsIt() {
        var capture = Capture(git: GitFacts(), home: "/Users/pat")
        capture.limits.said = 10
        capture.limits.thinking = 5
        capture.limits.command = 8
        capture.limits.diff = 6
        let chat = RawChat(sessionID: "s", agent: "claude", title: "t", folder: "/nonexistent", branch: nil, events: [
            .init(at: Sample.at(0), kind: .user, text: String(repeating: "u", count: 15)),
            .init(at: Sample.at(1), kind: .thinking, text: String(repeating: "t", count: 9)),
            .init(at: Sample.at(2), kind: .tool, text: String(repeating: "c", count: 10), tool: "Other", diff: String(repeating: "d", count: 10)),
            .init(at: Sample.at(3), kind: .agent, text: "short"),
        ], pullRequests: [])
        let events = capture.record(from: chat, now: Sample.at(10)).events
        #expect(events.map(\.text.count) == [10, 5, 8, 5])
        #expect(events.map(\.cut) == [5, 4, 6, nil])
        #expect(events[2].diff?.count == 6)
    }
}

@Suite struct EpisodeTests {
    @Test func splitsWhereThePersonSpoke() {
        let episodes = Episodes.split(Sample.record)
        #expect(episodes.map(\.n) == [1, 2])
        #expect(episodes.map(\.firstEvent) == [1, 9])
        #expect(episodes.map(\.lastEvent) == [8, 10])
        #expect(episodes[0].request == "The board is slow. Fix it.")
        #expect(episodes[0].changed == ["Sources/Board.swift"])
        #expect(episodes[0].made == ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
        #expect(episodes[1].changed.isEmpty && episodes[1].made.isEmpty)
    }

    @Test func messagesInARowAreOneRequest() {
        let record = ChatRecord(session: Sample.session, events: [
            ChatEvent(n: 1, kind: .system, text: "<task-notification>resumed</task-notification>"),
            ChatEvent(n: 2, kind: .agent, text: "Hello again."),
            ChatEvent(n: 3, kind: .user, text: "First thing."),
            ChatEvent(n: 4, kind: .user, text: "And another."),
            ChatEvent(n: 5, kind: .agent, text: "Both done."),
            ChatEvent(n: 6, kind: .user, actor: "sub", text: "A subagent's own turn isn't the person."),
            ChatEvent(n: 7, kind: .user, text: "Last."),
        ])
        let episodes = Episodes.split(record)
        // Nobody asked for the first stretch: it opens with a notice, not a brief.
        #expect(episodes.map(\.request) == ["", "First thing.\n\nAnd another.", "Last."])
        #expect(episodes.map(\.firstEvent) == [1, 3, 7])
        #expect(episodes.map(\.lastEvent) == [2, 6, 7])
        #expect(Episodes.split(ChatRecord(session: Sample.session, events: [])).isEmpty)
    }

    @Test func aChatStartedByAnotherSessionTakesItsBriefAsTheRequest() {
        let record = ChatRecord(session: Sample.session, events: [
            ChatEvent(n: 1, kind: .system, text: "Check whether the remote agents work is ready to publish."),
            ChatEvent(n: 2, kind: .agent, text: "It is ready."),
            ChatEvent(n: 3, kind: .system, text: "<ci-monitor-event>checks passed"),
        ])
        let episodes = Episodes.split(record)
        #expect(episodes.map(\.request) == ["Check whether the remote agents work is ready to publish."])
        #expect(Episodes.isNotice("  <system-reminder>x") && Episodes.isNotice("[Request interrupted by user]"))
        #expect(!Episodes.isNotice("Fix the <b>board</b>"))
    }

    @Test func placesEachFileOncePerRequestByTheStrongestTouch() {
        let touches = Episodes.touches(in: Sample.record, episodes: Episodes.split(Sample.record))
        #expect(touches == [PlacedTouch(path: "Sources/Board.swift", how: .edit, episode: 1, event: 4)])
        var record = Sample.record
        record.events[9].touches = [FileTouch(path: "Sources/Board.swift", how: .mention), FileTouch(path: "~/notes.md", how: .read)]
        let again = Episodes.touches(in: record, episodes: Episodes.split(record))
        // Files outside the repository aren't indexed.
        #expect(again.map(\.how) == [.edit, .mention])
        #expect(again.map(\.episode) == [1, 2])
    }

    @Test func aCardFromTheChatsOwnWords() {
        let episodes = Episodes.split(Sample.record)
        let first = Episodes.card(for: episodes[0], in: Sample.record)
        #expect(first.summary == "Finished tasks now expire after three days. All 12 tests pass.")
        #expect(first.request == "The board is slow. Fix it.")
        #expect(first.files == ["Sources/Board.swift"])
        #expect(first.landed == .committed)
        #expect(first.commits == ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
        #expect(first.evidence == [4, 8])
        #expect(first.source == "extract" && first.why.isEmpty)
        let second = Episodes.card(for: episodes[1], in: Sample.record)
        #expect(second.landed == .none)
        #expect(second.summary.hasPrefix("A weekend"))

        var uncommitted = Sample.record
        uncommitted.commits = []
        #expect(Episodes.card(for: episodes[0], in: uncommitted).landed == .uncommitted)
    }

    @Test func aLaterCommitCarriesAnEarlierRequestsFiles() {
        var record = Sample.record
        // The commit was made in the second request, and holds the first one's file.
        record.commits[0].event = 10
        let episodes = Episodes.split(record)
        #expect(episodes[0].made.isEmpty)
        #expect(Episodes.card(for: episodes[0], in: record).landed == .committed)
        #expect(Episodes.card(for: episodes[1], in: record).commits == record.commits.map(\.sha))
    }

    @Test func theSummaryIsWhatWasSaidBeforeAnyCINotice() {
        var record = Sample.record
        record.events.insert(ChatEvent(n: 0, kind: .system, text: "<ci-monitor-event>checks failed"), at: 8)
        record.events.insert(ChatEvent(n: 0, kind: .agent, text: "That comment isn't a review."), at: 9)
        for index in record.events.indices { record.events[index].n = index + 1 }
        let episodes = Episodes.split(record)
        #expect(Episodes.card(for: episodes[0], in: record).summary.hasPrefix("Finished tasks now expire"))
    }
}
