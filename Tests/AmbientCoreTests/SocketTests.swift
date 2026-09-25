import Foundation
import Testing
@testable import AmbientCore

/// A short, unique directory: Unix socket paths are limited to 104 bytes.
func shortTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("amb-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Collects values from other threads and waits for them.
final class Inbox<T>: @unchecked Sendable {
    private let lock = NSCondition()
    private var items: [T] = []

    func put(_ item: T) {
        lock.lock(); items.append(item); lock.broadcast(); lock.unlock()
    }

    func wait(count: Int = 1, timeout: TimeInterval = 2) -> [T] {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock(); defer { lock.unlock() }
        while items.count < count, lock.wait(until: deadline) {}
        return items
    }
}

@Suite(.serialized) struct SocketTests {
    @Test func wireMessagesAreSingleJSONLines() throws {
        let event = AgentEvent(agent: .claude, sessionId: "s", cwd: "/x", kind: .toolStarted(name: "Bash", detail: "a\nb"),
                               timestamp: Date(timeIntervalSince1970: 5))
        let data = try Wire.encode(.event(event))
        #expect(data.last == UInt8(ascii: "\n"))
        #expect(data.dropLast().contains(UInt8(ascii: "\n")) == false)
        #expect(try Wire.decode(data) == .event(event))
    }

    @Test func eventsReachTheServer() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let inbox = Inbox<WireMessage>()
        let server = UnixSocketServer(path: path)
        try server.start { data in
            if let m = try? Wire.decode(data) { inbox.put(m) }
            return nil
        }
        defer { server.stop() }

        let event = AgentEvent(agent: .gemini, sessionId: "g", cwd: nil, kind: .promptSubmitted,
                               timestamp: Date(timeIntervalSince1970: 9))
        _ = try UnixSocket.send(Wire.encode(.event(event)), to: path)
        #expect(inbox.wait() == [.event(event)])
    }

    @Test func requestsGetReplies() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path)
        try server.start { data in
            guard (try? Wire.decode(data)) == .ping else { return nil }
            return try? Wire.encode(.pong(version: "1.2.3"))
        }
        defer { server.stop() }

        let reply = try UnixSocket.send(Wire.encode(.ping), to: path, expectReply: true)
        #expect(try reply.map(Wire.decode) == .pong(version: "1.2.3"))
    }

    @Test func sendingToNobodyFailsFast() throws {
        let path = try shortTempDir().appendingPathComponent("missing.sock").path
        let start = Date()
        #expect(throws: (any Error).self) { try UnixSocket.send(Data("x\n".utf8), to: path) }
        #expect(Date().timeIntervalSince(start) < 0.3)
    }

    @Test func oversizedMessagesAreDropped() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let inbox = Inbox<Int>()
        let server = UnixSocketServer(path: path, maxMessageSize: 1024)
        try server.start { data in inbox.put(data.count); return nil }
        defer { server.stop() }

        _ = try? UnixSocket.send(Data(repeating: UInt8(ascii: "a"), count: 4096) + Data("\n".utf8), to: path)
        _ = try UnixSocket.send(Data("small\n".utf8), to: path)
        #expect(inbox.wait(count: 2, timeout: 0.5) == [5])
    }

    @Test func secondServerOnALiveSocketRefuses() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let first = UnixSocketServer(path: path)
        try first.start { _ in nil }
        defer { first.stop() }
        #expect(throws: UnixSocketError.alreadyRunning) { try UnixSocketServer(path: path).start { _ in nil } }
    }

    @Test func staleSocketFileIsReplaced() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let first = UnixSocketServer(path: path)
        try first.start { _ in nil }
        first.stop(unlink: false)
        #expect(FileManager.default.fileExists(atPath: path))

        let inbox = Inbox<Data>()
        let second = UnixSocketServer(path: path)
        try second.start { inbox.put($0); return nil }
        defer { second.stop() }
        _ = try UnixSocket.send(Data("hi\n".utf8), to: path)
        #expect(inbox.wait() == [Data("hi".utf8)])
    }

    @Test func socketIsPrivateToTheUser() throws {
        let path = try shortTempDir().appendingPathComponent("s.sock").path
        let server = UnixSocketServer(path: path)
        try server.start { _ in nil }
        defer { server.stop() }
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func tooLongPathIsRejected() {
        let path = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        #expect(throws: UnixSocketError.pathTooLong) { try UnixSocketServer(path: path).start { _ in nil } }
    }
}

@Suite struct PathsTests {
    @Test func defaultsToDotAmbientInHome() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/me"])
        #expect(p.home.path == "/Users/me/.ambient")
        #expect(p.socket.path == "/Users/me/.ambient/ambient.sock")
        #expect(p.cliLink.path == "/Users/me/.ambient/bin/ambient")
        #expect(p.userHome.path == "/Users/me")
    }

    @Test func ambientHomeOverrides() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/me", "AMBIENT_HOME": "/tmp/a"])
        #expect(p.home.path == "/tmp/a")
        #expect(p.backups.path == "/tmp/a/backups")
    }
}
