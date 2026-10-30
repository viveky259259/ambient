import Foundation

/// Tasks saved under `~/.ambient/tasks.json`.
public enum TaskFile {
    private struct Envelope: Codable {
        var version = 1
        var tasks: [AgentTask]
    }

    public static func save(_ tasks: [AgentTask], to url: URL) throws {
        let data = try JSONEncoder().encode(Envelope(tasks: tasks))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Whatever was saved, or nothing if the file is missing or from an incompatible version.
    public static func load(from url: URL) -> [AgentTask] {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return envelope.tasks
    }
}

extension AmbientPaths {
    public var tasksFile: URL { home.appendingPathComponent("tasks.json") }
}
