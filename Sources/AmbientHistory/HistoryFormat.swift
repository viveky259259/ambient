import Foundation

// The two files Ambient stores for a finished agent chat. Both are read long after they were written, by other
// people's copies of Ambient, so each carries a version and has golden fixtures in Tests/AmbientHistoryTests/Fixtures.

/// Who and what a chat was: enough to find it again and to say whose it is.
public struct ChatSession: Codable, Equatable, Sendable {
    /// The agent's own id for the session.
    public var id: String
    /// `AgentKind`'s raw value: "claude", "codex"…
    public var agent: String
    /// The repository the chat worked in, as "owner/name", or the folder's name when it has no GitHub remote.
    public var repo: String
    public var branch: String?
    /// `git config user.name` on the machine the chat ran on.
    public var developer: String?
    public var title: String?
    public var startedAt: Date
    public var endedAt: Date

    public init(id: String, agent: String, repo: String, branch: String? = nil, developer: String? = nil,
                title: String? = nil, startedAt: Date, endedAt: Date) {
        self.id = id
        self.agent = agent
        self.repo = repo
        self.branch = branch
        self.developer = developer
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// A commit the chat made.
public struct ChatCommit: Codable, Equatable, Sendable {
    public var sha: String
    public var subject: String
    public var at: Date
    /// Paths relative to the repository's root.
    public var files: [String]
    /// The number of the tool event whose command made it.
    public var event: Int?

    public init(sha: String, subject: String, at: Date, files: [String], event: Int? = nil) {
        self.sha = sha
        self.subject = subject
        self.at = at
        self.files = files
        self.event = event
    }
}

/// One file a chat event had to do with.
public struct FileTouch: Codable, Equatable, Hashable, Sendable {
    public enum How: String, Codable, Sendable, CaseIterable {
        /// Changed through the agent's edit tool: the event holds the exact diff.
        case edit
        /// Written whole through the agent's write tool: the event holds the content.
        case write
        /// Named by a shell command that writes files. The command is known; the resulting diff is not.
        case shell
        /// Read by a tool, or named by a shell command that only reads.
        case read
        /// Named in what the user or the agent said.
        case mention

        /// True for the three that change the file.
        public var changes: Bool { self == .edit || self == .write || self == .shell }
    }

    /// Relative to the repository's root; a path outside it starts with `~/` or `/`.
    public var path: String
    public var how: How

    public init(path: String, how: How) {
        self.path = path
        self.how = how
    }
}

/// One thing that happened in a chat, in order.
public struct ChatEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// What the person typed.
        case user
        /// Text the agent's harness put in the conversation: a subagent's report, a CI notice, a context summary.
        case system
        /// What the agent said.
        case agent
        case thinking
        /// A tool call. `text` is the command, the path or the arguments.
        case tool
        /// What a tool call returned. `of` names the call.
        case result
    }

    /// 1-based and stable: cards and links point at events by this number.
    public var n: Int
    public var at: Date?
    public var kind: Kind
    /// The subagent that said or did it; nil for the main agent and the user.
    public var actor: String?
    public var text: String
    /// The tool's name, for `.tool`.
    public var tool: String?
    /// What the agent said the command was for, when the tool takes a description.
    public var label: String?
    /// For an edit, unified-diff hunks; for a write, the file with every line marked `+`.
    public var diff: String?
    public var touches: [FileTouch]?
    /// The tool call this is the result of.
    public var of: Int?
    /// True for a result the tool reported as an error.
    public var failed: Bool?
    /// Characters left out of `text` or `diff` to keep the record small.
    public var cut: Int?

    public init(n: Int, at: Date? = nil, kind: Kind, actor: String? = nil, text: String, tool: String? = nil,
                label: String? = nil, diff: String? = nil, touches: [FileTouch]? = nil, of: Int? = nil,
                failed: Bool? = nil, cut: Int? = nil) {
        self.n = n
        self.at = at
        self.kind = kind
        self.actor = actor
        self.text = text
        self.tool = tool
        self.label = label
        self.diff = diff
        self.touches = touches
        self.of = of
        self.failed = failed
        self.cut = cut
    }
}

/// `chat.json`: a whole chat in Ambient's own shape, whichever agent it came from.
public struct ChatRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var session: ChatSession
    public var commits: [ChatCommit]
    /// What the files this chat touched still differed from `HEAD` by when it was captured: work it never committed.
    public var uncommitted: String?
    public var events: [ChatEvent]

    public init(session: ChatSession, commits: [ChatCommit] = [], uncommitted: String? = nil, events: [ChatEvent]) {
        self.version = Self.currentVersion
        self.session = session
        self.commits = commits
        self.uncommitted = uncommitted
        self.events = events
    }
}

/// What one request in a chat came to: the unit an answer is built from.
public struct ChangeCard: Codable, Equatable, Sendable {
    public enum Landed: String, Codable, Sendable {
        /// Its changes are in a commit the chat made.
        case committed
        /// It changed files, and no commit by this chat holds them.
        case uncommitted
        /// It changed no files.
        case none
    }

    /// 1-based, in the order the requests were made.
    public var episode: Int
    public var firstEvent: Int
    public var lastEvent: Int
    public var at: Date?
    /// What the person asked for, in their words.
    public var request: String
    public var summary: String
    public var why: String
    /// What was considered and not done.
    public var rejected: String
    /// How the result was checked.
    public var verified: String
    /// The files it changed.
    public var files: [String]
    public var commits: [String]
    public var landed: Landed
    /// Events that back the card's statements.
    public var evidence: [Int]
    /// "extract" for a card taken from the chat's own words; otherwise the model that wrote it.
    public var source: String

    public init(episode: Int, firstEvent: Int, lastEvent: Int, at: Date? = nil, request: String, summary: String,
                why: String = "", rejected: String = "", verified: String = "", files: [String] = [],
                commits: [String] = [], landed: Landed = .none, evidence: [Int] = [], source: String = "extract") {
        self.episode = episode
        self.firstEvent = firstEvent
        self.lastEvent = lastEvent
        self.at = at
        self.request = request
        self.summary = summary
        self.why = why
        self.rejected = rejected
        self.verified = verified
        self.files = files
        self.commits = commits
        self.landed = landed
        self.evidence = evidence
        self.source = source
    }
}

extension ChangeCard {
    /// The summary as shown in a list. A card taken from the chat's own words holds the agent's whole closing
    /// message, so only its opening paragraph is shown; a model's summary is already short.
    public var brief: String {
        guard source == "extract" else { return summary }
        let opening = summary.components(separatedBy: "\n\n").first ?? summary
        return Episodes.clip(opening, 500)
    }
}

/// A file touch placed in its chat: which request, which event.
public struct PlacedTouch: Codable, Equatable, Sendable {
    public var path: String
    public var how: FileTouch.How
    public var episode: Int
    public var event: Int

    public init(path: String, how: FileTouch.How, episode: Int, event: Int) {
        self.path = path
        self.how = how
        self.episode = episode
        self.event = event
    }
}

/// `cards.json`: everything the index needs about a chat, without the chat itself.
public struct CardFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var session: ChatSession
    /// Where the chat can be read, when the store has an address for it.
    public var url: String?
    public var commits: [ChatCommit]
    public var touches: [PlacedTouch]
    public var cards: [ChangeCard]

    public init(session: ChatSession, url: String? = nil, commits: [ChatCommit] = [], touches: [PlacedTouch] = [],
                cards: [ChangeCard]) {
        self.version = Self.currentVersion
        self.session = session
        self.url = url
        self.commits = commits
        self.touches = touches
        self.cards = cards
    }
}

/// How both files are written and read: seconds-precision ISO dates and sorted keys, so the same chat always makes the
/// same bytes.
public enum HistoryCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public enum HistoryError: Error, Equatable, CustomStringConvertible {
    case message(String)
    /// The model's API turned the key down. Asking again with the same key can only fail the same way.
    case keyRejected(String)

    public var description: String {
        switch self {
        case let .message(text): text
        case let .keyRejected(text): text
        }
    }
}
