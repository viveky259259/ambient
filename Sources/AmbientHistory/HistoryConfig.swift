import AmbientBase
import Foundation

/// `~/.ambient/history.json`: which repositories' chats are kept, and where. A repository that isn't listed is never
/// captured, so chats about anything else stay on the machine.
public struct HistoryConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Repo: Codable, Equatable, Sendable {
        /// `s3://bucket/prefix`, or a folder's absolute path.
        public var store: String
        public var region: String?
        /// The `aws` profile to use; nil for the default one.
        public var profile: String?
        /// Whether to leave a link to each chat on the pull requests that hold its commits.
        public var postLinks: Bool
        /// When the repository was set up. Chats that went quiet before then are left alone unless asked for, so
        /// setting up never uploads a repository's past by itself.
        public var since: Date?

        public init(store: String, region: String? = nil, profile: String? = nil, postLinks: Bool = true,
                    since: Date? = nil) {
            self.store = store
            self.region = region
            self.profile = profile
            self.postLinks = postLinks
            self.since = since
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            store = try values.decode(String.self, forKey: .store)
            region = try values.decodeIfPresent(String.self, forKey: .region)
            profile = try values.decodeIfPresent(String.self, forKey: .profile)
            postLinks = try values.decodeIfPresent(Bool.self, forKey: .postLinks) ?? true
            since = try values.decodeIfPresent(Date.self, forKey: .since)
        }
    }

    public var version: Int
    /// By "owner/name".
    public var repos: [String: Repo]
    /// A chat that hasn't said it ended counts as finished once its transcript has been still this long.
    public var idleHours: Double
    /// Whether a model writes the cards and the answers. Off, cards come from the chats' own words.
    public var useModel: Bool
    public var cardModel: String
    public var answerModel: String

    public init(repos: [String: Repo] = [:], idleHours: Double = 24, useModel: Bool = true,
                cardModel: String = "claude-haiku-5-5", answerModel: String = "claude-opus-5-5") {
        version = Self.currentVersion
        self.repos = repos
        self.idleHours = idleHours
        self.useModel = useModel
        self.cardModel = cardModel
        self.answerModel = answerModel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HistoryConfig()
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        repos = try values.decodeIfPresent([String: Repo].self, forKey: .repos) ?? [:]
        idleHours = try values.decodeIfPresent(Double.self, forKey: .idleHours) ?? defaults.idleHours
        useModel = try values.decodeIfPresent(Bool.self, forKey: .useModel) ?? defaults.useModel
        cardModel = try values.decodeIfPresent(String.self, forKey: .cardModel) ?? defaults.cardModel
        answerModel = try values.decodeIfPresent(String.self, forKey: .answerModel) ?? defaults.answerModel
    }

    public static func load(from url: URL) -> HistoryConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let config = try? decoder.decode(HistoryConfig.self, from: data) else { return HistoryConfig() }
        return config
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try encoder.encode(self).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// The store a repository's chats go to; nil when the repository isn't set up or its entry is unusable.
    public func store(for repo: String, shell: Shell = .system) -> (any HistoryStore)? {
        guard let entry = repos[repo] else { return nil }
        if let s3 = S3Store.parse(entry.store) {
            guard let region = entry.region, !region.isEmpty else { return nil }
            return S3Store(bucket: s3.bucket, prefix: s3.prefix, region: region, profile: entry.profile, shell: shell)
        }
        guard entry.store.hasPrefix("/") else { return nil }
        return FolderStore(root: entry.store)
    }
}

extension AmbientPaths {
    public var historyConfig: URL { home.appendingPathComponent("history.json") }
    /// What history keeps on this machine: each repository's index, chats it has fetched, and what it has captured.
    public var historyHome: URL { home.appendingPathComponent("history", isDirectory: true) }
    public var historyLedger: URL { historyHome.appendingPathComponent("captured.json") }

    public func historyFolder(for repo: String) -> URL {
        historyHome.appendingPathComponent(HistoryKeys.clean(repo).replacingOccurrences(of: "/", with: "__"),
                                           isDirectory: true)
    }

    public func historyIndex(for repo: String) -> URL {
        historyFolder(for: repo).appendingPathComponent("index.sqlite")
    }
}

/// Which transcripts have been captured, and as of what size and time, so a chat is captured again only when it has
/// grown.
public struct CaptureLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var size: Int
        public var modified: Date
        public var capturedAt: Date
        public var repo: String
        /// Where its files are in the store.
        public var folder: String
    }

    /// By "agent:session".
    public var captured: [String: Entry] = [:]

    public init() {}

    public static func load(from url: URL) -> CaptureLedger {
        guard let data = try? Data(contentsOf: url),
              let ledger = try? HistoryCoding.decode(CaptureLedger.self, from: data) else { return CaptureLedger() }
        return ledger
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try HistoryCoding.encode(self).write(to: url, options: .atomic)
    }

    /// True when the transcript holds something the last capture didn't.
    public func isStale(_ file: TranscriptFile, agent: String) -> Bool {
        guard let entry = captured["\(agent):\(file.sessionID)"] else { return true }
        return entry.size != file.size || abs(entry.modified.timeIntervalSince(file.modified)) >= 1
    }
}
