import Foundation

/// What a remote session remembers about its machine. The label is refreshed from the paired machine.
public struct MachineRef: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Where a remote session's events come from. Local sessions have none. A session with an origin never has a
/// `HostInfo`: nothing that focuses, signals or scripts a local process may run for it.
public struct RemoteOrigin: Codable, Equatable, Sendable {
    public var machine: MachineRef
    /// The working folder's name. Remote events never carry paths.
    public var project: String?
    /// The highest `seq` applied to this session; older or repeated events are ignored.
    public var lastSeq: Int64
    /// A prompt or result replayed long after it happened: it stays on screen, but it never chimes.
    public var missed: Bool
    /// The machine can't be reached, so what's shown may be out of date.
    public var unreachable: Bool

    public init(machine: MachineRef, project: String? = nil, lastSeq: Int64 = 0, missed: Bool = false, unreachable: Bool = false) {
        self.machine = machine
        self.project = project
        self.lastSeq = lastSeq
        self.missed = missed
        self.unreachable = unreachable
    }

    private enum CodingKeys: String, CodingKey { case machine, project, lastSeq, missed, unreachable }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machine = try c.decode(MachineRef.self, forKey: .machine)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        lastSeq = try c.decode(Int64.self, forKey: .lastSeq)
        missed = try c.decodeIfPresent(Bool.self, forKey: .missed) ?? false
        unreachable = try c.decodeIfPresent(Bool.self, forKey: .unreachable) ?? false
    }
}
