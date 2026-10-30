import Foundation

/// How much text leaves a remote machine. Applied there, before anything is spooled.
public enum RemoteRedaction: String, Codable, CaseIterable, Sendable {
    /// State, agent, project, machine and times.
    case metadata
    /// Adds tool names and short titles. The default.
    case standard
    /// Adds up to 160 characters of the agent's final message, a permission request or an error. Never what you typed.
    case full
}

/// What `follow` says about itself before streaming.
public struct RemoteHello: Equatable, Sendable {
    public let shim: String
    public let proto: Int
    public let caps: Set<String>
    public let level: RemoteRedaction
    /// The newest `seq` in the spool. Events up to here are a replay.
    public let seq: Int64
    /// Changes when the spool is replaced, which restarts `seq`.
    public let epoch: String
    /// The machine's identity, compared with the fingerprint pinned at pairing.
    public let identity: String
    /// The remote clock, for measuring skew.
    public let ts: Date
}

/// `ambient-remote status`: the handshake's fields and the health of the remote side.
public struct RemoteStatus: Equatable, Sendable {
    public enum HookState: String, Sendable { case installed, partial, missing, absent }

    public let hello: RemoteHello
    public let spoolBytes: Int64
    public let spoolPermsOK: Bool
    public let claude: HookState
    public let codex: HookState
}

/// One line of a `follow` stream.
public enum RemoteLine: Equatable, Sendable {
    case hello(RemoteHello)
    case heartbeat(seq: Int64)
    case event(RemoteEvent)
}

/// Decodes `follow`'s output. Control lines have a `type` and their own allowlist; everything else must pass
/// `RemoteEventDecoder`. Neither path can produce a `WireMessage`.
public enum RemoteLineDecoder {
    private static let helloFields: Set<String> = ["v", "type", "shim", "proto", "caps", "level", "seq", "epoch", "identity", "ts"]
    private static let statusFields = helloFields.union(["spoolBytes", "spoolPerms", "claude", "codex"])

    public static func decode(_ line: Data) throws(RemoteRejection) -> RemoteLine {
        let members = try RemoteEventDecoder.members(of: line)
        guard let type = members.first(where: { $0.key == "type" })?.value else {
            return .event(try RemoteEventDecoder.event(from: try RemoteEventDecoder.flatFields(members, allowed: RemoteEventDecoder.allowed)))
        }
        switch type {
        case .string("hello"):
            return .hello(try hello(from: try RemoteEventDecoder.flatFields(members, allowed: helloFields)))
        case .string("heartbeat"):
            let fields = try RemoteEventDecoder.flatFields(members, allowed: ["v", "type", "seq"])
            try checkVersion(fields)
            return .heartbeat(seq: try RemoteEventDecoder.integer(fields, "seq", in: 0...(1 << 53)))
        default:
            throw .invalid("type")
        }
    }

    public static func status(_ line: Data) throws(RemoteRejection) -> RemoteStatus {
        let fields = try RemoteEventDecoder.flatFields(try RemoteEventDecoder.members(of: line), allowed: statusFields)
        guard fields["type"] == .string("status") else { throw .invalid("type") }
        return RemoteStatus(hello: try hello(from: fields),
                            spoolBytes: try RemoteEventDecoder.integer(fields, "spoolBytes", in: 0...(1 << 53)),
                            spoolPermsOK: try RemoteEventDecoder.string(fields, "spoolPerms") == "ok",
                            claude: try hookState(fields, "claude"),
                            codex: try hookState(fields, "codex"))
    }

    private static func checkVersion(_ fields: [String: JSONValue]) throws(RemoteRejection) {
        let v = try RemoteEventDecoder.integer(fields, "v", in: 0...Int64(Int32.max))
        guard RemoteEvent.supportedVersions.contains(Int(v)) else { throw .unsupportedVersion(Int(v)) }
    }

    private static func hello(from fields: [String: JSONValue]) throws(RemoteRejection) -> RemoteHello {
        for key in ["v", "shim", "proto", "caps", "level", "seq", "epoch", "identity", "ts"]
        where fields[key] == nil || fields[key] == .null { throw .missingField(key) }
        try checkVersion(fields)
        guard let shim = try RemoteEventDecoder.string(fields, "shim"),
              shim.range(of: #"\A[0-9A-Za-z.+-]{1,32}\z"#, options: .regularExpression) != nil else { throw .invalid("shim") }
        let proto = try RemoteEventDecoder.integer(fields, "proto", in: 0...Int64(Int32.max))
        guard let caps = try RemoteEventDecoder.string(fields, "caps"),
              caps.range(of: #"\A[a-z,]{0,128}\z"#, options: .regularExpression) != nil else { throw .invalid("caps") }
        guard let name = try RemoteEventDecoder.string(fields, "level"), let level = RemoteRedaction(rawValue: name) else {
            throw .invalid("level")
        }
        guard let epoch = try RemoteEventDecoder.string(fields, "epoch"),
              epoch.range(of: #"\A[0-9a-f]{16}\z"#, options: .regularExpression) != nil else { throw .invalid("epoch") }
        guard let identity = try RemoteEventDecoder.string(fields, "identity"), Machine.isValidFingerprint(identity) else {
            throw .invalid("identity")
        }
        return RemoteHello(shim: shim, proto: Int(proto), caps: Set(caps.split(separator: ",").map(String.init)), level: level,
                           seq: try RemoteEventDecoder.integer(fields, "seq", in: 0...(1 << 53)), epoch: epoch, identity: identity,
                           ts: try RemoteEventDecoder.timestamp(fields))
    }

    private static func hookState(_ fields: [String: JSONValue], _ key: String) throws(RemoteRejection) -> RemoteStatus.HookState {
        guard let name = try RemoteEventDecoder.string(fields, key), let state = RemoteStatus.HookState(rawValue: name) else {
            throw .invalid(key)
        }
        return state
    }
}
