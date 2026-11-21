import Darwin
import Foundation
import Testing
@testable import AmbientBase

/// A unique socket path under /tmp, well inside the 104-byte sun_path limit.
private func qaSocketPath() -> String {
    "/tmp/qab-\(UUID().uuidString.prefix(12)).sock"
}

/// Messages a handler saw, readable from the test thread.
private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func append(_ d: Data) { lock.lock(); items.append(d); lock.unlock() }
    var all: [Data] { lock.lock(); defer { lock.unlock() }; return items }

    /// Waits up to `timeout` for at least `count` messages.
    func wait(for count: Int = 1, timeout: TimeInterval = 15) -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline { usleep(5_000) }
        return all
    }
}

/// Starts a server on a fresh path; the caller stops it.
private func startServer(maxMessageSize: Int = 65_536, path: String = qaSocketPath(),
                         handler: @escaping UnixSocketServer.Handler) throws -> UnixSocketServer {
    let server = UnixSocketServer(path: path, maxMessageSize: maxMessageSize)
    try server.start(handler: handler)
    return server
}

private func systemError(_ body: () throws -> Void) -> (String, Int32)? {
    do { try body() } catch let UnixSocketError.system(call, code) { return (call, code) } catch {}
    return nil
}

private func fileMode(_ path: String) -> Int {
    var st = stat()
    guard lstat(path, &st) == 0 else { return -1 }
    return Int(st.st_mode & 0o777)
}

private func isSocketFile(_ path: String) -> Bool {
    var st = stat()
    return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFSOCK
}

/// Expected replies get a 15-second timeout: a reply returns at once, and a loaded CI runner can stall the process
/// for seconds (see `blockedCooperativePoolStarvesTheServer`). Timeouts under test stay short.
/// Serialized: every test blocks its thread in a socket call, and a parallel run can tie up the whole Swift
/// cooperative pool, which starves the server (see `blockedCooperativePoolStarvesTheServer`).
@Suite("UnixSocket", .serialized)
struct QAUnixSocketTests {
    // MARK: Request / reply

    @Test func echoesAReply() throws {
        let server = try startServer { Data("echo:".utf8) + $0 }
        defer { server.stop() }
        let reply = try UnixSocket.send(Data("hello\n".utf8), to: server.path, timeout: 15, expectReply: true)
        #expect(reply == Data("echo:hello".utf8))
    }

    @Test func aMessageWithoutANewlineEndsAtTheClientsShutdown() throws {
        let server = try startServer { $0 }
        defer { server.stop() }
        let reply = try UnixSocket.send(Data("no newline".utf8), to: server.path, timeout: 15, expectReply: true)
        #expect(reply == Data("no newline".utf8))
    }

    @Test func onlyTheFirstLineIsDelivered() throws {
        let inbox = Inbox()
        let server = try startServer { inbox.append($0); return Data("ok".utf8) }
        defer { server.stop() }
        let reply = try UnixSocket.send(Data("first\nsecond\nthird\n".utf8), to: server.path, timeout: 15, expectReply: true)
        #expect(reply == Data("ok".utf8))
        #expect(inbox.wait() == [Data("first".utf8)])
    }

    @Test func aNilReplyGivesAnEmptyReply() throws {
        let server = try startServer { _ in nil }
        defer { server.stop() }
        #expect(try UnixSocket.send(Data("x\n".utf8), to: server.path, timeout: 15, expectReply: true) == Data())
    }

    @Test func fireAndForgetReturnsNilAndStillDelivers() throws {
        let inbox = Inbox()
        let server = try startServer { inbox.append($0); return Data("ignored".utf8) }
        defer { server.stop() }
        let result = try UnixSocket.send(Data("event\n".utf8), to: server.path)
        #expect(result == nil)
        #expect(inbox.wait() == [Data("event".utf8)])
    }

    @Test(arguments: [Data(), Data("\n".utf8), Data("\nafter".utf8)])
    func emptyMessagesNeverReachTheHandler(payload: Data) throws {
        let inbox = Inbox()
        let server = try startServer { inbox.append($0); return Data("reply".utf8) }
        defer { server.stop() }
        let reply = try UnixSocket.send(payload, to: server.path, timeout: 15, expectReply: true)
        #expect(reply == Data())
        #expect(inbox.all.isEmpty)
    }

    @Test func binaryPayloadsArriveIntact() throws {
        let payload = Data((0...255).map(UInt8.init).filter { $0 != 0x0A })
        let server = try startServer { $0 }
        defer { server.stop() }
        #expect(try UnixSocket.send(payload + Data([0x0A]), to: server.path, timeout: 15, expectReply: true) == payload)
    }

    @Test func aMessageSplitAcrossReadsIsReassembled() throws {
        // Larger than the server's 8 KiB read buffer.
        let payload = Data(repeating: UInt8(ascii: "a"), count: 50_000)
        let server = try startServer { Data("\($0.count)".utf8) }
        defer { server.stop() }
        let reply = try UnixSocket.send(payload + Data("\n".utf8), to: server.path, timeout: 15, expectReply: true)
        #expect(reply == Data("50000".utf8))
    }

    @Test func aReplyLargerThanTheSocketBufferArrivesWhole() throws {
        let big = Data((0..<2_000_000).map { UInt8($0 % 251) })
        let server = try startServer { _ in big }
        defer { server.stop() }
        let reply = try UnixSocket.send(Data("give\n".utf8), to: server.path, timeout: 15, expectReply: true)
        #expect(reply?.count == big.count)
        #expect(reply == big)
    }

    // MARK: Size limit

    @Test func messageAtTheLimitIsAccepted() throws {
        let inbox = Inbox()
        let server = try startServer(maxMessageSize: 16) { inbox.append($0); return Data("ok".utf8) }
        defer { server.stop() }
        let msg = Data(repeating: UInt8(ascii: "m"), count: 16)
        #expect(try UnixSocket.send(msg + Data("\n".utf8), to: server.path, timeout: 15, expectReply: true) == Data("ok".utf8))
        #expect(inbox.wait() == [msg])
    }

    @Test(arguments: [true, false])
    func messageOverTheLimitIsDropped(withNewline: Bool) throws {
        let inbox = Inbox()
        let server = try startServer(maxMessageSize: 16) { inbox.append($0); return Data("ok".utf8) }
        defer { server.stop() }
        var msg = Data(repeating: UInt8(ascii: "m"), count: 17)
        if withNewline { msg.append(0x0A) }
        #expect(try UnixSocket.send(msg, to: server.path, timeout: 15, expectReply: true) == Data())
        #expect(inbox.all.isEmpty)
    }

    @Test func aFloodWithoutANewlineIsCutOff() throws {
        let inbox = Inbox()
        let server = try startServer(maxMessageSize: 10_000) { inbox.append($0); return Data("ok".utf8) }
        defer { server.stop() }
        // The server hangs up mid-message; the client may see an empty reply or a reset. Either way: no handler call.
        let reply = try? UnixSocket.send(Data(repeating: 0x41, count: 200_000), to: server.path, timeout: 15, expectReply: true)
        #expect(reply == nil || reply == Data())
        usleep(100_000)
        #expect(inbox.all.isEmpty)
    }

    // MARK: Timeouts and failures

    @Test func aSlowServerTimesTheClientOut() throws {
        let server = try startServer { _ in Thread.sleep(forTimeInterval: 1.5); return Data("late".utf8) }
        defer { server.stop() }
        let err = systemError { try UnixSocket.send(Data("x\n".utf8), to: server.path, timeout: 0.2, expectReply: true) }
        #expect(err?.0 == "read")
        #expect(err?.1 == EAGAIN)
    }

    @Test func nothingListeningFailsFastOnConnect() {
        let started = Date()
        let err = systemError { try UnixSocket.send(Data("x\n".utf8), to: qaSocketPath()) }
        #expect(err?.0 == "connect")
        #expect(err?.1 == ENOENT)
        #expect(Date().timeIntervalSince(started) < 0.5)
    }

    @Test func aRegularFileIsNotAServer() throws {
        let path = qaSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { unlink(path) }
        let err = systemError { try UnixSocket.send(Data("x\n".utf8), to: path) }
        #expect(err?.0 == "connect")
        #expect(!UnixSocketServer.isListening(path))
    }

    @Test func aStaleSocketRefusesConnections() throws {
        let path = qaSocketPath()
        try makeStaleSocket(at: path)
        defer { unlink(path) }
        let err = systemError { try UnixSocket.send(Data("x\n".utf8), to: path) }
        #expect(err?.0 == "connect")
        #expect(err?.1 == ECONNREFUSED)
    }

    // MARK: Path length

    @Test func pathsOf104BytesOrMoreAreTooLong() {
        let path = "/tmp/" + String(repeating: "p", count: 99)   // 104 bytes
        #expect(path.utf8.count == 104)
        #expect(throws: UnixSocketError.pathTooLong) { try UnixSocket.send(Data(), to: path) }
        #expect(throws: UnixSocketError.pathTooLong) { try UnixSocketServer(path: path).start { _ in nil } }
        #expect(!UnixSocketServer.isListening(path))
        #expect(throws: UnixSocketError.pathTooLong) { try UnixSocket.send(Data(), to: path + String(repeating: "x", count: 500)) }
    }

    @Test func a103BytePathWorksEndToEnd() throws {
        let path = "/tmp/qab-\(UUID().uuidString.prefix(8))-" + String(repeating: "q", count: 103 - 18)
        #expect(path.utf8.count == 103)
        let server = try startServer(path: path) { $0 }
        defer { server.stop() }
        #expect(try UnixSocket.send(Data("edge\n".utf8), to: path, timeout: 15, expectReply: true) == Data("edge".utf8))
    }

    @Test func multibyteCharactersCountAsBytes() {
        // 30 four-byte emoji = 120 bytes, though only 30 characters.
        let path = "/tmp/" + String(repeating: "🚀", count: 30)
        #expect(throws: UnixSocketError.pathTooLong) { try UnixSocket.send(Data(), to: path) }
    }

    // MARK: Server lifecycle

    @Test func socketFileIsPrivate() throws {
        let server = try startServer { _ in nil }
        defer { server.stop() }
        #expect(isSocketFile(server.path))
        #expect(fileMode(server.path) == 0o600)
    }

    @Test func isListeningFollowsTheServer() throws {
        let path = qaSocketPath()
        #expect(!UnixSocketServer.isListening(path))
        let server = try startServer(path: path) { _ in nil }
        #expect(UnixSocketServer.isListening(path))
        server.stop()
        #expect(!UnixSocketServer.isListening(path))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func isListeningDoesNotCallTheHandler() throws {
        let inbox = Inbox()
        let server = try startServer { inbox.append($0); return nil }
        defer { server.stop() }
        #expect(UnixSocketServer.isListening(server.path))
        usleep(100_000)
        #expect(inbox.all.isEmpty)
    }

    @Test func stopWithoutUnlinkLeavesTheFileAndARestartReplacesIt() throws {
        let path = qaSocketPath()
        let first = try startServer(path: path) { _ in Data("1".utf8) }
        first.stop(unlink: false)
        #expect(isSocketFile(path))
        #expect(!UnixSocketServer.isListening(path))
        let second = try startServer(path: path) { _ in Data("2".utf8) }
        defer { second.stop() }
        #expect(try UnixSocket.send(Data("?\n".utf8), to: path, timeout: 15, expectReply: true) == Data("2".utf8))
    }

    @Test func aPathCanBeReboundRightAfterStop() throws {
        let path = qaSocketPath()
        for round in 0..<5 {
            let server = try startServer(path: path) { _ in Data("\(round)".utf8) }
            #expect(try UnixSocket.send(Data("?\n".utf8), to: path, timeout: 15, expectReply: true) == Data("\(round)".utf8))
            server.stop()
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aSecondServerOnALivePathIsRefused() throws {
        let path = qaSocketPath()
        let first = try startServer(path: path) { _ in Data("first".utf8) }
        defer { first.stop() }
        #expect(throws: UnixSocketError.alreadyRunning) { try UnixSocketServer(path: path).start { _ in nil } }
        // The live server is untouched.
        #expect(try UnixSocket.send(Data("?\n".utf8), to: path, timeout: 15, expectReply: true) == Data("first".utf8))
    }

    @Test func aStaleSocketFileIsReplaced() throws {
        let path = qaSocketPath()
        try makeStaleSocket(at: path)
        #expect(isSocketFile(path))
        let server = try startServer(path: path) { _ in Data("fresh".utf8) }
        defer { server.stop() }
        #expect(try UnixSocket.send(Data("?\n".utf8), to: path, timeout: 15, expectReply: true) == Data("fresh".utf8))
    }

    @Test func aLeftoverRegularFileIsReplaced() throws {
        let path = qaSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data("junk".utf8))
        let server = try startServer(path: path) { _ in Data("ok".utf8) }
        defer { server.stop() }
        #expect(isSocketFile(path))
    }

    @Test func bindingInAMissingDirectoryFails() {
        let path = "/tmp/qab-missing-\(UUID().uuidString.prefix(8))/s.sock"
        let err = systemError { try UnixSocketServer(path: path).start { _ in nil } }
        #expect(err?.0 == "bind")
        #expect(err?.1 == ENOENT)
    }

    @Test func stoppingTwiceOrBeforeStartIsSafe() throws {
        UnixSocketServer(path: qaSocketPath()).stop()
        let server = try startServer { _ in nil }
        server.stop()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: server.path))
    }

    @Test func keepsServingAfterAClientHangsUpEarly() throws {
        let server = try startServer { _ in Thread.sleep(forTimeInterval: 0.3); return Data(repeating: 1, count: 100_000) }
        defer { server.stop() }
        // This client gives up before the reply; the server's write must not take the process down (SIGPIPE).
        _ = try? UnixSocket.send(Data("a\n".utf8), to: server.path, timeout: 0.05, expectReply: true)
        usleep(500_000)
        #expect(try UnixSocket.send(Data("b\n".utf8), to: server.path, timeout: 15, expectReply: true)?.count == 100_000)
    }

    @Test func concurrentClientsEachGetTheirOwnReply() throws {
        let server = try startServer { Data("re:".utf8) + $0 }
        defer { server.stop() }
        let path = server.path
        let inbox = Inbox()
        let group = DispatchGroup()
        // Plain threads, not Swift tasks, so the clients don't tie up the cooperative pool.
        for i in 0..<32 {
            group.enter()
            Thread {
                let reply = try? UnixSocket.send(Data("\(i)\n".utf8), to: path, timeout: 15, expectReply: true)
                if reply == Data("re:\(i)".utf8) { inbox.append(Data("\(i)".utf8)) }
                group.leave()
            }.start()
        }
        #expect(group.wait(timeout: .now() + 60) == .success)
        #expect(inbox.all.count == 32)
    }

    @Test func aFewSilentClientsDoNotHoldUpOthers() throws {
        let server = try startServer { _ in Data("pong".utf8) }
        defer { server.stop() }
        let silent = (0..<8).map { _ in rawConnect(server.path) }
        defer { silent.forEach { close($0) } }
        #expect(silent.allSatisfy { $0 >= 0 })
        let started = Date()
        #expect(try UnixSocket.send(Data("x\n".utf8), to: server.path, timeout: 15, expectReply: true) == Data("pong".utf8))
        #expect(Date().timeIntervalSince(started) < 0.5)
    }

    /// Clients blocked in `UnixSocket.send` on every Swift cooperative thread stop the server from serving until they
    /// time out: its per-client work runs on a width-limited concurrent GCD queue. Reproduced in a child process so
    /// the starvation can't spill into other tests. Intermittent: it depends on which side gets threads first.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMBIENT_TEST_CRASHES"] == "1", "Spawns a child process that crashes; set AMBIENT_TEST_CRASHES=1")) func blockedCooperativePoolStarvesTheServer() async {
        await withKnownIssue("BUG: UnixSocketServer stops serving while the process's cooperative pool is blocked in socket calls", isIntermittent: true) {
            await #expect(processExitsWith: .success) {
                let path = "/tmp/qab-st-\(UUID().uuidString.prefix(8)).sock"
                let server = UnixSocketServer(path: path)
                try server.start { $0 }
                let width = ProcessInfo.processInfo.activeProcessorCount * 2
                let failures = await withTaskGroup(of: Int.self) { group in
                    for i in 0..<width {
                        group.addTask {
                            let reply = try? UnixSocket.send(Data("\(i)\n".utf8), to: path, timeout: 1.5, expectReply: true)
                            return reply == Data("\(i)".utf8) ? 0 : 1
                        }
                    }
                    return await group.reduce(0, +)
                }
                server.stop()
                unlink(path)   // stop() may not have unlinked yet if the cancel handler is still starved
                if failures > 0 { exit(1) }
            }
        }
    }

    // MARK: serve() over a socketpair

    @Test func serveReadsOneLineAndReplies() throws {
        let (client, server) = try socketPair()
        defer { close(client) }
        #expect(write(client, "ping\nrest", 9) == 9)
        let inbox = Inbox()
        UnixSocketServer.serve(server, maxMessageSize: 100) { inbox.append($0); return Data("pong".utf8) }
        #expect(inbox.all == [Data("ping".utf8)])
        #expect(readToEnd(client) == Data("pong".utf8))
    }

    @Test func serveGivesUpOnASilentClient() throws {
        let (client, server) = try socketPair()
        defer { close(client) }
        let inbox = Inbox()
        let started = Date()
        UnixSocketServer.serve(server, maxMessageSize: 100) { inbox.append($0); return nil }
        let elapsed = Date().timeIntervalSince(started)
        #expect(inbox.all.isEmpty)
        #expect(elapsed >= 0.9 && elapsed < 3)   // the 1-second receive timeout
    }

    @Test func serveSurvivesAPeerThatAlreadyLeft() throws {
        let (client, server) = try socketPair()
        #expect(write(client, "bye\n", 4) == 4)
        close(client)
        let inbox = Inbox()
        UnixSocketServer.serve(server, maxMessageSize: 100) { inbox.append($0); return Data(repeating: 0, count: 1_000_000) }
        // What it sent still counts.
        #expect(inbox.all == [Data("bye".utf8)])
    }

    @Test func errorsAreEquatable() {
        #expect(UnixSocketError.system("read", EAGAIN) == .system("read", EAGAIN))
        #expect(UnixSocketError.system("read", EAGAIN) != .system("write", EAGAIN))
        #expect(UnixSocketError.pathTooLong != .alreadyRunning)
    }
}

// MARK: - Helpers

/// Leaves a socket file at `path` that nothing listens on, as a crashed server would.
private func makeStaleSocket(at path: String) throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    #expect(fd >= 0)
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    try #require(rc == 0)
}

private func rawConnect(_ path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if rc != 0 { close(fd); return -1 }
    return fd
}

private func socketPair() throws -> (Int32, Int32) {
    var fds: [Int32] = [0, 0]
    try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    return (fds[0], fds[1])
}

private func readToEnd(_ fd: Int32) -> Data {
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4_096)
    while true {
        let n = read(fd, &buf, buf.count)
        if n > 0 { out.append(buf, count: n) } else { break }
    }
    return out
}
