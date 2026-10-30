import Foundation

/// The hub's local, append-only record of what happened on the remote path (ER-27). It holds what happened and to
/// which machine, and never any event content: `detail` is always a short code or a fingerprint, never remote text.
public struct RemoteAudit: Sendable {
    public enum Action: String, Codable, Sendable {
        case paired, unpaired, purged, fingerprintChanged, policyChanged
        case linkUp, linkDown, signInNeeded, upgradeNeeded
        case rejected, rateLimited, spoolGap, spoolReset
    }

    public struct Record: Codable, Equatable, Sendable {
        public let ts: Date
        public let action: Action
        public let machine: String
        public var detail: String?
        public var count: Int?

        public init(ts: Date = Date(), action: Action, machine: String, detail: String? = nil, count: Int? = nil) {
            self.ts = ts
            self.action = action
            self.machine = machine
            self.detail = detail
            self.count = count
        }
    }

    /// Past this, the log moves to `audit.1.jsonl`, replacing the one before.
    static let maxBytes = 5 * 1024 * 1024

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Appends one line. Failing to audit never stops a link.
    public func append(_ record: Record) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(record) else { return }
        line.append(UInt8(ascii: "\n"))

        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxBytes {
            let old = url.deletingPathExtension().appendingPathExtension("1.jsonl")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        // O_APPEND: the app and the CLI both write here, and a short write of one line is atomic.
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    public func records() -> [Record] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Record.self, from: Data($0)) }
    }
}
