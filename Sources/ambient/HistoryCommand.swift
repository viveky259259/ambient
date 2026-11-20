import AmbientCore
import AmbientHistory
import Foundation

/// `ambient history`: keep finished agent chats in a team's store, and ask why the code is the way it is.
struct HistoryCommand {
    let paths: AmbientPaths
    var shell: Shell = .system
    /// The folder commands run in; tests set it.
    var folder: String = FileManager.default.currentDirectoryPath
    /// Finds the model that writes cards and answers; tests replace it. `asking` is false when the app started the
    /// command by itself: then the Keychain is read only if macOS won't show a permission dialog.
    var findModel: (_ asking: Bool) -> (any TextModel)? = { ClaudeAPI.fromKeychain(asking: $0) }
    private let out = Terminal()

    static let usage = """
          ambient history setup --store s3://BUCKET[/PREFIX]|FOLDER [--region REGION] [--profile NAME] [--no-links]
                                                                  Keep this repository's finished agent chats in a store
          ambient history status                                  What is set up, and what is waiting to be captured
          ambient history capture [--session ID|--transcript PATH|--due [--since DAYS]] [--dry-run] [--no-links] [--no-model]
                                                                  Store a finished chat now (the app does this itself);
                                                                  --since also takes chats from before setup
          ambient history sync                                    Fetch the team's new chats into this Mac's index
          ambient history why PATH[:LINE] [--all] [--json] [--no-sync]
                                                                  The chats and commits behind a file, or one line of it
          ambient history ask "QUESTION" [--file PATH] [--deep] [--json] [--no-sync] [--no-model]
                                                                  Answer a question from the recorded chats
          ambient history show SESSION [FROM-TO]                  Print a stored chat, or some of its events
          ambient history open SESSION                            Open a stored chat's page in the browser
          ambient history eval FILE [--answers]                   Score retrieval (and answers) on a set of questions
        """

    func run(_ args: [String]) -> Int32 {
        guard let command = args.first else {
            print(Self.usage)
            return 0
        }
        let rest = Array(args.dropFirst())
        do {
            switch command {
            case "setup": return try setup(rest)
            case "status": return try status()
            case "capture": return try capture(rest)
            case "sync": return try sync()
            case "why": return try why(rest)
            case "ask": return try ask(rest)
            case "show": return try show(rest)
            case "open": return try open(rest)
            case "eval": return try eval(rest)
            case "help", "--help", "-h":
                print(Self.usage)
                return 0
            default:
                out.error("Unknown history command '\(command)'.")
                print(Self.usage)
                return 64
            }
        } catch {
            out.error("\(error)")
            return 1
        }
    }

    // MARK: - Arguments

    /// Flags that take a value, flags that don't, and everything else, in order.
    struct Arguments {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var rest: [String] = []

        init(_ args: [String], valued: Set<String>) throws {
            var index = 0
            while index < args.count {
                let arg = args[index]
                if valued.contains(arg) {
                    guard index + 1 < args.count else { throw HistoryError.message("\(arg) needs a value.") }
                    values[arg] = args[index + 1]
                    index += 2
                } else if arg.hasPrefix("--") {
                    flags.insert(arg)
                    index += 1
                } else {
                    rest.append(arg)
                    index += 1
                }
            }
        }
    }

    // MARK: - Where we are

    /// The repository around a folder and what history is set up for it.
    struct Context {
        var root: String?
        var repo: String
        var config: HistoryConfig
        var store: (any HistoryStore)?
    }

    func context(in named: String? = nil) -> Context {
        let git = GitFacts(shell: shell)
        let start = named ?? folder
        let root = git.root(of: start)
        let repo = root.map { git.slug(of: $0) ?? ($0 as NSString).lastPathComponent } ?? (start as NSString).lastPathComponent
        let config = HistoryConfig.load(from: paths.historyConfig)
        return Context(root: root, repo: repo, config: config, store: config.store(for: repo, shell: shell))
    }

    private func notSetUp(_ context: Context) -> HistoryError {
        .message("History isn't set up for \(context.repo). Run `ambient history setup --store …` in the repository.")
    }

    func index(for context: Context) throws -> HistoryIndex {
        try HistoryIndex(path: paths.historyIndex(for: context.repo).path)
    }

    /// Brings the index up to date, at most once every ten minutes unless forced. Returns what to tell the user when
    /// the store can't be reached: the index still answers from what it has.
    @discardableResult
    func refresh(_ context: Context, index: HistoryIndex, force: Bool) -> String? {
        guard let store = context.store else { return nil }
        let stamp = paths.historyFolder(for: context.repo).appendingPathComponent("synced")
        if !force, let modified = (try? FileManager.default.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 600 {
            return nil
        }
        do {
            _ = try HistorySync().sync(repo: context.repo, store: store, index: index)
            try? Data().write(to: stamp)
            return nil
        } catch {
            return "Couldn't reach the history store, so this is from what was fetched before. (\(error))"
        }
    }

    /// A chat's full record: from the store, else from the copy kept the last time it was fetched.
    func chat(_ session: IndexedSession, in context: Context) -> ChatRecord? {
        let cache = paths.historyFolder(for: context.repo).appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent(Self.fileName(for: session) + ".json")
        if let store = context.store, let data = try? store.get(session.folder + HistoryKeys.chat),
           let record = try? HistoryCoding.decode(ChatRecord.self, from: data) {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cache, options: .atomic)
            return record
        }
        return (try? Data(contentsOf: cache)).flatMap { try? HistoryCoding.decode(ChatRecord.self, from: $0) }
    }

    /// A name for a chat's local copies. The id comes from the shared store, which anyone on the team can write to,
    /// so it is never used as a path: slashes and dots can't take the file out of its folder.
    static func fileName(for session: IndexedSession) -> String {
        String(session.key.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "-" })
    }

    // MARK: - setup, status

    private func setup(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: ["--store", "--region", "--profile", "--repo"])
        var context = context()
        if let repo = options.values["--repo"] { context.repo = repo }
        guard context.root != nil || options.values["--repo"] != nil else {
            throw HistoryError.message("Run this inside the repository whose chats you want kept, or name it with --repo OWNER/NAME.")
        }
        guard let location = options.values["--store"] else {
            throw HistoryError.message("Say where to keep the chats: --store s3://BUCKET[/PREFIX], or a folder's path.")
        }
        var entry = HistoryConfig.Repo(store: location, region: options.values["--region"],
                                       profile: options.values["--profile"], postLinks: !options.flags.contains("--no-links"))
        if let s3 = S3Store.parse(location) {
            if entry.region == nil {
                // us-east-1 answers with no constraint at all.
                var arguments = ["s3api", "get-bucket-location", "--bucket", s3.bucket, "--query", "LocationConstraint", "--output", "text"]
                if let profile = entry.profile { arguments += ["--profile", profile] }
                let output = shell("aws", arguments)
                guard output.succeeded else {
                    throw HistoryError.message("Couldn't find the bucket's region (\(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))). "
                        + "Sign in with `aws login` or `aws sso login`, or pass --region.")
                }
                let region = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.region = region.isEmpty || region == "None" || region == "null" ? "us-east-1" : region
            }
        } else {
            guard !location.hasPrefix("s3:") else { throw HistoryError.message("'\(location)' isn't a bucket address. Use s3://BUCKET or s3://BUCKET/PREFIX.") }
            entry.store = Commands.absolute(location)
            entry.postLinks = false
        }
        var config = context.config
        entry.since = config.repos[context.repo]?.since ?? Date()
        config.repos[context.repo] = entry
        guard let store = config.store(for: context.repo, shell: shell) else {
            throw HistoryError.message("That store can't be used.")
        }
        // Proves the store is reachable and writable before anything depends on it.
        let probe = HistoryKeys.repoPrefix(context.repo) + ".ambient-setup"
        try store.put(Data("ambient history\n".utf8), key: probe, contentType: "text/plain")
        _ = try store.list(prefix: HistoryKeys.repoPrefix(context.repo))
        try config.save(to: paths.historyConfig)
        out.success("\(context.repo): finished chats will be kept in \(entry.store)\(entry.region.map { " (\($0))" } ?? "").")
        out.note("A chat is stored when its session ends, or once it has been quiet for \(Int(config.idleHours)) hours.")
        out.note("Chats that finished before now stay on this Mac; `ambient history capture --due --since DAYS` stores those too.")
        out.note(entry.postLinks ? "Each chat's link is left on the pull requests that hold its commits."
            : "No links are left on pull requests.")
        // Said without looking for the key: reading the Keychain here could stop setup on a permission dialog.
        out.note("With a Claude API key (ANTHROPIC_API_KEY, or the one Ambient keeps in the Keychain), \(config.cardModel) "
            + "writes the cards and \(config.answerModel) the deep answers; without one, cards come from the chats' own words.")
        return 0
    }

    private func status() throws -> Int32 {
        let context = context()
        let config = context.config
        if config.repos.isEmpty {
            out.skip("History isn't set up for any repository. Run `ambient history setup --store …` in one.")
            return 0
        }
        for (repo, entry) in config.repos.sorted(by: { $0.key < $1.key }) {
            let counts = try? HistoryIndex(path: paths.historyIndex(for: repo).path).counts()
            out.line(repo == context.repo ? "●" : "○", "\(out.bold(repo)) → \(entry.store)"
                + (counts.map { "  \(out.dim("\($0.chats) chats, \($0.cards) cards indexed here"))" } ?? ""))
        }
        let pipeline = HistoryPipeline(paths: paths, config: config, shell: shell)
        let due = pipeline.due()
        out.note(due.isEmpty ? "Nothing is waiting to be captured."
            : "\(due.count) finished \(due.count == 1 ? "chat is" : "chats are") waiting: ambient history capture --due")
        return 0
    }

    // MARK: - capture, sync

    private func capture(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: ["--session", "--transcript", "--since"])
        let config = HistoryConfig.load(from: paths.historyConfig)
        let quiet = options.flags.contains("--quiet")
        if config.repos.isEmpty {
            if !quiet { out.skip("History isn't set up for any repository.") }
            return 0
        }
        let wantsModel = !options.flags.contains("--no-model") && config.useModel
        let model = wantsModel ? findModel(!quiet) : nil
        let pipeline = HistoryPipeline(paths: paths, config: config, shell: shell, model: model)
        let dryRun = options.flags.contains("--dry-run")
        var transcripts: [String] = []
        if let path = options.values["--transcript"] {
            transcripts = [Commands.absolute(path)]
        } else if let named = options.values["--session"] {
            let parts = named.split(separator: ":", maxSplits: 1).map(String.init)
            let (agent, id) = parts.count == 2 ? (parts[0], parts[1]) : ("claude", named)
            guard agent == "claude" else {
                if !quiet { out.skip("Only Claude chats can be captured so far; \(agent) isn't read yet.") }
                return 0
            }
            guard let path = ClaudeTranscript.find(sessionID: id, home: paths.userHome.path) else {
                if quiet { return 0 }
                throw HistoryError.message("No Claude transcript for session \(id) on this Mac.")
            }
            transcripts = [path]
        } else if options.flags.contains("--due") {
            var lookback: Double?
            if let days = options.values["--since"] {
                guard let number = Double(days), number > 0 else { throw HistoryError.message("--since takes a number of days.") }
                lookback = number
            }
            transcripts = pipeline.due(lookbackDays: lookback).map(\.file.path)
            if transcripts.isEmpty, !quiet { out.skip("Nothing is waiting to be captured.") }
        } else {
            throw HistoryError.message("Say which chat: --session ID, --transcript PATH, or --due for every finished one.")
        }
        var failed = false
        for path in transcripts {
            do {
                switch try pipeline.capture(transcript: path, dryRun: dryRun, postLinks: !options.flags.contains("--no-links")) {
                case let .skipped(reason):
                    if !quiet { out.skip("\((path as NSString).lastPathComponent): \(reason)") }
                case let .stored(stored):
                    let title = stored.session.title ?? stored.session.id
                    let changed = stored.cards.filter { !$0.files.isEmpty }.count
                    out.success("\(dryRun ? "Would store" : "Stored") \"\(title)\": \(stored.events) events, "
                        + "\(stored.cards.count) requests (\(changed) changed code), \(stored.commits) commits")
                    if let url = stored.url { out.note(url) }
                    if !stored.pullRequests.isEmpty {
                        out.note("Linked on pull request\(stored.pullRequests.count == 1 ? "" : "s") "
                            + stored.pullRequests.map { "#\($0)" }.joined(separator: ", "))
                    }
                    stored.notes.forEach { out.warn($0) }
                    if quiet, wantsModel, model == nil {
                        out.note("If the key is in the Keychain, macOS needs your permission once: run "
                            + "`ambient history capture --session \(stored.session.id)` in a terminal and choose Always Allow.")
                    }
                }
            } catch {
                failed = true
                out.error("\((path as NSString).lastPathComponent): \(error)")
            }
        }
        return failed ? 1 : 0
    }

    private func sync() throws -> Int32 {
        let context = context()
        guard let store = context.store else { throw notSetUp(context) }
        let index = try index(for: context)
        let result = try HistorySync().sync(repo: context.repo, store: store, index: index)
        try? Data().write(to: paths.historyFolder(for: context.repo).appendingPathComponent("synced"))
        let counts = try index.counts()
        out.success("\(context.repo): \(result.added) new or changed, \(result.removed) removed; "
            + "\(counts.chats) chats and \(counts.cards) cards indexed.")
        if result.unreadable > 0 { out.warn("\(result.unreadable) couldn't be read (written by a newer Ambient?).") }
        return 0
    }

    // MARK: - why

    /// "PATH" or "PATH:LINE", made relative to the repository.
    func fileArgument(_ argument: String, in context: Context) -> (path: String, line: Int?) {
        var path = argument
        var line: Int?
        if let colon = argument.lastIndex(of: ":"), let number = Int(argument[argument.index(after: colon)...]), number > 0 {
            path = String(argument[..<colon])
            line = number
        }
        let finder = PathFinder(roots: context.root.map { [$0] } ?? [], home: paths.userHome.path, known: [])
        return (finder.relative(path, from: folder), line)
    }

    func whyReport(_ argument: String, in context: Context, sync: Bool) throws -> (report: WhyReport, note: String?) {
        guard context.config.repos[context.repo] != nil else { throw notSetUp(context) }
        let index = try index(for: context)
        let note = sync ? refresh(context, index: index, force: false) : nil
        let (path, line) = fileArgument(argument, in: context)
        let query = HistoryQuery(index: index, git: GitFacts(shell: shell), root: context.root)
        return (try query.why(path: path, line: line), note)
    }

    private func why(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: [])
        guard let argument = options.rest.first else { throw HistoryError.message("Say which file: ambient history why PATH[:LINE]") }
        let context = context()
        let (report, note) = try whyReport(argument, in: context, sync: !options.flags.contains("--no-sync"))
        if options.flags.contains("--json") {
            printJSON(Self.json(report))
            return 0
        }
        print(Self.text(report, all: options.flags.contains("--all"), terminal: out))
        if let note { out.warn(note) }
        return 0
    }

    static func day(_ date: Date) -> String { String(HistoryPage.stamp(date).prefix(10)) }

    static func heading(_ hit: IndexHit) -> String {
        let session = hit.chat.session
        var parts = [day(hit.card.at ?? session.startedAt), session.agent]
        if let developer = session.developer { parts.append(developer) }
        if let title = session.title { parts.append("\"\(title)\"") }
        return parts.joined(separator: " · ")
    }

    /// Where to read the request's part of the chat.
    static func pointer(_ hit: IndexHit) -> String {
        let events = "\(hit.card.firstEvent)-\(hit.card.lastEvent)"
        let command = "ambient history show \(hit.chat.session.id.prefix(8)) \(events)"
        guard let url = hit.chat.url, url.hasPrefix("https://") else { return command }
        return "\(url)  (\(command))"
    }

    static func text(_ report: WhyReport, all: Bool, terminal out: Terminal) -> String {
        var lines: [String] = []
        var counts = ["\(report.changes.count) recorded \(report.changes.count == 1 ? "change" : "changes")"]
        if !report.references.isEmpty { counts.append("\(report.references.count) other requests referred to it") }
        if !report.unexplained.isEmpty {
            counts.append("\(report.unexplained.count) \(report.unexplained.count == 1 ? "commit" : "commits") with no recorded chat")
        }
        lines.append(out.bold(report.path + (report.line.map { ":\($0)" } ?? "")))
        lines.append(out.dim(counts.joined(separator: " · ")))
        if let line = report.line {
            if let commit = report.blamedCommit {
                let explained = report.changes.contains { $0.blamed }
                lines.append("Line \(line) was last changed by \(commit.sha.prefix(7)) (\(commit.subject))"
                    + (explained ? ", marked ◆ below." : ", which no recorded chat made."))
            } else {
                lines.append("Line \(line) isn't in a commit yet, or the file isn't in this checkout.")
            }
        }
        func field(_ name: String, _ value: String) {
            guard !value.isEmpty else { return }
            let label = name.padding(toLength: 9, withPad: " ", startingAt: 0)
            let body = value.split(separator: "\n", omittingEmptySubsequences: true).joined(separator: "\n            ")
            lines.append("  \(out.dim(label)) \(body)")
        }
        for change in report.changes {
            let card = change.hit.card
            lines.append("")
            lines.append("\(change.blamed ? "◆" : "●") \(out.bold(heading(change.hit)))")
            field("Asked", Episodes.clip(card.request, 400))
            field("Did", card.brief)
            field("Why", card.why)
            field("Rejected", card.rejected)
            field("Checked", card.verified)
            if change.commits.isEmpty {
                field("Commit", card.landed == .committed ? card.commits.map { String($0.prefix(7)) }.joined(separator: ", ")
                    : "none by this chat" + (change.hit.how == .shell ? " (changed by a shell command)" : ""))
            } else {
                field("Commit", change.commits.map { "\($0.sha.prefix(7)) \($0.subject)" }.joined(separator: "\n"))
            }
            field("Chat", pointer(change.hit))
        }
        if !report.unexplained.isEmpty {
            lines.append("")
            lines.append(out.bold("Commits with no recorded chat"))
            for commit in report.unexplained.prefix(all ? 200 : 8) {
                lines.append("  \(commit.sha.prefix(7)) \(day(commit.at)) \(commit.author)  \(commit.subject)")
            }
            if !all, report.unexplained.count > 8 { lines.append(out.dim("  … \(report.unexplained.count - 8) more (--all)")) }
        }
        if !report.references.isEmpty {
            lines.append("")
            lines.append(out.bold("Requests that read or mentioned it"))
            for hit in report.references.prefix(all ? 200 : 5) {
                lines.append("  \(heading(hit))")
                lines.append("    \(out.dim(Episodes.clip(hit.card.request.replacingOccurrences(of: "\n", with: " "), 140)))")
            }
            if !all, report.references.count > 5 { lines.append(out.dim("  … \(report.references.count - 5) more (--all)")) }
        }
        if report.changes.isEmpty, report.references.isEmpty, report.unexplained.isEmpty {
            lines.append("No recorded chat touched this file, and git has no history for it here.")
        }
        return lines.joined(separator: "\n")
    }

    static func json(_ hit: IndexHit) -> [String: Any] {
        let card = hit.card
        let session = hit.chat.session
        var object: [String: Any] = [
            "session": session.id, "agent": session.agent, "episode": card.episode,
            "events": [card.firstEvent, card.lastEvent], "request": card.request, "summary": card.summary,
            "why": card.why, "rejected": card.rejected, "verified": card.verified, "files": card.files,
            "commits": card.commits, "landed": card.landed.rawValue, "evidence": card.evidence, "source": card.source,
            "at": ISO8601DateFormatter().string(from: card.at ?? session.startedAt),
        ]
        object["title"] = session.title
        object["developer"] = session.developer
        object["url"] = hit.chat.url
        object["how"] = hit.how?.rawValue
        return object
    }

    static func json(_ commit: FileCommit) -> [String: Any] {
        ["sha": commit.sha, "subject": commit.subject, "author": commit.author,
         "at": ISO8601DateFormatter().string(from: commit.at)]
    }

    static func json(_ report: WhyReport) -> [String: Any] {
        var object: [String: Any] = [
            "path": report.path,
            "changes": report.changes.map { change -> [String: Any] in
                var item = json(change.hit)
                item["fileCommits"] = change.commits.map(json)
                item["blamed"] = change.blamed
                return item
            },
            "references": report.references.map(json),
            "commitsWithoutChat": report.unexplained.map(json),
        ]
        object["line"] = report.line
        object["blamedCommit"] = report.blamedCommit.map(json)
        return object
    }

    private func printJSON(_ object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    }

    // MARK: - ask

    func answer(_ question: String, files: [String], deep: Bool, useModel: Bool, sync: Bool,
                in context: Context) throws -> (answer: HistoryAnswer, note: String?) {
        guard context.config.repos[context.repo] != nil else { throw notSetUp(context) }
        let index = try index(for: context)
        let note = sync ? refresh(context, index: index, force: false) : nil
        let query = HistoryQuery(index: index, git: GitFacts(shell: shell), root: context.root)
        let model = useModel && context.config.useModel ? findModel(true) : nil
        var config = context.config
        if !useModel { config.useModel = false }
        let answerer = HistoryAnswerer(query: query, config: config, model: model) { chat($0, in: context) }
        let relative = files.map { fileArgument($0, in: context).path }
        return (try answerer.ask(question, files: relative, deep: deep), note)
    }

    private func ask(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: ["--file"])
        let question = options.rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw HistoryError.message("Ask something: ambient history ask \"why does …\"") }
        let context = context()
        let (answer, note) = try answer(question, files: options.values["--file"].map { [$0] } ?? [],
                                        deep: options.flags.contains("--deep"),
                                        useModel: !options.flags.contains("--no-model"),
                                        sync: !options.flags.contains("--no-sync"), in: context)
        if options.flags.contains("--json") {
            var object: [String: Any] = ["answer": answer.text, "depth": answer.depth.rawValue,
                                         "sources": answer.sources.map(Self.json)]
            object["note"] = answer.note
            printJSON(object)
            return 0
        }
        print(answer.text)
        if answer.depth != .cards, !answer.sources.isEmpty {
            print("")
            print(out.bold("Sources"))
            for hit in answer.sources {
                print("  \(Self.heading(hit))")
                print("    \(out.dim(Self.pointer(hit)))")
            }
        }
        if let text = answer.note { out.note(text) }
        if let note { out.warn(note) }
        return 0
    }

    // MARK: - show, open

    func session(named name: String, in context: Context, index: HistoryIndex) throws -> IndexedSession {
        guard let session = try index.session(matching: name) else {
            throw HistoryError.message("No one stored chat's id starts with '\(name)'. `ambient history sync` fetches new ones.")
        }
        return session
    }

    /// A stored chat's events as plain text; `range` narrows it to some.
    func transcript(_ name: String, range: ClosedRange<Int>?, in context: Context) throws -> String {
        guard context.config.repos[context.repo] != nil else { throw notSetUp(context) }
        let index = try index(for: context)
        let session = try session(named: name, in: context, index: index)
        guard let record = chat(session, in: context) else {
            throw HistoryError.message("The chat couldn't be fetched from the store.")
        }
        let events = record.events.filter { range?.contains($0.n) ?? true }
        return events.map { CardWriter.line(for: $0, scale: range == nil ? 0.5 : 4) }.joined(separator: "\n")
    }

    private func show(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: [])
        guard let name = options.rest.first else { throw HistoryError.message("Say which chat: ambient history show SESSION [FROM-TO]") }
        var range: ClosedRange<Int>?
        if options.rest.count > 1 {
            let bounds = options.rest[1].split(separator: "-").compactMap { Int($0) }
            guard let first = bounds.first, let last = bounds.last, first >= 1, first <= last else {
                throw HistoryError.message("Events are given as FROM-TO, like 12-40.")
            }
            range = first...last
        }
        print(try transcript(name, range: range, in: context()))
        return 0
    }

    private func open(_ args: [String]) throws -> Int32 {
        guard let name = args.first else { throw HistoryError.message("Say which chat: ambient history open SESSION") }
        let context = context()
        guard let store = context.store else { throw notSetUp(context) }
        let index = try index(for: context)
        let session = try session(named: name, in: context, index: index)
        guard let data = try store.get(session.folder + HistoryKeys.page) else {
            throw HistoryError.message("That chat's page isn't in the store.")
        }
        let file = paths.historyFolder(for: context.repo).appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent(Self.fileName(for: session) + ".html")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        _ = shell("open", [file.path])
        out.success("Opened \(file.path)")
        return 0
    }

    // MARK: - eval

    private func eval(_ args: [String]) throws -> Int32 {
        let options = try Arguments(args, valued: [])
        guard let path = options.rest.first, let data = FileManager.default.contents(atPath: Commands.absolute(path)) else {
            throw HistoryError.message("Give a questions file: ambient history eval FILE [--answers]")
        }
        let questions = try HistoryEval.load(data)
        let context = context()
        guard context.config.repos[context.repo] != nil else { throw notSetUp(context) }
        let index = try index(for: context)
        if let note = refresh(context, index: index, force: true) { out.warn(note) }
        let query = HistoryQuery(index: index, git: GitFacts(shell: shell), root: context.root)
        let withAnswers = options.flags.contains("--answers")
        let model = withAnswers ? findModel(true) : nil
        if withAnswers, model == nil { throw HistoryError.message("--answers needs a Claude API key.") }
        let answerer = HistoryAnswerer(query: query, config: context.config, model: model) { chat($0, in: context) }
        var results: [HistoryEval.Result] = []
        for question in questions {
            let hits = try query.retrieve(question.ask, files: question.file.map { [$0] } ?? [])
            var result = HistoryEval.Result(question: question, found: HistoryEval.found(question, in: hits), answered: nil, depth: nil)
            if withAnswers {
                let answer = try answerer.ask(question.ask, files: question.file.map { [$0] } ?? [])
                result.answered = HistoryEval.answered(question, by: answer.text)
                result.depth = answer.depth
            }
            results.append(result)
            let mark = result.found && result.answered != false ? "✓" : "✗"
            out.line(mark, "\(question.ask)" + (result.found ? "" : out.dim("  [not retrieved]"))
                + (result.answered == false ? out.dim("  [answer missed: \(question.expectWords.joined(separator: ", "))]") : "")
                + (result.depth.map { out.dim("  (\($0.rawValue))") } ?? ""))
        }
        let summary = HistoryEval.summary(results)
        print("")
        print(summary)
        return results.allSatisfy({ $0.found && $0.answered != false }) ? 0 : 1
    }
}
