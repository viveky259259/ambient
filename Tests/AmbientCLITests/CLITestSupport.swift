@testable import AmbientCore
import Foundation
import Testing
@testable import ambient

/// A throwaway user home for one test, short enough for a Unix socket path (macOS caps them at 104 bytes).
struct TempHome {
    let root: URL
    var paths: AmbientPaths { AmbientPaths(userHome: root) }

    init() throws {
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("amb-cli-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// Makes `~/<folder>` so the installer thinks that agent is on this Mac.
    func addAgentFolder(_ folder: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true),
                                                withIntermediateDirectories: true)
    }
}

/// Stands in for Ambient.app on the CLI's socket: answers each request with `respond` and keeps what it got.
final class FakeAppSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [WireMessage] = []
    private let server: UnixSocketServer
    private let respond: @Sendable (WireMessage) -> WireMessage?

    var received: [WireMessage] { lock.lock(); defer { lock.unlock() }; return _received }

    init(paths: AmbientPaths, respond: @escaping @Sendable (WireMessage) -> WireMessage?) throws {
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        self.respond = respond
        server = UnixSocketServer(path: paths.socket.path)
        try server.start { [weak self] data in
            guard let self, let message = try? Wire.decode(data) else { return nil }
            self.lock.lock(); self._received.append(message); self.lock.unlock()
            return self.respond(message).flatMap { try? Wire.encode($0) }
        }
    }

    func stop() { server.stop() }
}

/// Runs `ambient <args>` against a temp home and returns its exit code.
func runCLI(_ args: [String], paths: AmbientPaths) -> Int32 {
    Commands(paths: paths).run(args)
}

let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

func sampleSession(_ id: String = "s1", agent: AgentKind = .claude, cwd: String = "/src/api") -> Session {
    var s = Session(agent: agent, sessionId: id, at: fixedDate)
    s.cwd = cwd
    return s
}
