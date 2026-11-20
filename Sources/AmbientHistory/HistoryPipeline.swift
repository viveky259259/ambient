import AmbientBase
import Foundation

/// Takes a finished chat from the agent's transcript to the team's store: record, cards, page, index, link.
public struct HistoryPipeline: Sendable {
    public var paths: AmbientPaths
    public var config: HistoryConfig
    public var shell: Shell
    /// Writes cards when the settings allow it; nil leaves them to the chat's own words.
    public var model: (any TextModel)?
    public var now: @Sendable () -> Date

    public init(paths: AmbientPaths, config: HistoryConfig, shell: Shell = .system, model: (any TextModel)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.config = config
        self.shell = shell
        self.model = model
        self.now = now
    }

    public enum Outcome: Sendable {
        case stored(Stored)
        /// Not captured, and why: its repository isn't set up, or the chat is empty.
        case skipped(String)
    }

    public struct Stored: Sendable {
        public var session: ChatSession
        public var folder: String
        public var url: String?
        public var events: Int
        public var cards: [ChangeCard]
        public var commits: Int
        public var pullRequests: [Int]
        /// Things that didn't stop the capture but are worth saying.
        public var notes: [String]
    }

    private var home: String { paths.userHome.path }

    /// Captures one Claude chat from its transcript.
    /// - Parameter dryRun: do everything except write to the store, the index and GitHub.
    public func capture(transcript path: String, dryRun: Bool = false, postLinks: Bool = true) throws -> Outcome {
        let chat = try ClaudeTranscript.read(path: path)
        guard chat.events.contains(where: { $0.kind == .user || $0.kind == .agent }) else {
            return .skipped("the chat has nothing in it yet")
        }
        let capture = Capture(git: GitFacts(shell: shell), home: home)
        let place = capture.place(of: chat)
        guard let entry = config.repos[place.repo] else {
            return .skipped("\(place.repo) isn't set up for history (ambient history setup)")
        }
        guard let store = config.store(for: place.repo, shell: shell) else {
            return .skipped("\(place.repo)'s history store (\(entry.store)) can't be used; run ambient history setup again")
        }
        let record = capture.record(from: chat, now: now())
        var notes: [String] = []
        if place.root == nil {
            notes.append("The chat's folder is gone, so its commits and uncommitted changes couldn't be read from git.")
        }

        let writer = CardWriter(model: config.useModel ? model : nil, modelName: config.cardModel)
        let written = writer.cards(for: record)
        notes += written.failures.map { "The model couldn't write a card (\($0)); the chat's own words were used." }
        if config.useModel, model == nil {
            notes.append("No Claude API key was found, so cards come from the chat's own words.")
        }

        let folder = HistoryKeys.folder(for: record.session)
        let url = store.address(of: folder + HistoryKeys.page)
        let episodes = Episodes.split(record)
        let cardFile = CardFile(session: record.session, url: url, commits: record.commits,
                                touches: Episodes.touches(in: record, episodes: episodes), cards: written.cards)
        var stored = Stored(session: record.session, folder: folder, url: url, events: record.events.count,
                            cards: written.cards, commits: record.commits.count, pullRequests: [], notes: notes)
        if dryRun { return .stored(stored) }

        // The chat first and the cards last: a reader that syncs between the two never sees cards without a chat.
        try store.put(try HistoryCoding.encode(record), key: folder + HistoryKeys.chat, contentType: "application/json")
        try store.put(Data(HistoryPage.render(record, cards: written.cards).utf8), key: folder + HistoryKeys.page,
                      contentType: "text/html; charset=utf-8")
        let cardData = try HistoryCoding.encode(cardFile)
        try store.put(cardData, key: folder + HistoryKeys.cards, contentType: "application/json")

        // The local index learns about it now; its revision is fixed up by the next sync.
        let index = try HistoryIndex(path: paths.historyIndex(for: place.repo).path)
        try index.upsert(cardFile, folder: folder, revision: "local")

        var ledger = CaptureLedger.load(from: paths.historyLedger)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let modified = attributes[.modificationDate] as? Date, let size = (attributes[.size] as? NSNumber)?.intValue {
            ledger.captured["\(chat.agent):\(chat.sessionID)"] = .init(size: size, modified: modified, capturedAt: now(),
                                                                       repo: place.repo, folder: folder)
            try ledger.save(to: paths.historyLedger)
        }

        if postLinks, entry.postLinks, let url, url.hasPrefix("https://") {
            let links = PullRequestLinks(shell: shell)
            let numbers = links.pullRequests(for: record, recorded: chat.pullRequests)
            let changed = written.cards.filter { !$0.files.isEmpty }.count
            stored.pullRequests = links.post(for: record, url: url, changes: changed, to: numbers)
            if stored.pullRequests.count < numbers.count {
                stored.notes.append("Couldn't leave the link on every pull request (gh).")
            }
        }
        return .stored(stored)
    }

    /// A transcript that is due: where it is and which repository it belongs to.
    public struct Due: Equatable, Sendable {
        public var file: TranscriptFile
        public var repo: String
    }

    /// Claude chats that are finished and not yet captured: in a repository that is set up, changed since their last
    /// capture, and still for `idleHours`. A chat that went quiet before its repository was set up is left alone,
    /// so setting up doesn't upload a repository's past unasked; `lookbackDays` asks for that past, that far back.
    public func due(lookbackDays: Double? = nil) -> [Due] {
        guard !config.repos.isEmpty else { return [] }
        let ledger = CaptureLedger.load(from: paths.historyLedger)
        let git = GitFacts(shell: shell)
        let current = now()
        var slugs: [String: String?] = [:]
        var due: [Due] = []
        for file in ClaudeTranscript.all(home: home) {
            let quiet = current.timeIntervalSince(file.modified)
            guard quiet >= config.idleHours * 3600, quiet <= (lookbackDays ?? 30) * 86_400, file.size > 0,
                  ledger.isStale(file, agent: "claude"), let folder = Self.folder(ofTranscript: file.path) else { continue }
            if slugs[folder] == nil {
                slugs[folder] = .some(git.root(of: folder).map { git.slug(of: $0) ?? Capture.folderName($0) })
            }
            guard let repo = slugs[folder] ?? nil, let entry = config.repos[repo] else { continue }
            if lookbackDays == nil, let since = entry.since, file.modified < since { continue }
            due.append(Due(file: file, repo: repo))
        }
        return due
    }

    /// The folder a transcript's chat ran in, read from its first lines without parsing the whole file.
    static func folder(ofTranscript path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 256_000)) ?? Data(), as: UTF8.self)
        guard let range = head.range(of: "\"cwd\":\"") else { return nil }
        var folder = ""
        var escaped = false
        for character in head[range.upperBound...] {
            if escaped { folder.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" { return folder.isEmpty ? nil : folder }
            folder.append(character)
        }
        return nil
    }
}

/// Brings this machine's index up to date with the store: reads the cards of chats it hasn't seen, or that were
/// captured again, and forgets chats that are gone from the store.
public struct HistorySync: Sendable {
    public struct Result: Equatable, Sendable {
        public var added = 0
        public var removed = 0
        public var unreadable = 0
    }

    public init() {}

    public func sync(repo: String, store: any HistoryStore, index: HistoryIndex) throws -> Result {
        var result = Result()
        let listed = try store.list(prefix: HistoryKeys.repoPrefix(repo))
            .filter { $0.key.hasSuffix("/" + HistoryKeys.cards) }
        let known = try index.revisions()
        var present = Set<String>()
        for object in listed {
            let folder = String(object.key.dropLast(HistoryKeys.cards.count))
            present.insert(folder)
            if known[folder]?.revision == object.revision { continue }
            guard let data = try store.get(object.key),
                  let file = try? HistoryCoding.decode(CardFile.self, from: data),
                  file.version <= CardFile.currentVersion else {
                result.unreadable += 1
                continue
            }
            try index.upsert(file, folder: folder, revision: object.revision)
            result.added += 1
        }
        // A listing with nothing in it, when chats were there before, is far more likely a store that is empty for
        // the wrong reason (a share mounted as an empty folder, a prefix typed differently) than every chat deleted.
        // So chats are forgotten one by one as they go, never all at once.
        guard !present.isEmpty || known.isEmpty else { return result }
        for (folder, entry) in known where !present.contains(folder) {
            try index.remove(sessionKey: entry.key)
            result.removed += 1
        }
        return result
    }
}
