import Darwin
import Foundation

public enum UnixSocketError: Error, Equatable {
    case pathTooLong
    case alreadyRunning
    case system(String, Int32)
}

private func sysError(_ call: String) -> UnixSocketError {
    .system(call, errno)
}

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else { throw UnixSocketError.pathTooLong }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return addr
}

private func setTimeout(_ fd: Int32, _ option: Int32, _ seconds: TimeInterval) {
    var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
}

private func noSigPipe(_ fd: Int32) {
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw -> Bool in
        guard var p = raw.baseAddress else { return true }
        var left = raw.count
        while left > 0 {
            let n = Darwin.write(fd, p, left)
            if n < 0 { if errno == EINTR { continue }; return false }
            left -= n
            p += n
        }
        return true
    }
}

public enum UnixSocket {
    /// Connects, sends `data`, and optionally reads a reply until the server closes.
    /// Fails fast when nothing is listening.
    @discardableResult
    public static func send(_ data: Data, to path: String, timeout: TimeInterval = 0.25,
                            expectReply: Bool = false) throws -> Data? {
        var addr = try makeAddress(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw sysError("socket") }
        defer { close(fd) }
        noSigPipe(fd)
        setTimeout(fd, SO_SNDTIMEO, timeout)
        setTimeout(fd, SO_RCVTIMEO, timeout)

        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { throw sysError("connect") }
        guard writeAll(fd, data) else { throw sysError("write") }
        guard expectReply else { return nil }

        shutdown(fd, SHUT_WR)
        var reply = Data()
        var buf = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 { reply.append(buf, count: n); continue }
            if n < 0, errno == EINTR { continue }
            if n < 0 { throw sysError("read") }
            break
        }
        return reply
    }
}

/// Accepts connections on a Unix socket; each connection carries one newline-terminated message
/// and optionally gets one reply.
public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) -> Data?

    public let path: String
    private let maxMessageSize: Int
    private let acceptQueue = DispatchQueue(label: "ambient.socket.accept")
    private let clientQueue = DispatchQueue(label: "ambient.socket.client", attributes: .concurrent)
    private var source: DispatchSourceRead?
    private var unlinkOnCancel = true

    public init(path: String, maxMessageSize: Int = 65_536) {
        self.path = path
        self.maxMessageSize = maxMessageSize
    }

    public func start(handler: @escaping Handler) throws {
        var addr = try makeAddress(path)
        if FileManager.default.fileExists(atPath: path) {
            if Self.isListening(path) { throw UnixSocketError.alreadyRunning }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw sysError("socket") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { let e = sysError("bind"); close(fd); throw e }
        chmod(path, 0o600)
        guard listen(fd, 64) == 0 else { let e = sysError("listen"); close(fd); unlink(path); throw e }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        let clientQueue = self.clientQueue, maxSize = maxMessageSize
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                clientQueue.async { Self.serve(client, maxMessageSize: maxSize, handler: handler) }
            }
        }
        let path = self.path
        source.setCancelHandler { [weak self] in
            close(fd)
            if self?.unlinkOnCancel ?? true { unlink(path) }
        }
        self.source = source
        source.resume()
    }

    public func stop(unlink: Bool = true) {
        unlinkOnCancel = unlink
        source?.cancel()
        source = nil
        // Cancellation is asynchronous; wait so callers can rebind the path right away.
        acceptQueue.sync {}
    }

    /// True when a server accepts connections at `path`.
    public static func isListening(_ path: String) -> Bool {
        do {
            try UnixSocket.send(Data(), to: path, timeout: 0.2)
            return true
        } catch {
            return false
        }
    }

    private static func serve(_ fd: Int32, maxMessageSize: Int, handler: Handler) {
        defer { close(fd) }
        noSigPipe(fd)
        setTimeout(fd, SO_RCVTIMEO, 1)
        setTimeout(fd, SO_SNDTIMEO, 1)

        var message = Data()
        var buf = [UInt8](repeating: 0, count: 8_192)
        reading: while true {
            let n = read(fd, &buf, buf.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            if let newline = buf[..<n].firstIndex(of: UInt8(ascii: "\n")) {
                message.append(buf, count: newline)
                break reading
            }
            message.append(buf, count: n)
            if message.count > maxMessageSize { return }
        }
        guard !message.isEmpty, message.count <= maxMessageSize else { return }
        if let reply = handler(message) { _ = writeAll(fd, reply) }
    }
}
