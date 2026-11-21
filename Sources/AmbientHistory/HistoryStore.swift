import Foundation

/// A file in a store.
public struct StoredObject: Equatable, Sendable {
    public var key: String
    /// Changes whenever the object is written again. Compared, never parsed.
    public var revision: String

    public init(key: String, revision: String) {
        self.key = key
        self.revision = revision
    }
}

/// Where a team's chats are kept: a bucket, or a folder.
public protocol HistoryStore: Sendable {
    func put(_ data: Data, key: String, contentType: String) throws
    /// Nil when there is nothing under the key.
    func get(_ key: String) throws -> Data?
    func list(prefix: String) throws -> [StoredObject]
    /// A stable address a person can open, when the store has one.
    func address(of key: String) -> String?
}

/// Where a chat's files go: `<repo>/sessions/<yyyy>/<mm>/<dd>/<agent>-<session>/`. The date is the day the chat
/// started, so capturing it again after it resumes writes to the same place.
public enum HistoryKeys {
    public static func repoPrefix(_ repo: String) -> String { clean(repo) + "/sessions/" }

    public static func folder(for session: ChatSession) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.dateComponents([.year, .month, .day], from: session.startedAt)
        let date = String(format: "%04d/%02d/%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return repoPrefix(session.repo) + "\(date)/\(clean(session.agent))-\(clean(session.id))/"
    }

    public static let chat = "chat.json"
    public static let cards = "cards.json"
    public static let page = "page.html"

    /// Keeps a key to characters that need no escaping anywhere it's used: a URL, a shell, a file name.
    public static func clean(_ text: String) -> String {
        let parts = text.split(separator: "/", omittingEmptySubsequences: true).map { part in
            String(part.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "-" })
        }.filter { $0 != "." && $0 != ".." }
        return parts.isEmpty ? "unknown" : parts.joined(separator: "/")
    }
}

/// A folder on this machine or a shared disk. Also what tests use.
public struct FolderStore: HistoryStore {
    public let root: String

    public init(root: String) {
        self.root = root.hasSuffix("/") ? String(root.dropLast()) : root
    }

    private func path(_ key: String) -> String { root + "/" + key }

    public func put(_ data: Data, key: String, contentType: String) throws {
        let url = URL(fileURLWithPath: path(key))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func get(_ key: String) throws -> Data? {
        FileManager.default.contents(atPath: path(key))
    }

    public func list(prefix: String) throws -> [StoredObject] {
        // A store that isn't there is an error, not an empty store: a shared disk that isn't mounted must not look
        // like every chat was deleted.
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isFolder), isFolder.boolValue else {
            throw HistoryError.message("The history folder \(root) isn't there.")
        }
        let base = path(prefix)
        guard let walker = FileManager.default.enumerator(atPath: base) else { return [] }
        var objects: [StoredObject] = []
        for case let name as String in walker {
            let full = base + (base.hasSuffix("/") ? "" : "/") + name
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: full),
                  attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            objects.append(StoredObject(key: prefix + (prefix.hasSuffix("/") || prefix.isEmpty ? "" : "/") + name,
                                        revision: "\(Int(modified * 1000))-\(size)"))
        }
        return objects.sorted { $0.key < $1.key }
    }

    public func address(of key: String) -> String? {
        URL(fileURLWithPath: path(key)).absoluteString
    }
}

/// An S3 bucket, reached through the `aws` command with the developer's own sign-in. Ambient holds no AWS keys.
public struct S3Store: HistoryStore {
    public let bucket: String
    /// Inside the bucket, without slashes at either end; empty for the bucket's root.
    public let prefix: String
    public let region: String
    public let profile: String?
    public let shell: Shell

    public init(bucket: String, prefix: String = "", region: String, profile: String? = nil, shell: Shell = .system) {
        self.bucket = bucket
        self.prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.region = region
        self.profile = profile.flatMap { $0.isEmpty ? nil : $0 }
        self.shell = shell
    }

    /// `s3://bucket/prefix` taken apart; nil for anything else.
    public static func parse(_ location: String) -> (bucket: String, prefix: String)? {
        guard location.hasPrefix("s3://") else { return nil }
        let rest = location.dropFirst(5).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let bucket = rest.first, bucket.range(of: "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", options: .regularExpression) != nil
        else { return nil }
        return (bucket, rest.count > 1 ? rest[1].trimmingCharacters(in: CharacterSet(charactersIn: "/")) : "")
    }

    func full(_ key: String) -> String { prefix.isEmpty ? key : prefix + "/" + key }

    private var common: [String] {
        ["--region", region] + (profile.map { ["--profile", $0] } ?? [])
    }

    private func failure(_ what: String, _ output: Shell.Output) -> HistoryError {
        if output.status == 127 {
            return .message("\(what): the aws command isn't installed. Install it with `brew install awscli`.")
        }
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .message("\(what): \(detail.isEmpty ? "aws exited with \(output.status)" : detail)")
    }

    public func put(_ data: Data, key: String, contentType: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-history-\(UUID().uuidString)")
        try data.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let output = shell("aws", ["s3api", "put-object", "--bucket", bucket, "--key", full(key), "--body", file.path,
                                   "--content-type", contentType] + common)
        guard output.succeeded else { throw failure("Couldn't upload \(key)", output) }
    }

    public func get(_ key: String) throws -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let output = shell("aws", ["s3api", "get-object", "--bucket", bucket, "--key", full(key)] + common + [file.path])
        if !output.succeeded {
            if output.stderr.contains("NoSuchKey") || output.stderr.contains("(404)") { return nil }
            throw failure("Couldn't download \(key)", output)
        }
        return FileManager.default.contents(atPath: file.path)
    }

    public func list(prefix listed: String) throws -> [StoredObject] {
        // The CLI follows the pages itself and prints one document.
        let output = shell("aws", ["s3api", "list-objects-v2", "--bucket", bucket, "--prefix", full(listed),
                                   "--query", "Contents[].{k:Key,e:ETag,m:LastModified}", "--output", "json"] + common)
        guard output.succeeded else { throw failure("Couldn't list the bucket", output) }
        guard let rows = (try? JSONSerialization.jsonObject(with: Data(output.stdout.utf8))) as? [[String: Any]] else {
            // An empty prefix prints "null".
            return []
        }
        let strip = prefix.isEmpty ? 0 : prefix.count + 1
        return rows.compactMap { row -> StoredObject? in
            guard let key = row["k"] as? String, key.count > strip else { return nil }
            let revision = (row["e"] as? String ?? "") + "@" + (row["m"] as? String ?? "")
            return StoredObject(key: String(key.dropFirst(strip)), revision: revision)
        }.sorted { $0.key < $1.key }
    }

    /// The object's page in the AWS console. It opens for someone signed in to AWS with access to the bucket and shows
    /// nothing to anyone else, so it can sit in a public pull request. (The object's own `amazonaws.com` URL can't be
    /// used: a browser's console sign-in doesn't count there, so it refuses everyone.)
    public func address(of key: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let encoded = full(key).addingPercentEncoding(withAllowedCharacters: allowed) ?? full(key)
        return "https://s3.console.aws.amazon.com/s3/object/\(bucket)?region=\(region)&prefix=\(encoded)"
    }
}
