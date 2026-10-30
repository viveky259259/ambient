import Foundation

/// Sessions saved across app restarts, so an update doesn't forget agents mid-turn.
public enum StateFile {
    private struct Envelope: Codable {
        var version = 1
        var sessions: [Session]
        /// Saved with the sessions, so what a machine has delivered and what the sessions show never disagree.
        var remoteCursors: [String: RemoteCursor]?
    }

    public static func save(_ sessions: [Session], cursors: [String: RemoteCursor] = [:], to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(sessions: sessions, remoteCursors: cursors.isEmpty ? nil : cursors))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Whatever was saved, or nothing if the file is missing or from an incompatible version.
    public static func load(from url: URL) -> [Session] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return envelope.sessions
    }

    /// How far each paired machine had been applied when the sessions were saved.
    public static func loadCursors(from url: URL) -> [String: RemoteCursor] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [:] }
        return envelope.remoteCursors ?? [:]
    }
}

extension AmbientPaths {
    public var stateFile: URL { home.appendingPathComponent("state.json") }
}
