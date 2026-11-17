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
