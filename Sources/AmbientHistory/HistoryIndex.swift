import Foundation
import SQLite3

/// A value in or out of SQLite.
enum SQLValue: Equatable {
    case text(String)
    case int(Int)
    case real(Double)
    case null

    var string: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    var integer: Int? {
        switch self {
        case let .int(value): value
        case let .real(value): Int(value)
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case let .real(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }
}

/// The little of SQLite's C API the index needs.
final class SQLite {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(handle)
            throw HistoryError.message("Can't open the history index at \(path): \(message)")
        }
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { sqlite3_close(handle) }

    private func failure(_ sql: String) -> HistoryError {
        .message("History index: \(String(cString: sqlite3_errmsg(handle))) (in \(sql.prefix(60)))")
    }

    @discardableResult
    func run(_ sql: String, _ values: [SQLValue] = []) throws -> [[SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure(sql) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case let .text(text): status = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let .int(number): status = sqlite3_bind_int64(statement, index, Int64(number))
            case let .real(number): status = sqlite3_bind_double(statement, index, number)
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw failure(sql) }
        }
        var rows: [[SQLValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw failure(sql) }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .int(Int(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                case SQLITE_NULL: .null
                default: .text(sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
                }
            })
        }
        return rows
    }

    func transaction(_ body: () throws -> Void) throws {
        try run("BEGIN IMMEDIATE")
        do {
            try body()
            try run("COMMIT")
        } catch {
            _ = try? run("ROLLBACK")
            throw error
        }
    }
}

/// A chat as the index lists it.
public struct IndexedSession: Equatable, Sendable {
    /// "agent:session".
    public var key: String
    public var session: ChatSession
    public var url: String?
    /// Where its files are in the store.
    public var folder: String

    public init(key: String, session: ChatSession, url: String?, folder: String) {
        self.key = key
        self.session = session
        self.url = url
        self.folder = folder
    }
}

/// A card found for a question, with how its chat touched the file asked about.
public struct IndexHit: Equatable, Sendable {
    public var chat: IndexedSession
    public var card: ChangeCard
    /// The strongest thing the request did to the file; nil when the card was found by its words.
    public var how: FileTouch.How?
    /// The event where it did.
    public var event: Int?
}

/// One repository's cards on this machine, in SQLite: by file, by commit and by words. It is only ever built from
/// the store's `cards.json` files, so deleting it loses nothing.
public final class HistoryIndex {
    private let db: SQLite
    static let schemaVersion = "1"

    /// - Parameter path: a file, or ":memory:".
    public init(path: String) throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        db = try SQLite(path: path)
        try db.run("PRAGMA journal_mode=WAL")
        try db.run("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        let version = try db.run("SELECT value FROM meta WHERE key='schema'").first?.first?.string
        if version != nil, version != Self.schemaVersion {
            // Built by another version: start over. The store still has everything.
            for table in ["sessions", "cards", "touches", "commits", "cards_fts"] {
                try db.run("DROP TABLE IF EXISTS \(table)")
            }
        }
        try db.run("""
            CREATE TABLE IF NOT EXISTS sessions(key TEXT PRIMARY KEY, id TEXT, agent TEXT, repo TEXT, branch TEXT,
              developer TEXT, title TEXT, started REAL, ended REAL, url TEXT, folder TEXT, revision TEXT)
            """)
        try db.run("""
            CREATE TABLE IF NOT EXISTS cards(session TEXT, episode INTEGER, first_event INTEGER, last_event INTEGER,
              at REAL, request TEXT, summary TEXT, why TEXT, rejected TEXT, verified TEXT, files TEXT, commits TEXT,
              landed TEXT, evidence TEXT, source TEXT, PRIMARY KEY(session, episode))
            """)
        try db.run("CREATE TABLE IF NOT EXISTS touches(path TEXT, how TEXT, session TEXT, episode INTEGER, event INTEGER)")
        try db.run("CREATE INDEX IF NOT EXISTS touches_path ON touches(path)")
        try db.run("CREATE INDEX IF NOT EXISTS touches_session ON touches(session)")
        try db.run("""
            CREATE TABLE IF NOT EXISTS commits(sha TEXT, session TEXT, event INTEGER, subject TEXT, at REAL,
              PRIMARY KEY(sha, session))
            """)
        try db.run("""
            CREATE VIRTUAL TABLE IF NOT EXISTS cards_fts USING fts5(session UNINDEXED, episode UNINDEXED, request,
              summary, why, rejected, verified, files, tokenize='porter unicode61')
            """)
        try db.run("INSERT OR REPLACE INTO meta(key, value) VALUES('schema', ?)", [.text(Self.schemaVersion)])
    }

    public static func key(for session: ChatSession) -> String { "\(session.agent):\(session.id)" }

    // MARK: - Writing

    /// Puts a chat's cards in, replacing whatever the index had for that chat.
    public func upsert(_ file: CardFile, folder: String, revision: String) throws {
        let key = Self.key(for: file.session)
        try db.transaction {
            try removeRows(for: key)
            let s = file.session
            try db.run("INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", [
                .text(key), .text(s.id), .text(s.agent), .text(s.repo), Self.optional(s.branch),
                Self.optional(s.developer), Self.optional(s.title), .real(s.startedAt.timeIntervalSince1970),
                .real(s.endedAt.timeIntervalSince1970), Self.optional(file.url), .text(folder), .text(revision),
            ])
            for card in file.cards {
                try db.run("INSERT INTO cards VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
                    .text(key), .int(card.episode), .int(card.firstEvent), .int(card.lastEvent),
                    card.at.map { .real($0.timeIntervalSince1970) } ?? .null, .text(card.request), .text(card.summary),
                    .text(card.why), .text(card.rejected), .text(card.verified), .text(Self.json(card.files)),
                    .text(Self.json(card.commits)), .text(card.landed.rawValue),
                    .text(Self.json(card.evidence.map(String.init))), .text(card.source),
                ])
                try db.run("INSERT INTO cards_fts VALUES(?,?,?,?,?,?,?,?)", [
                    .text(key), .int(card.episode), .text(card.request), .text(card.summary), .text(card.why),
                    .text(card.rejected), .text(card.verified), .text(Self.words(inPaths: card.files)),
                ])
            }
            for touch in file.touches {
                try db.run("INSERT INTO touches VALUES(?,?,?,?,?)", [
                    .text(touch.path), .text(touch.how.rawValue), .text(key), .int(touch.episode), .int(touch.event),
                ])
            }
            for commit in file.commits {
                try db.run("INSERT OR REPLACE INTO commits VALUES(?,?,?,?,?)", [
                    .text(commit.sha), .text(key), commit.event.map { .int($0) } ?? .null, .text(commit.subject),
                    .real(commit.at.timeIntervalSince1970),
                ])
            }
        }
    }

    public func remove(sessionKey key: String) throws {
        try db.transaction { try removeRows(for: key) }
    }

    private func removeRows(for key: String) throws {
        for table in ["sessions WHERE key", "cards WHERE session", "touches WHERE session", "commits WHERE session",
                      "cards_fts WHERE session"] {
            try db.run("DELETE FROM \(table) = ?", [.text(key)])
        }
    }

    private static func optional(_ text: String?) -> SQLValue { text.map { .text($0) } ?? .null }

    private static func json(_ strings: [String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: strings)) ?? Data("[]".utf8), as: UTF8.self)
    }

    private static func strings(_ json: String?) -> [String] {
        (json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String]) ?? []
    }

    /// "Sources/AmbientCore/TaskStore.swift" as words a search can match: the path, its file name and the name's parts.
    static func words(inPaths paths: [String]) -> String {
        paths.map { path in
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return "\(path) \(name) \(camelParts(name))"
        }.joined(separator: " ")
    }

    static func camelParts(_ name: String) -> String {
        var parts: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, let last = current.last, last.isLowercase || last.isNumber {
                parts.append(current)
                current = ""
            }
            if character.isLetter || character.isNumber { current.append(character) } else if !current.isEmpty {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.count > 1 ? parts.joined(separator: " ") : ""
    }

    // MARK: - Reading

    /// Where each indexed chat's files are in the store, and the revision of the cards they were read from.
    public func revisions() throws -> [String: (key: String, revision: String)] {
        var result: [String: (key: String, revision: String)] = [:]
        for row in try db.run("SELECT folder, key, revision FROM sessions") {
            if let folder = row[0].string, let key = row[1].string { result[folder] = (key, row[2].string ?? "") }
        }
        return result
    }

    public func counts() throws -> (chats: Int, cards: Int) {
        let chats = try db.run("SELECT COUNT(*) FROM sessions").first?.first?.integer ?? 0
        let cards = try db.run("SELECT COUNT(*) FROM cards").first?.first?.integer ?? 0
        return (chats, cards)
    }

    /// Every file some indexed chat touched.
    public func knownPaths() throws -> Set<String> {
        Set(try db.run("SELECT DISTINCT path FROM touches").compactMap { $0.first?.string })
    }

    private static let cardColumns = """
        s.key, s.id, s.agent, s.repo, s.branch, s.developer, s.title, s.started, s.ended, s.url, s.folder,
        c.episode, c.first_event, c.last_event, c.at, c.request, c.summary, c.why, c.rejected, c.verified, c.files,
        c.commits, c.landed, c.evidence, c.source
        """

    private static func hit(from row: [SQLValue], how: FileTouch.How? = nil, event: Int? = nil) -> IndexHit? {
        guard row.count >= 25, let key = row[0].string, let id = row[1].string, let agent = row[2].string,
              let repo = row[3].string, let episode = row[11].integer else { return nil }
        let session = ChatSession(id: id, agent: agent, repo: repo, branch: row[4].string, developer: row[5].string,
                                  title: row[6].string, startedAt: Date(timeIntervalSince1970: row[7].double ?? 0),
                                  endedAt: Date(timeIntervalSince1970: row[8].double ?? 0))
        let card = ChangeCard(episode: episode, firstEvent: row[12].integer ?? 0, lastEvent: row[13].integer ?? 0,
                              at: row[14].double.map { Date(timeIntervalSince1970: $0) }, request: row[15].string ?? "",
                              summary: row[16].string ?? "", why: row[17].string ?? "", rejected: row[18].string ?? "",
                              verified: row[19].string ?? "", files: strings(row[20].string),
                              commits: strings(row[21].string),
                              landed: ChangeCard.Landed(rawValue: row[22].string ?? "") ?? .none,
                              evidence: strings(row[23].string).compactMap(Int.init), source: row[24].string ?? "extract")
        return IndexHit(chat: IndexedSession(key: key, session: session, url: row[9].string, folder: row[10].string ?? ""),
                        card: card, how: how, event: event)
    }

    /// The requests that had to do with any of these paths (a file's names over time), newest first. Each request
    /// appears once, with the strongest thing it did to the file.
    public func requests(touching paths: [String], changesOnly: Bool) throws -> [IndexHit] {
        guard !paths.isEmpty else { return [] }
        let marks = paths.map { _ in "?" }.joined(separator: ",")
        let rows = try db.run("""
            SELECT \(Self.cardColumns), t.how, t.event FROM touches t
            JOIN cards c ON c.session = t.session AND c.episode = t.episode
            JOIN sessions s ON s.key = t.session
            WHERE t.path IN (\(marks)) ORDER BY COALESCE(c.at, s.started) DESC, c.episode DESC
            """, paths.map { .text($0) })
        var best: [String: IndexHit] = [:]
        var order: [String] = []
        for row in rows {
            guard let how = row[25].string.flatMap(FileTouch.How.init), let hit = Self.hit(from: row, how: how, event: row[26].integer),
                  !changesOnly || how.changes else { continue }
            let id = "\(hit.chat.key)#\(hit.card.episode)"
            if let existing = best[id] {
                if Capture.rank(how) < Capture.rank(existing.how ?? .mention) { best[id] = hit }
            } else {
                best[id] = hit
                order.append(id)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// The chats that made a commit. `sha` may be a prefix.
    public func sessions(makingCommit sha: String) throws -> [String] {
        guard sha.count >= 7, sha.allSatisfy(\.isHexDigit) else { return [] }
        return try db.run("SELECT DISTINCT session FROM commits WHERE sha LIKE ? ORDER BY at", [.text(sha.lowercased() + "%")])
            .compactMap { $0.first?.string }
    }

    /// Where a commit was made: the chat, and the request whose events include the command that made it.
    public func requests(makingCommit sha: String) throws -> [IndexHit] {
        guard sha.count >= 7, sha.allSatisfy(\.isHexDigit) else { return [] }
        return try db.run("""
            SELECT \(Self.cardColumns) FROM commits k
            JOIN cards c ON c.session = k.session AND k.event BETWEEN c.first_event AND c.last_event
            JOIN sessions s ON s.key = c.session
            WHERE k.sha LIKE ? ORDER BY k.at
            """, [.text(sha.lowercased() + "%")]).compactMap { Self.hit(from: $0) }
    }

    public func cards(inSession key: String) throws -> [IndexHit] {
        try db.run("""
            SELECT \(Self.cardColumns) FROM cards c JOIN sessions s ON s.key = c.session
            WHERE c.session = ? ORDER BY c.episode
            """, [.text(key)]).compactMap { Self.hit(from: $0) }
    }

    /// The chat whose key or session id starts with `prefix`, when exactly one does.
    public func session(matching prefix: String) throws -> IndexedSession? {
        let rows = try db.run("""
            SELECT key, id, agent, repo, branch, developer, title, started, ended, url, folder FROM sessions
            WHERE key LIKE ? OR id LIKE ? LIMIT 2
            """, [.text(prefix + "%"), .text(prefix + "%")])
        guard rows.count == 1, let row = rows.first, let key = row[0].string, let id = row[1].string,
              let agent = row[2].string, let repo = row[3].string else { return nil }
        let session = ChatSession(id: id, agent: agent, repo: repo, branch: row[4].string, developer: row[5].string,
                                  title: row[6].string, startedAt: Date(timeIntervalSince1970: row[7].double ?? 0),
                                  endedAt: Date(timeIntervalSince1970: row[8].double ?? 0))
        return IndexedSession(key: key, session: session, url: row[9].string, folder: row[10].string ?? "")
    }

    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "did", "do", "does", "for", "from",
        "had", "has", "have", "how", "in", "into", "is", "it", "its", "me", "of", "on", "or", "so", "tell", "that",
        "the", "their", "then", "there", "this", "to", "was", "we", "were", "what", "when", "where", "which", "who",
        "why", "will", "with", "would", "you",
    ]

    /// An FTS5 query for a question: its words, any of which may match. Nil when it has none worth searching for.
    static func match(for question: String) -> String? {
        var seen = Set<String>()
        let words = question.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) && seen.insert($0).inserted }
        return words.isEmpty ? nil : words.prefix(24).map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    /// Cards whose words match the question, best first.
    public func search(_ question: String, limit: Int = 12) throws -> [IndexHit] {
        // Identifiers are searched as written and as their parts: "TaskStore" also finds "task store".
        let expanded = question + " " + question.split { !($0.isLetter || $0.isNumber) }
            .map { Self.camelParts(String($0)) }.joined(separator: " ")
        guard let match = Self.match(for: expanded) else { return [] }
        let rows = try db.run("""
            SELECT \(Self.cardColumns) FROM cards_fts f
            JOIN cards c ON c.session = f.session AND c.episode = f.episode
            JOIN sessions s ON s.key = c.session
            WHERE cards_fts MATCH ? ORDER BY bm25(cards_fts, 0, 0, 2.0, 3.0, 3.0, 1.0, 1.0, 2.0) LIMIT ?
            """, [.text(match), .int(limit)])
        return rows.compactMap { Self.hit(from: $0) }
    }
}
