import Foundation

/// Why a memory request was turned down, in words an agent can act on.
public struct MemoryError: Error, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Shared working memory: text and files agents leave for each other, by project or for every agent.
/// Entries expire, and can end with the session that wrote them. Not thread-safe: own it from one queue.
public final class MemoryStore {
    public static let maxValueBytes = 32 * 1024
    public static let maxEntriesPerScope = 200
    public static let maxKeyLength = 80
    public static let maxDescriptionLength = 160
    /// Working memory, not an archive: entries last a week unless written again or given another time.
    public static let defaultTTLMinutes = 7 * 24 * 60
    public static let maxTTLMinutes = 30 * 24 * 60

    private struct Slot: Hashable {
        let scope: MemoryScope
        let key: String
    }

    private var bySlot: [Slot: MemoryEntry] = [:]
    /// Goes up with every change, so the owner knows when to save.
    public private(set) var revision = 0

    public init() {}

    /// Newest first.
    public var entries: [MemoryEntry] {
        bySlot.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public func load(_ entries: [MemoryEntry]) {
        bySlot = Dictionary(entries.map { (Slot(scope: $0.scope, key: $0.key), $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })
    }

    /// Adds or replaces the entry under the write's key and scope.
    @discardableResult
    public func write(_ w: MemoryWrite, author: MemoryAuthor?, now: Date = Date()) throws -> MemoryEntry {
        let key = w.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.problem(withKey: key) { throw MemoryError(problem) }
        switch (w.value, w.file) {
        case (nil, nil), (_?, _?):
            throw MemoryError("Share either text or a file.")
        case let (value?, nil):
            guard !value.isEmpty else { throw MemoryError("The value is empty. Use memory_forget to remove an entry.") }
            guard value.utf8.count <= Self.maxValueBytes else {
                throw MemoryError("The value is \(value.utf8.count / 1024) KB; text is limited to \(Self.maxValueBytes / 1024) KB. "
                    + "Share it as a file instead.")
            }
            if let problem = MemoryGuard.problem(withText: value) { throw MemoryError(problem) }
        case (nil, _?):
            break
        }
        if w.untilSessionEnds, author == nil {
            throw MemoryError("Ambient can't tell which session is asking, so it can't keep this only until the session "
                + "ends. Give it ttl_minutes instead.")
        }
        let minutes = w.ttlMinutes ?? Self.defaultTTLMinutes
        guard (1...Self.maxTTLMinutes).contains(minutes) else {
            throw MemoryError("ttl_minutes must be between 1 and \(Self.maxTTLMinutes) (30 days).")
        }

        let slot = Slot(scope: w.scope, key: key)
        let existing = bySlot[slot].flatMap { $0.isExpired(at: now) ? nil : $0 }
        if existing == nil, live(in: w.scope, at: now).count >= Self.maxEntriesPerScope {
            throw MemoryError("\(w.scope.label) already holds \(Self.maxEntriesPerScope) entries. Forget some first.")
        }
        let entry = MemoryEntry(key: key, scope: w.scope, value: w.value, file: w.file,
                                description: Trim.clean(w.description, max: Self.maxDescriptionLength),
                                author: author, createdAt: existing?.createdAt ?? now, updatedAt: now,
                                expiresAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
                                untilSessionEnds: w.untilSessionEnds)
        bySlot[slot] = entry
        revision += 1
        return entry
    }

    /// The entry under `key`: in `scope` when given, otherwise the project's, then the global one.
    public func read(key: String, project: String, scope: MemoryScope? = nil, now: Date = Date()) -> MemoryEntry? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        for scope in Self.lookup(project: project, scope: scope) {
            if let entry = bySlot[Slot(scope: scope, key: key)], !entry.isExpired(at: now) { return entry }
        }
        return nil
    }

    /// Entries without their values, newest first: the project's and global ones, or only `scope`'s.
    public func list(project: String, scope: MemoryScope? = nil, now: Date = Date()) -> [MemoryEntry] {
        let scopes = Set(Self.lookup(project: project, scope: scope))
        return entries.filter { scopes.contains($0.scope) && !$0.isExpired(at: now) }.map(\.summary)
    }

    /// Removes the entry under `key`, looked up as in `read`.
    public func forget(key: String, project: String, scope: MemoryScope? = nil, now: Date = Date()) -> MemoryEntry? {
        guard let entry = read(key: key, project: project, scope: scope, now: now) else { return nil }
        revision += 1
        return bySlot.removeValue(forKey: Slot(scope: entry.scope, key: entry.key))
    }

    /// Answers a request from `ambient memory` or `ambient mcp`. `sessions` tells who's writing; `blobs` holds
    /// the copies of shared files.
    public func answer(_ request: MemoryRequest, sessions: [Session], blobs: MemoryBlobStore?,
                       now: Date = Date()) -> MemoryReply {
        switch request {
        case let .write(write, callerPids):
            if let file = write.file, blobs?.contains(file) != true {
                return .failed("Ambient has no copy of \(file.name). Share the file again.")
            }
            do {
                return .entry(try self.write(write, author: MemoryAuthor.resolve(callerPids: callerPids, sessions: sessions),
                                             now: now))
            } catch {
                return .failed(error.localizedDescription)
            }
        case let .read(key, project, scope):
            return read(key: key, project: project, scope: scope, now: now).map(MemoryReply.entry)
                ?? .failed(Self.nothingShared(key, project: project, scope: scope))
        case let .list(project, scope):
            return .entries(list(project: project, scope: scope, now: now))
        case let .forget(key, project, scope):
            return forget(key: key, project: project, scope: scope, now: now).map(MemoryReply.forgotten)
                ?? .failed(Self.nothingShared(key, project: project, scope: scope))
        }
    }

    private static func nothingShared(_ key: String, project: String, scope: MemoryScope?) -> String {
        let place = scope.map { $0 == .global ? "globally" : "in \($0.label)" }
            ?? "in \(MemoryScope.project(project).label) or globally"
        return "Nothing is shared as \(key) \(place)."
    }

    /// Removes what a session asked to keep only while it ran.
    @discardableResult
    public func sessionEnded(_ sessionID: String) -> [MemoryEntry] {
        remove { $0.untilSessionEnds && $0.author?.sessionID == sessionID }
    }

    /// Removes session-bound entries whose session isn't among `live`, e.g. after Ambient was closed while it ended.
    @discardableResult
    public func retainSessions(_ live: Set<String>) -> [MemoryEntry] {
        remove { $0.untilSessionEnds && !live.contains($0.author?.sessionID ?? "") }
    }

    /// Removes expired entries.
    @discardableResult
    public func sweep(now: Date = Date()) -> [MemoryEntry] {
        remove { $0.isExpired(at: now) }
    }

    /// The files entries still refer to.
    public var blobs: [MemoryBlob] { bySlot.values.compactMap(\.file) }

    private func live(in scope: MemoryScope, at date: Date) -> [MemoryEntry] {
        bySlot.values.filter { $0.scope == scope && !$0.isExpired(at: date) }
    }

    private func remove(where match: (MemoryEntry) -> Bool) -> [MemoryEntry] {
        let gone = bySlot.filter { match($0.value) }
        guard !gone.isEmpty else { return [] }
        for slot in gone.keys { bySlot.removeValue(forKey: slot) }
        revision += 1
        return Array(gone.values)
    }

    private static func lookup(project: String, scope: MemoryScope?) -> [MemoryScope] {
        scope.map { [$0] } ?? [.project(project), .global]
    }

    /// Keys are short and plain so agents and shells can pass them around: "api-schema", "tests/failing".
    public static func problem(withKey key: String) -> String? {
        guard !key.isEmpty else { return "The key is empty." }
        guard key.count <= maxKeyLength else { return "Keys are limited to \(maxKeyLength) characters." }
        guard key.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/@-]*$", options: .regularExpression) != nil else {
            return "Keys use letters, digits and . _ : / @ - (no spaces), and start with a letter or digit, e.g. api-schema."
        }
        return nil
    }
}
