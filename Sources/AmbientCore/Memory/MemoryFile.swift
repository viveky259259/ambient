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

    /// Whatever was saved, or nothing if the file is missing or from an incompatible version.
    public static func load(from url: URL) -> [MemoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return envelope.entries
    }
}

/// Copies of shared files, one folder per content hash: `~/.ambient/memory/<sha256>/<name>`, read-only, so the
/// agent that reads one can't change it for the others.
public struct MemoryBlobStore: Sendable {
    public static let maxFileBytes = 50 * 1024 * 1024
    /// Text files up to this size are checked for secrets like shared text is.
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
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw MemoryError("There's no file at \(source.path).")
        }
        guard !isDirectory.boolValue else {
            throw MemoryError("\(source.path) is a folder. Share its files one at a time, or an archive of it.")
        }
        let size = (try? fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maxFileBytes else {
            throw MemoryError("The file is \(size / 1_048_576) MB; shared files are limited to \(Self.maxFileBytes / 1_048_576) MB.")
        }
        guard let data = try? Data(contentsOf: source, options: .alwaysMapped) else {
            throw MemoryError("Couldn't read \(source.path).")
        }
        if data.count <= Self.scannedBytes, let text = String(data: data, encoding: .utf8),
           let problem = MemoryGuard.problem(withText: text) {
            throw MemoryError(problem)
        }

        let blob = MemoryBlob(name: source.lastPathComponent, sha256: Self.sha256(data), size: data.count)
        if contains(blob) { return blob }
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
            if folder.lastPathComponent.hasPrefix(".") {
                let changed = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if changed < cutoff { try? fm.removeItem(at: folder) }
            } else if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? fm.removeItem(at: folder)
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
