import Foundation

/// A paired remote machine. The id is how the user names it on the command line and in session ids; the label
/// is only for display. Ambient follows a machine only through its transport, and only while the identity it
/// reports still matches the fingerprint pinned when it was paired.
public struct Machine: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var label: String
    /// The command that reaches the machine, e.g. `["ssh", "devbox"]`. The remote command is appended as one
    /// last argument, a shell string, the way ssh takes it.
    public var transport: [String]
    /// The identity pinned at pairing: `SHA256:…` for an SSH host key, or `id:<32 hex>` for a shim install id.
    public var fingerprint: String
    public var pairedAt: Date

    public init(id: String, label: String? = nil, transport: [String], fingerprint: String, pairedAt: Date = Date()) {
        self.id = id
        self.label = label ?? id
        self.transport = transport
        self.fingerprint = fingerprint
        self.pairedAt = pairedAt
    }

    public var ref: MachineRef { MachineRef(id: id, label: label) }

    /// The user's own ssh, with their `~/.ssh/config`: ProxyJump, certificates, agents and ControlMaster all apply.
    public static func defaultTransport(host: String) -> [String] { ["ssh", host] }

    /// Lowercase letters, digits, `.`, `_` and `-`; starts with a letter or digit; at most 32 characters.
    public static func isValidID(_ id: String) -> Bool {
        id.range(of: #"\A[a-z0-9][a-z0-9._-]{0,31}\z"#, options: .regularExpression) != nil
    }

    /// `SHA256:` and 43 base64 characters (an OpenSSH host key fingerprint), or `id:` and 32 lowercase hex.
    public static func isValidFingerprint(_ f: String) -> Bool {
        f.range(of: #"\A(SHA256:[A-Za-z0-9+/]{43}|id:[0-9a-f]{32})\z"#, options: .regularExpression) != nil
    }
}

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

    public init(machine: MachineRef, project: String? = nil, lastSeq: Int64 = 0) {
        self.machine = machine
        self.project = project
        self.lastSeq = lastSeq
    }
}
