import Foundation

/// Where Ambient keeps its socket, CLI link, backups and logs. `AMBIENT_HOME` overrides `~/.ambient`.
public struct AmbientPaths: Equatable, Sendable {
    /// The user's home directory, where agent configs live.
    public let userHome: URL
    public let home: URL

    public init(userHome: URL, home: URL? = nil) {
        self.userHome = userHome
        self.home = home ?? userHome.appendingPathComponent(".ambient", isDirectory: true)
    }

    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> AmbientPaths {
        let userHome = URL(fileURLWithPath: environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory(),
                           isDirectory: true)
        let home = environment["AMBIENT_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return AmbientPaths(userHome: userHome, home: home)
    }

    public var socket: URL { home.appendingPathComponent("ambient.sock") }
    public var binDir: URL { home.appendingPathComponent("bin", isDirectory: true) }
    public var cliLink: URL { binDir.appendingPathComponent("ambient") }
    public var backups: URL { home.appendingPathComponent("backups", isDirectory: true) }
    public var logs: URL { home.appendingPathComponent("logs", isDirectory: true) }
    /// Downloaded offline voice packs, one folder per version.
    public var voice: URL { home.appendingPathComponent("voice", isDirectory: true) }
    /// Few-shot skill pack for the local board summarizer (`task-skill.json`, 0600).
    public var taskSkill: URL { home.appendingPathComponent("task-skill.json") }

    /// Creates the Ambient home, readable only by the user.
    public func ensureHome() throws {
        let fm = FileManager.default
        for dir in [home, binDir, backups, logs] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
    }
}
