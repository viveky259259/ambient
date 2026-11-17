import Foundation
import AmbientBase
import AmbientContracts

/// Today's story, saved across restarts.
public enum DayLogFile {
    private struct Envelope: Codable {
        var version = 1
        var log: DayLog
    }

    public static func save(_ log: DayLog, to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(log: log))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// What was saved, or nil if the file is missing, corrupt or from another version.
    public static func load(from url: URL) -> DayLog? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return nil }
        return envelope.log
    }
}

extension AmbientPaths {
    public var dayFile: URL { home.appendingPathComponent("day.json") }
}
