import Foundation

extension AmbientPaths {
    /// The hub's remote-agents data, readable only by the user.
    public var remoteDir: URL { home.appendingPathComponent("remote", isDirectory: true) }
    /// Paired machines: the allowlist. Nothing else is ever followed.
    public var machinesFile: URL { remoteDir.appendingPathComponent("machines.json") }
    public var remoteAuditLog: URL { remoteDir.appendingPathComponent("audit.jsonl") }
    public var remoteAudit: RemoteAudit { RemoteAudit(url: remoteAuditLog) }
}

/// The paired machines, saved under `~/.ambient/remote/machines.json`.
public enum MachineFile {
    private struct Envelope: Codable {
        var version = 1
        var machines: [Machine]
    }

    public static func save(_ machines: [Machine], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(machines: machines.sorted { $0.id < $1.id })).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Whatever was saved. A machine with an invalid id or fingerprint isn't followed, and an id is only read once:
    /// the file is the allowlist, and people edit it.
    public static func load(from url: URL) -> [Machine] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        var seen = Set<String>()
        return envelope.machines.filter {
            Machine.isValidID($0.id) && Machine.isValidFingerprint($0.fingerprint) && !$0.transport.isEmpty
                && seen.insert($0.id).inserted
        }
    }
}
