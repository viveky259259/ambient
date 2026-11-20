import AmbientCore
import AmbientHistory
import Foundation

/// Hands finished chats to `ambient history capture`, which stores them for the team. The app only decides when; the
/// work runs in the command-line tool, one capture at a time, off the main thread, and says what it did in
/// `~/.ambient/logs/history.log`.
final class HistoryLauncher {
    private let paths: AmbientPaths
    private let isAlive: (Int32) -> Bool
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.history", qos: .utility)
    private var nextScan = Date.distantPast
    /// How often chats that went quiet without saying they ended are looked for.
    static let scanInterval: TimeInterval = 3_600
    /// An agent writes its transcript's last lines as it exits; reading sooner can miss them.
    static let settleDelay: TimeInterval = 5

    init(paths: AmbientPaths, isAlive: @escaping (Int32) -> Bool = ProcessProbe.isAlive) {
        self.paths = paths
        self.isAlive = isAlive
    }

    private var isSetUp: Bool {
        FileManager.default.fileExists(atPath: paths.historyConfig.path)
            && !HistoryConfig.load(from: paths.historyConfig).repos.isEmpty
    }

    /// True when a session leaving the island means its chat is over: it said so, or its agent has exited. One the
    /// island dropped for going quiet may still be picked up again, so it waits for the hourly look instead.
    static func isFinished(_ change: SessionChange, isAlive: (Int32) -> Bool) -> Bool {
        guard change.removed, change.session.origin == nil, !change.session.sessionId.hasPrefix("demo-") else { return false }
        if change.event == .sessionEnded { return true }
        guard let pid = change.session.host?.agentPid else { return false }
        return !isAlive(pid)
    }

    /// Call with every change to a session.
    func observe(_ change: SessionChange) {
        guard Self.isFinished(change, isAlive: isAlive), isSetUp else { return }
        let id = change.session.id
        queue.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            self?.run(["history", "capture", "--session", id, "--quiet"])
        }
    }

    /// Call often; it looks for quiet, finished chats at most once an hour.
    func tick(now: Date = Date()) {
        guard now >= nextScan else { return }
        nextScan = now.addingTimeInterval(Self.scanInterval)
        guard isSetUp else { return }
        queue.async { [weak self] in self?.run(["history", "capture", "--due", "--quiet"]) }
    }

    private func run(_ arguments: [String]) {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ambient")
        let cli = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : paths.cliLink
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { return }
        let log = paths.logs.appendingPathComponent("history.log")
        try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: log) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? handle.write(contentsOf: Data("\(stamp) ambient \(arguments.joined(separator: " "))\n".utf8))
        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? handle.write(contentsOf: Data("couldn't start: \(error.localizedDescription)\n".utf8))
        }
    }
}
