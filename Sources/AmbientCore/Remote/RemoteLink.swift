import Foundation

/// How a machine's link is doing, for every surface that shows it (ER-20).
public enum RemoteHealth: Equatable, Sendable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    /// The transport refused the user: their keys, certificate or SSO need attention. Retries slowly.
    case signInNeeded(String)
    /// The machine's identity changed, so the link stopped until the user approves it again.
    case revoked(String)
    case upgradeNeeded(String)
    case stopped

    public var label: String {
        switch self {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .signInNeeded: "Sign-in needed"
        case .revoked: "Stopped: identity changed"
        case .upgradeNeeded: "Update needed"
        case .stopped: "Stopped"
        }
    }

    public var detail: String? {
        switch self {
        case let .signInNeeded(m), let .revoked(m), let .upgradeNeeded(m): m
        default: nil
        }
    }
}

/// Exponential backoff with jitter, so a fleet of links doesn't reconnect in step.
public struct RemoteBackoff: Sendable {
    public var base: TimeInterval = 1
    public var limit: TimeInterval = 60
    public var jitter = 0.2

    public init() {}

    public func delay(attempt: Int, random: Double = Double.random(in: -1...1)) -> TimeInterval {
        let exact = min(limit, base * pow(2, Double(max(0, attempt - 1))))
        return max(0, exact * (1 + jitter * random))
    }
}

/// One machine's connection: it spawns the transport, runs `follow`, feeds lines through `RemoteIngest` and reconnects
/// with backoff. One way by construction: stdin is closed and nothing is ever sent back.
public final class RemoteLink: @unchecked Sendable {
    public struct Options: Sendable {
        /// With heartbeats every 15 s, this long of silence means the connection is dead.
        public var silenceLimit: TimeInterval = 45
        /// A connection up for this long resets the backoff.
        public var stableAfter: TimeInterval = 30
        public var backoff = RemoteBackoff()

        public init() {}
    }

    /// Takes a batch, and calls its last argument once the batch is applied. The link reads nothing more until then, or
    /// until it's stopped, so a fast machine fills its own pipe and never the queue behind this.
    public typealias Deliver = @Sendable ([RemoteDelivery], RemoteCursor, @escaping @Sendable () -> Void) -> Void
    public typealias Report = @Sendable (RemoteHealth, RemoteHello?) -> Void

    public let machine: Machine
    private let ingest: RemoteIngest
    private let transport: RemoteTransport
    private let audit: RemoteAudit?
    private let options: Options
    private let deliver: Deliver
    private let report: Report

    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    public init(machine: Machine, cursor: RemoteCursor, policy: RemoteIngest.Policy = .init(), options: Options = Options(),
                audit: RemoteAudit? = nil, deliver: @escaping Deliver, report: @escaping Report) {
        self.machine = machine
        self.ingest = RemoteIngest(machine: machine, cursor: cursor, policy: policy, audit: audit)
        self.transport = RemoteTransport(argv: machine.transport)
        self.audit = audit
        self.options = options
        self.deliver = deliver
        self.report = report
    }

    public func start() {
        let thread = Thread { [self] in
            run()
            finished.signal()
        }
        thread.name = "ambient.remote.\(machine.id)"
        thread.start()
    }

    /// Ends the link and returns once it has stopped delivering.
    public func stop() {
        lock.lock()
        stopped = true
        let running = process
        lock.unlock()
        running?.terminate()
        wake.signal()
        finished.wait()
        finished.signal()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private enum Outcome {
        case retry(uptime: TimeInterval)
        case restart
        case signIn(String)
        case refused(RemoteRefusal)
    }

    private func run() {
        var attempt = 0
        var restarts = 0
        report(.connecting, nil)
        while !isStopped {
            let outcome = connectOnce()
            if isStopped { break }
            if case .restart = outcome { restarts += 1 } else { restarts = 0 }
            switch outcome {
            case .restart:
                // A rebuilt spool starts over at once. Asking again right away is a machine that won't settle, and each
                // time costs a transport, so that waits like any other retry.
                guard restarts > 1 else { continue }
                report(.reconnecting(attempt: restarts), nil)
                sleep(options.backoff.delay(attempt: restarts))
            case let .refused(.fingerprintChanged(expected, got)):
                report(.revoked("Expected \(expected), but the machine reports \(got). If that's expected, pair it again."), nil)
                return
            case let .refused(.upgradeNeeded(message)):
                report(.upgradeNeeded(message), nil)
                return
            case let .signIn(message):
                attempt += 1
                report(.signInNeeded(message), nil)
                sleep(options.backoff.limit)
            case let .retry(uptime):
                attempt = uptime >= options.stableAfter ? 1 : attempt + 1
                report(.reconnecting(attempt: attempt), nil)
                sleep(options.backoff.delay(attempt: attempt))
            }
        }
        report(.stopped, nil)
    }

    private func sleep(_ seconds: TimeInterval) {
        _ = wake.wait(timeout: .now() + seconds)
    }

    private func connectOnce() -> Outcome {
        ingest.beginConnection()
        let child = transport.process(for: RemoteTransport.follow(since: ingest.cursor.seq))
        let out = Pipe(), err = Pipe()
        child.standardOutput = out
        child.standardError = err
        let errors = TailBuffer()
        let drained = DispatchSemaphore(value: 0)
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drained.signal()
            } else {
                errors.append(chunk)
            }
        }
        do {
            try child.run()
        } catch {
            return .retry(uptime: 0)
        }
        lock.lock()
        let cancelled = stopped
        if !cancelled { process = child }
        lock.unlock()
        if cancelled { child.terminate() }

        let result = read(child, from: out.fileHandleForReading.fileDescriptor)
        child.terminate()
        child.waitUntilExit()
        // What it printed on the way out is why it left. An ssh ControlPersist master can hold this pipe open, so a
        // short wait, not an end of file.
        _ = drained.wait(timeout: .now() + 0.5)
        err.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        process = nil
        lock.unlock()

        ingest.flush(now: Date())
        if result.wasLinked { audit?.append(.init(action: .linkDown, machine: machine.id)) }
        if let outcome = result.outcome { return outcome }
        if !result.wasLinked, let message = Self.signInProblem(errors.text) {
            audit?.append(.init(action: .signInNeeded, machine: machine.id))
            return .signIn(message)
        }
        return .retry(uptime: result.uptime)
    }

    private func read(_ child: Process, from fd: Int32) -> (outcome: Outcome?, wasLinked: Bool, uptime: TimeInterval) {
        var splitter = RemoteLineSplitter()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var linkedAt: Date?
        var lastHeard = Date()
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)

        func finish(_ outcome: Outcome?) -> (Outcome?, Bool, TimeInterval) {
            (outcome, linkedAt != nil, linkedAt.map { Date().timeIntervalSince($0) } ?? 0)
        }

        while !isStopped {
            let ready = poll(&poller, 1, 1_000)
            if ready < 0 && errno != EINTR { return finish(nil) }
            if ready <= 0 {
                if Date().timeIntervalSince(lastHeard) > options.silenceLimit { return finish(nil) }
                continue
            }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { return finish(nil) }
            lastHeard = Date()

            var batch: [RemoteDelivery] = []
            var hold: TimeInterval = 0
            for line in splitter.feed(Data(buffer[0..<count])) {
                let now = Date()
                switch ingest.receive(line, now: now) {
                case let .linked(hello):
                    linkedAt = now
                    audit?.append(.init(ts: now, action: .linkUp, machine: machine.id, detail: hello.shim))
                    report(.connected, hello)
                case .restart:
                    return finish(.restart)
                case let .refused(reason):
                    return finish(.refused(reason))
                case let .deliver(delivery):
                    batch.append(delivery)
                    // Each delay is the whole wait from now, not a step on top of the last one.
                    hold = max(hold, ingest.delay(after: delivery.event, now: now))
                case .heartbeat, .dropped:
                    break
                }
            }
            if !batch.isEmpty { handOver(batch) }
            // `stop()` may just have been spent on the wait above.
            if hold > 0, !isStopped { sleep(hold) }
            // Waiting here says nothing about the connection.
            lastHeard = Date()
        }
        return finish(nil)
    }

    /// Delivers a batch and waits until it's applied. `stop()` signals the same semaphore, so nothing hangs on the other
    /// side answering: not a main thread that's quitting, and not one that's waiting for this link to stop.
    private func handOver(_ batch: [RemoteDelivery]) {
        deliver(batch, ingest.cursor) { [wake] in wake.signal() }
        wake.wait()
    }

    /// The transport's words for a refused sign-in. Host key failures are the transport's own alarm, so they stop too.
    static func signInProblem(_ stderr: String) -> String? {
        let text = stderr.lowercased()
        let signIn = ["permission denied", "too many authentication failures", "no supported authentication",
                      "certificate has expired", "sso session", "not logged in", "login required"]
        guard signIn.contains(where: text.contains) || text.contains("host key verification failed") else { return nil }
        let lines = stderr.split(whereSeparator: \.isNewline).map(String.init)
        return RemoteEventDecoder.plainText(lines.last(where: { !$0.isEmpty }) ?? stderr, max: 160)
    }

    /// Keeps the end of what the transport printed.
    private final class TailBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
            if data.count > 4_096 { data.removeFirst(data.count - 4_096) }
        }

        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

/// A machine's link as the surfaces show it.
public struct RemoteLinkStatus: Equatable, Sendable {
    public let machine: Machine
    public var health: RemoteHealth
    public var shim: String?
    public var level: RemoteRedaction?
    public var lastEventAt: Date?
    /// The app carries a newer shim than the machine runs.
    public var updateAvailable: Bool

    public init(machine: Machine, health: RemoteHealth = .connecting, shim: String? = nil, level: RemoteRedaction? = nil,
                lastEventAt: Date? = nil, updateAvailable: Bool = false) {
        self.machine = machine
        self.health = health
        self.shim = shim
        self.level = level
        self.lastEventAt = lastEventAt
        self.updateAvailable = updateAvailable
    }

    /// One line for the menu bar and Settings.
    public var summary: String {
        var parts = [health.label]
        if let level { parts.append(level.rawValue) }
        if updateAvailable { parts.append("update available") }
        return parts.joined(separator: " · ")
    }
}
