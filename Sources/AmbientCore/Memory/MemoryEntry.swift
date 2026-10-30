import Foundation

/// Who can see a shared entry: the agents working in one project (worktrees included), or every agent on this Mac.
public enum MemoryScope: Codable, Equatable, Hashable, Sendable {
    /// Keyed by the project's root folder, from `MemoryProject.root(for:)`.
    case project(String)
    case global

    public var label: String {
        switch self {
        case let .project(root): URL(fileURLWithPath: root).lastPathComponent
        case .global: "global"
        }
    }

    /// Unique across projects, which `label` isn't: two projects can share a folder name.
    var id: String {
        switch self {
        case let .project(root): root
        case .global: "global"
        }
    }
}

/// A file shared through working memory: a copy in `~/.ambient/memory/`, addressed by its content.
public struct MemoryBlob: Codable, Equatable, Sendable {
    /// The file name it was shared under, which its copy keeps.
    public var name: String
    public var sha256: String
    public var size: Int

    public init(name: String, sha256: String, size: Int) {
        self.name = name
        self.sha256 = sha256
        self.size = size
    }
}

/// The agent session that wrote an entry, when Ambient could tell.
public struct MemoryAuthor: Codable, Equatable, Sendable {
    /// `Session.id` (`agent:sessionId`).
    public var sessionID: String
    public var agent: AgentKind
    /// What the island calls it, e.g. "Codex" or a custom agent's own name.
    public var label: String
    /// The agent's process, which outlives the island's interest in a session that's gone quiet.
    public var agentPid: Int32?

    public init(sessionID: String, agent: AgentKind, label: String, agentPid: Int32? = nil) {
        self.sessionID = sessionID
        self.agent = agent
        self.label = label
        self.agentPid = agentPid
    }

    public init?(callerPids: [Int32], sessions: [Session]) {
        guard let s = Session.calling(callerPids: callerPids, in: sessions) else { return nil }
        self.init(sessionID: s.id, agent: s.agent, label: s.agentLabel, agentPid: s.host?.agentPid)
    }
}

extension Session {
    /// The session whose agent process is the nearest of `callerPids`, the caller's parent chain. When one process
    /// has had several sessions (Claude's /clear), the most recent one.
    public static func calling(callerPids: [Int32], in sessions: [Session]) -> Session? {
        for pid in callerPids {
            let matches = sessions.filter { $0.host?.agentPid == pid }
            if let s = matches.max(by: { $0.lastEventAt < $1.lastEventAt }) { return s }
        }
        return nil
    }
}

/// One piece of shared working memory: text (often JSON) or a file, under a key other agents read it by.
public struct MemoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(scope.id)/\(key)" }
    public var key: String
    public var scope: MemoryScope
    /// Text or JSON. Nil for files, and in listings.
    public var value: String?
    public var file: MemoryBlob?
    /// What it is, for agents deciding whether to read it.
    public var description: String?
    /// The size of `value` in UTF-8 bytes, kept when listings leave the value out.
    public var size: Int
    public var author: MemoryAuthor?
    public var createdAt: Date
    public var updatedAt: Date
    /// Gone after this, unless written again.
    public var expiresAt: Date?
    /// Gone when the author's session ends or its agent exits.
    public var untilSessionEnds: Bool

    public init(key: String, scope: MemoryScope, value: String? = nil, file: MemoryBlob? = nil,
                description: String? = nil, author: MemoryAuthor? = nil, createdAt: Date = Date(),
                updatedAt: Date = Date(), expiresAt: Date? = nil, untilSessionEnds: Bool = false) {
        self.key = key
        self.scope = scope
        self.value = value
        self.file = file
        self.description = description
        self.size = file?.size ?? value?.utf8.count ?? 0
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.untilSessionEnds = untilSessionEnds
    }

    /// The entry without its value, for listings.
    public var summary: MemoryEntry {
        var copy = self
        copy.value = nil
        return copy
    }

    public func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }
}

/// A write from an agent: text or a file already copied into the blob store.
public struct MemoryWrite: Codable, Equatable, Sendable {
    public var key: String
    public var scope: MemoryScope
    public var value: String?
    public var file: MemoryBlob?
    public var description: String?
    /// Minutes until it expires; nil for the default.
    public var ttlMinutes: Int?
    public var untilSessionEnds: Bool

    public init(key: String, scope: MemoryScope, value: String? = nil, file: MemoryBlob? = nil,
                description: String? = nil, ttlMinutes: Int? = nil, untilSessionEnds: Bool = false) {
        self.key = key
        self.scope = scope
        self.value = value
        self.file = file
        self.description = description
        self.ttlMinutes = ttlMinutes
        self.untilSessionEnds = untilSessionEnds
    }
}

/// What the CLI and `ambient mcp` ask the app for. `callerPids` is the asking process's parent chain, nearest
/// first, which tells the app which agent session is asking.
public enum MemoryRequest: Codable, Equatable, Sendable {
    case write(MemoryWrite, callerPids: [Int32])
    /// One entry by key: the project's first, then global, unless `scope` says which.
    case read(key: String, project: String, scope: MemoryScope?)
    /// Entries without their values: the project's and global ones, or only `scope`'s.
    case list(project: String, scope: MemoryScope?)
    case forget(key: String, project: String, scope: MemoryScope?)
}

public enum MemoryReply: Codable, Equatable, Sendable {
    case entry(MemoryEntry)
    case entries([MemoryEntry])
    case forgotten(MemoryEntry)
    case failed(String)
}
