import Foundation
import AmbientContracts

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

    /// The user's own ssh, with their `~/.ssh/config`: ProxyJump, certificates and ControlMaster all apply.
    /// `BatchMode` makes a sign-in failure an error rather than a prompt nobody can see. This connection stays up with
    /// nobody watching and only ever reads, so it forwards nothing, whatever the config says for that host. A machine
    /// paired before these were here keeps the command it was paired with.
    public static func defaultTransport(host: String) -> [String] {
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15",
         "-o", "ServerAliveCountMax=3", "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ClearAllForwardings=yes", host]
    }

    /// ssh takes anything starting with `-` as an option, even where a host belongs.
    public static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && !host.hasPrefix("-")
    }

    /// Lowercase letters, digits, `.`, `_` and `-`; starts with a letter or digit; at most 32 characters.
    public static func isValidID(_ id: String) -> Bool {
        id.range(of: #"\A[a-z0-9][a-z0-9._-]{0,31}\z"#, options: .regularExpression) != nil
    }

    /// `SHA256:` and 43 base64 characters (an OpenSSH host key fingerprint), or `id:` and 32 lowercase hex.
    public static func isValidFingerprint(_ f: String) -> Bool {
        f.range(of: #"\A(SHA256:[A-Za-z0-9+/]{43}|id:[0-9a-f]{32})\z"#, options: .regularExpression) != nil
    }
}

