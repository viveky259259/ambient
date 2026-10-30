import CryptoKit
import Foundation

/// Shared working memory saved under `~/.ambient/memory.json`.
public enum MemoryFile {
    private struct Envelope: Codable {
        var version = 1
        var entries: [MemoryEntry]
    }

    public static func save(_ entries: [MemoryEntry], to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(entries: entries))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Whatever was saved, nothing if the file is missing, or nil if it can't be read, e.g. it's from another version.
    public static func load(from url: URL) -> [MemoryEntry]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return nil }
        return envelope.entries
    }
}

/// Copies of shared files, one folder per content hash: `~/.ambient/memory/<sha256>/<name>`, read-only, so the
/// agent that reads one can't change it for the others.
public struct MemoryBlobStore: Sendable {
    public static let maxFileBytes = 50 * 1024 * 1024
    /// How much of a file is checked for secrets, like shared text is.
    static let scannedBytes = 1024 * 1024

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for blob: MemoryBlob) -> URL {
        root.appendingPathComponent(blob.sha256, isDirectory: true).appendingPathComponent(blob.name)
    }

    public func contains(_ blob: MemoryBlob) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: blob).path)
        return (attributes?[.size] as? NSNumber)?.intValue == blob.size
    }

    /// Copies the file at `path` in, unless it's too big or looks like it holds secrets.
    public func add(fileAt path: String) throws -> MemoryBlob {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        if let problem = MemoryGuard.problem(withFilePath: source.path)
            ?? MemoryGuard.problem(withFilePath: source.resolvingSymlinksInPath().path) {
            throw MemoryError(problem)
        }
        // Of the file itself: these describe a symlink, not what it points to.
        let target = source.resolvingSymlinksInPath()
        guard let attributes = try? fm.attributesOfItem(atPath: target.path) else {
            throw MemoryError("There's no file at \(source.path).")
        }
        guard attributes[.type] as? FileAttributeType != .typeDirectory else {
            throw MemoryError("\(source.path) is a folder. Share its files one at a time, or an archive of it.")
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MemoryError("\(source.path) isn't a regular file.")
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maxFileBytes else {
            throw MemoryError("The file is \(size / 1_048_576) MB; shared files are limited to \(Self.maxFileBytes / 1_048_576) MB.")
        }
        guard let data = try? Data(contentsOf: target) else {
            throw MemoryError("Couldn't read \(source.path).")
        }
        // Lenient, so one stray byte in a log doesn't skip the check.
        if let problem = MemoryGuard.problem(withText: String(decoding: data.prefix(Self.scannedBytes), as: UTF8.self)) {
            throw MemoryError(problem)
        }

        let blob = MemoryBlob(name: source.lastPathComponent, sha256: Self.sha256(data), size: data.count)
        if contains(blob) {
            // Counts as new, so collection doesn't take it before the app hears about it.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url(for: blob).path)
            return blob
        }
        let folder = root.appendingPathComponent(blob.sha256, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = root.appendingPathComponent(".\(UUID().uuidString)")
        do {
            try data.write(to: temporary)
            try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: temporary.path)
            try fm.moveItem(at: temporary, to: url(for: blob))
        } catch {
            try? fm.removeItem(at: temporary)
            // Another agent shared the same file at the same moment.
            if contains(blob) { return blob }
            throw MemoryError("Couldn't copy the file into shared memory: \(error.localizedDescription)")
        }
        return blob
    }

    /// Deletes copies no entry refers to. Ones changed after `cutoff` stay, since an agent may have just copied
    /// a file in and not yet asked the app to share it.
    public func collect(keeping blobs: [MemoryBlob], changedBefore cutoff: Date) {
        let fm = FileManager.default
        // By "<sha256>/<name>": listings come back with symlinks resolved (/private/var for /var), unlike `root`.
        let keep = Set(blobs.map { "\($0.sha256)/\($0.name)" })
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where !keep.contains("\(folder.lastPathComponent)/\(file.lastPathComponent)") {
                let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if changed < cutoff { try? fm.removeItem(at: file) }
            }
            // Temporary files and emptied folders; a new empty folder may be about to get its file.
            if folder.lastPathComponent.hasPrefix(".") || (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                let changed = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if changed < cutoff { try? fm.removeItem(at: folder) }
            }
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension AmbientPaths {
    public var memoryFile: URL { home.appendingPathComponent("memory.json") }
    public var memoryBlobs: URL { home.appendingPathComponent("memory", isDirectory: true) }
}
