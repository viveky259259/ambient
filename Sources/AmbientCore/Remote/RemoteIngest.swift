import Foundation

/// How far a machine's spool has been delivered. `epoch` names the spool: a new one restarts `seq`.
public struct RemoteCursor: Codable, Equatable, Sendable {
    public var seq: Int64
    public var epoch: String?

    public init(seq: Int64 = 0, epoch: String? = nil) {
        self.seq = seq
        self.epoch = epoch
    }
}

/// An event ready to apply, with the two things the hub decides about it.
public struct RemoteDelivery: Equatable, Sendable {
    public let event: RemoteEvent
    /// When to record it: the remote time, corrected for clock skew and never in the future.
    public let at: Date
    /// A replay from longer ago than `missedAfter`. It's shown, but never chimes.
    public let missed: Bool

    public init(event: RemoteEvent, at: Date, missed: Bool) {
        self.event = event
        self.at = at
        self.missed = missed
    }
}

/// Why a link stopped and won't retry by itself.
public enum RemoteRefusal: Equatable, Sendable {
    case fingerprintChanged(expected: String, got: String)
    case upgradeNeeded(String)
}

public enum RemoteIngestOutput: Equatable, Sendable {
    case linked(RemoteHello)
    /// The spool was replaced, so the stream's `--since` is meaningless. Reconnect from the cursor.
    case restart
    case refused(RemoteRefusal)
    case heartbeat
    case deliver(RemoteDelivery)
    case dropped
}

/// A token bucket: `delay` says how long to hold back the next event. Holding back rather than dropping means a
/// flood can only delay its own machine, and everything it sent is still in the spool.
public struct RemoteRateLimiter: Sendable {
    public let rate: Double
    public let burst: Double
    private var tokens: Double
    private var updatedAt: Date?

    public init(rate: Double = 50, burst: Double = 500) {
        self.rate = rate
        self.burst = burst
        self.tokens = burst
    }

    /// For replays: more than a full 5 MB spool, whose shortest real lines run about 165 bytes, so a Mac back from sleep
    /// catches up at once. After that, the live rate. A larger `spool_max_bytes` only takes longer to arrive.
    public static var replay: RemoteRateLimiter { RemoteRateLimiter(rate: 50, burst: 40_000) }

    public mutating func delay(now: Date) -> TimeInterval {
        if let updatedAt { tokens = min(burst, tokens + max(0, now.timeIntervalSince(updatedAt)) * rate) }
        updatedAt = now
        tokens -= 1
        return tokens >= 0 ? 0 : -tokens / rate
    }
}

/// Everything the hub decides about one machine's stream, with no I/O of its own beyond the audit log: the
/// handshake, the pinned identity, the cursor, deduplication, replay and pacing. Not thread-safe: `RemoteLink` owns it.
public final class RemoteIngest {
    public struct Policy: Sendable {
        /// A replayed prompt or result older than this shows as missed.
        public var missedAfter: TimeInterval = 600
        /// Clocks further apart than this are corrected for (ER-21).
        public var clockSkewLimit: TimeInterval = 120
        /// How many event ids to remember for deduplication.
        public var rememberedIDs = 4_096

        public init() {}
    }

    public let machine: Machine
    public let policy: Policy
    public private(set) var cursor: RemoteCursor
    /// Delivered, duplicate and rejected lines since this object was created.
    public private(set) var delivered = 0
    public private(set) var duplicates = 0
    public private(set) var rejected = 0

    private let audit: RemoteAudit?
    private var limiter: RemoteRateLimiter
    /// Lives here rather than on a connection, so reconnecting doesn't refill it.
    private var replayLimiter: RemoteRateLimiter
    private var hello: RemoteHello?
    private var skew: TimeInterval = 0
    private var seenIDs = Set<String>()
    private var seenOrder: [String] = []
    private var seenStart = 0
    /// Everything a machine can repeat at will goes through this, so it can't fill the log.
    private var throttle: RemoteAuditThrottle

    public init(machine: Machine, cursor: RemoteCursor, policy: Policy = Policy(),
                limiter: RemoteRateLimiter = RemoteRateLimiter(), replayLimiter: RemoteRateLimiter = .replay,
                audit: RemoteAudit? = nil) {
        self.machine = machine
        self.cursor = cursor
        self.policy = policy
        self.limiter = limiter
        self.replayLimiter = replayLimiter
        self.audit = audit
        self.throttle = RemoteAuditThrottle(audit: audit)
    }

    /// A new connection is starting: it must say hello before anything counts.
    public func beginConnection() {
        hello = nil
    }

    public func receive(_ line: Data, now: Date) -> RemoteIngestOutput {
        let decoded: RemoteLine
        do {
            decoded = try RemoteLineDecoder.decode(line)
        } catch {
            let output = reject(error, now: now)
            // A handshake this hub can't read would otherwise look like a link that never says anything (ER-34).
            // Other lines before the handshake are just a login shell talking.
            if hello == nil, line.range(of: Data(#""type":"hello""#.utf8)) != nil {
                return .refused(.upgradeNeeded("This machine's ambient-remote doesn't match this app. Run `ambient remote add \(machine.id)` to update it."))
            }
            return output
        }
        switch decoded {
        case let .hello(h): return handshake(h, now: now)
        case .heartbeat: return hello == nil ? reject(.invalid("heartbeat"), now: now) : .heartbeat
        case let .event(e): return accept(e, now: now)
        }
    }

    /// How long to hold back the event just delivered. A replay has its own bucket, since an honest one is bounded by
    /// the spool's cap. But `hello.seq` is whatever the machine says, so calling everything a replay only spends that
    /// bucket: from then on it's paced like anything else.
    public func delay(after e: RemoteEvent, now: Date) -> TimeInterval {
        let replay = e.seq <= (hello?.seq ?? 0)
        let wait = replay ? replayLimiter.delay(now: now) : limiter.delay(now: now)
        guard wait > 0 else { return 0 }
        throttle.record(.rateLimited, machine: machine.id, now: now)
        return wait
    }

    /// Writes out audit counts still waiting for their minute. Call when a connection ends.
    public func flush(now: Date) {
        throttle.flush(now: now)
    }

    private func handshake(_ h: RemoteHello, now: Date) -> RemoteIngestOutput {
        guard h.identity == machine.fingerprint else {
            audit?.append(.init(ts: now, action: .fingerprintChanged, machine: machine.id, detail: h.identity))
            return .refused(.fingerprintChanged(expected: machine.fingerprint, got: h.identity))
        }
        guard RemoteEvent.supportedVersions.contains(h.proto) else {
            audit?.append(.init(ts: now, action: .upgradeNeeded, machine: machine.id, detail: "proto \(h.proto)"))
            return .refused(.upgradeNeeded("This machine's ambient-remote speaks protocol \(h.proto). Run `ambient remote add \(machine.id)` to update it."))
        }
        if cursor.epoch != nil, cursor.epoch != h.epoch || h.seq < cursor.seq {
            throttle.record(.spoolReset, machine: machine.id, now: now)
            cursor = RemoteCursor(seq: 0, epoch: h.epoch)
            return .restart
        }
        cursor.epoch = h.epoch
        hello = h
        let measured = now.timeIntervalSince(h.ts)
        skew = abs(measured) > policy.clockSkewLimit ? measured : 0
        return .linked(h)
    }

    private func accept(_ line: RemoteEvent, now: Date) -> RemoteIngestOutput {
        guard let hello else { return reject(.invalid("order"), now: now) }
        // A line spooled before the level was tightened still streams. What counts is the level now.
        let e = line.redacted(to: hello.level)
        guard e.seq > cursor.seq, !seenIDs.contains(e.id) else {
            duplicates += 1
            return .dropped
        }
        if cursor.seq > 0, e.seq > cursor.seq + 1 {
            throttle.record(.spoolGap, machine: machine.id, count: Int(e.seq - cursor.seq - 1), now: now)
        }
        cursor.seq = e.seq
        remember(e.id)
        delivered += 1
        let at = min(e.ts.addingTimeInterval(skew), now)
        let late = e.seq <= hello.seq && now.timeIntervalSince(at) > policy.missedAfter
        return .deliver(RemoteDelivery(event: e, at: at, missed: late && Self.alerts(e.kind)))
    }

    private static func alerts(_ kind: RemoteEvent.Kind) -> Bool {
        switch kind {
        case .needsInput, .turnCompleted, .turnFailed: true
        default: false
        }
    }

    private func remember(_ id: String) {
        seenIDs.insert(id)
        seenOrder.append(id)
        if seenOrder.count - seenStart > policy.rememberedIDs {
            seenIDs.remove(seenOrder[seenStart])
            seenStart += 1
            if seenStart > policy.rememberedIDs {
                seenOrder.removeFirst(seenStart)
                seenStart = 0
            }
        }
    }

    private func reject(_ rejection: RemoteRejection, now: Date) -> RemoteIngestOutput {
        rejected += 1
        throttle.record(.rejected, machine: machine.id, detail: rejection.code, now: now)
        if case let .unsupportedVersion(v) = rejection {
            return .refused(.upgradeNeeded("This machine's ambient-remote speaks protocol \(v). Run `ambient remote add \(machine.id)` to update it."))
        }
        return .dropped
    }
}
