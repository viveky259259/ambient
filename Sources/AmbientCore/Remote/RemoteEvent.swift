import Foundation

/// One line from a remote machine's spool, after `RemoteEventDecoder` has checked it. Deliberately separate from
/// `WireMessage`: it has no cases that ask the app to do anything, and nothing converts one into the other.
public struct RemoteEvent: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case sessionStarted, promptSubmitted, toolStarted, toolFinished, toolFailed, needsInput
        case compactStarted, compactFinished, subagentStarted, subagentFinished
        case turnCompleted, turnFailed, sessionEnded, notice
        /// Written by `follow` when the agent's title changes.
        case titleChanged
        /// Written by `follow` when the agent process is gone without a `sessionEnded`.
        case agentExited
    }

    public static let currentVersion = 1
    /// The hub accepts the current protocol version and the one before it.
    public static let supportedVersions = max(1, currentVersion - 1)...currentVersion

    public let v: Int
    public let seq: Int64
    /// 128 random bits as 32 lowercase hex characters.
    public let id: String
    /// The remote clock. Order comes from `seq`; this is only shown.
    public let ts: Date
    public let agent: AgentKind
    public let session: String
    public let kind: Kind
    public let project: String?
    public let tool: String?
    public let title: String?
    /// `permission` or `question`, for `needsInput`.
    public let reason: String?
    public let message: String?

    public init(v: Int = RemoteEvent.currentVersion, seq: Int64, id: String, ts: Date, agent: AgentKind, session: String,
                kind: Kind, project: String? = nil, tool: String? = nil, title: String? = nil, reason: String? = nil,
                message: String? = nil) {
        self.v = v
        self.seq = seq
        self.id = id
        self.ts = ts
        self.agent = agent
        self.session = session
        self.kind = kind
        self.project = project
        self.tool = tool
        self.title = title
        self.reason = reason
        self.message = message
    }

    /// What the event does to a session. Nil for events that change nothing but the title.
    public var eventKind: EventKind? {
        switch kind {
        case .sessionStarted: .sessionStarted
        case .promptSubmitted: .promptSubmitted
        case .toolStarted: .toolStarted(name: tool ?? "tool", detail: nil)
        case .toolFinished: .toolFinished(name: tool ?? "tool", failed: false)
        case .toolFailed: .toolFinished(name: tool ?? "tool", failed: true)
        case .needsInput: .needsInput(reason: reason ?? "question", message: message)
        case .compactStarted: .compactStarted
        case .compactFinished: .compactFinished
        case .subagentStarted: .subagentStarted
        case .subagentFinished: .subagentFinished
        case .turnCompleted: .turnCompleted(summary: message)
        case .turnFailed: .turnFailed(message: message)
        case .sessionEnded, .agentExited: .sessionEnded
        case .notice: message.map { .notice(message: $0) }
        case .titleChanged: nil
        }
    }
}

/// Why a remote line was dropped. `code` is what the audit log records: never any of the line's content.
public enum RemoteRejection: Error, Equatable, Sendable, CustomStringConvertible {
    case tooLong(bytes: Int)
    case notJSON
    case notAnObject
    /// Nested deeper than a flat object allows; checked before parsing, so a hostile line can't exhaust the stack.
    case tooDeep
    case duplicateField(String)
    case unknownField(String)
    case missingField(String)
    case wrongType(String)
    case unsupportedVersion(Int)
    case invalid(String)

    public var code: String {
        switch self {
        case .tooLong: "tooLong"
        case .notJSON: "notJSON"
        case .notAnObject: "notAnObject"
        case .tooDeep: "tooDeep"
        case .duplicateField: "duplicateField"
        case .unknownField: "unknownField"
        case .missingField: "missingField"
        case .wrongType: "wrongType"
        case .unsupportedVersion: "unsupportedVersion"
        case .invalid: "invalid"
        }
    }

    public var description: String {
        switch self {
        case let .tooLong(bytes): "line is \(bytes) bytes"
        case .notJSON: "not JSON"
        case .notAnObject: "not a JSON object"
        case .tooDeep: "nested too deeply"
        case let .duplicateField(f): "duplicate field \(f)"
        case let .unknownField(f): "unknown field \(f)"
        case let .missingField(f): "missing field \(f)"
        case let .wrongType(f): "wrong type for \(f)"
        case let .unsupportedVersion(v): "protocol version \(v)"
        case let .invalid(f): "invalid \(f)"
        }
    }
}

/// The strict decoder for remote spool lines (ER-7, ER-34): an allowlist of flat fields with types and caps,
/// states from an enum, a versioned `v`, and a 64 KB line cap. Anything else rejects the whole line.
public enum RemoteEventDecoder {
    public static let maxLineBytes = 64 * 1024

    /// Caps for text fields. Longer free text is cut; longer identifiers reject the line.
    public enum Caps {
        public static let session = 128
        public static let project = 64
        public static let tool = 64
        public static let title = 80
        public static let message = 160
    }

    static let allowed: Set<String> = ["v", "seq", "id", "ts", "agent", "session", "kind", "project", "tool", "title",
                                       "reason", "message"]
    static let required = ["v", "seq", "id", "ts", "agent", "session", "kind"]
    static let reasons: Set<String> = ["permission", "question"]

    public static func decode(_ line: Data) throws(RemoteRejection) -> RemoteEvent {
        guard line.count <= maxLineBytes else { throw .tooLong(bytes: line.count) }
        guard nesting(of: line) <= 2 else { throw .tooDeep }
        let root: JSONValue
        do { root = try JSONValue.parse(line) } catch { throw .notJSON }
        guard case let .object(members) = root else { throw .notAnObject }

        var fields: [String: JSONValue] = [:]
        for m in members {
            guard allowed.contains(m.key) else { throw .unknownField(m.key) }
            guard fields[m.key] == nil else { throw .duplicateField(m.key) }
            switch m.value {
            case .object, .array: throw .wrongType(m.key)
            default: fields[m.key] = m.value
            }
        }
        for key in required where fields[key] == nil || fields[key] == .null { throw .missingField(key) }

        let v = try integer(fields, "v", in: 0...Int64(Int32.max))
        guard RemoteEvent.supportedVersions.contains(Int(v)) else { throw .unsupportedVersion(Int(v)) }
        let seq = try integer(fields, "seq", in: 1...(1 << 53))
        guard let id = try string(fields, "id"), id.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression) != nil
        else { throw .invalid("id") }
        let ts = try timestamp(fields)
        guard let agentName = try string(fields, "agent"), let agent = AgentKind(rawValue: agentName) else {
            throw .invalid("agent")
        }
        guard let session = try string(fields, "session"),
              session.range(of: #"\A[A-Za-z0-9._:@-]{1,128}\z"#, options: .regularExpression) != nil
        else { throw .invalid("session") }
        guard let kindName = try string(fields, "kind"), let kind = RemoteEvent.Kind(rawValue: kindName) else {
            throw .invalid("kind")
        }
        let reason = try string(fields, "reason")
        if let reason, !reasons.contains(reason) { throw .invalid("reason") }

        return RemoteEvent(v: Int(v), seq: seq, id: id, ts: ts, agent: agent, session: session, kind: kind,
                           project: try text(fields, "project", max: Caps.project),
                           tool: try text(fields, "tool", max: Caps.tool),
                           title: try text(fields, "title", max: Caps.title),
                           reason: reason,
                           message: try text(fields, "message", max: Caps.message))
    }

    /// Plain text only: control, format (including bidirectional overrides and zero-width characters) and
    /// line separator characters are removed, whitespace collapsed, and the result cut to `max`.
    public static func plainText(_ s: String, max: Int) -> String? {
        let kept = s.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                // Tabs and newlines become the spaces `truncate` collapses them into.
                return scalar == "\t" || scalar == "\n"
            default:
                return true
            }
        }
        return Trim.clean(String(String.UnicodeScalarView(kept)), max: max)
    }

    /// The deepest bracket nesting outside strings. A valid line is one flat object: depth 1.
    static func nesting(of line: Data) -> Int {
        var depth = 0, deepest = 0, inString = false, escaped = false
        for byte in line {
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
            default: break
            }
        }
        return deepest
    }

    private static func string(_ fields: [String: JSONValue], _ key: String) throws(RemoteRejection) -> String? {
        switch fields[key] {
        case nil, .null?: return nil
        case let .string(s)?: return s
        default: throw .wrongType(key)
        }
    }

    private static func text(_ fields: [String: JSONValue], _ key: String, max: Int) throws(RemoteRejection) -> String? {
        try string(fields, key).flatMap { plainText($0, max: max) }
    }

    private static func integer(_ fields: [String: JSONValue], _ key: String,
                                in range: ClosedRange<Int64>) throws(RemoteRejection) -> Int64 {
        guard case let .number(raw)? = fields[key] else { throw .wrongType(key) }
        guard let n = Int64(raw), range.contains(n) else { throw .invalid(key) }
        return n
    }

    private static func timestamp(_ fields: [String: JSONValue]) throws(RemoteRejection) -> Date {
        guard case let .number(raw)? = fields["ts"] else { throw .wrongType("ts") }
        // Unix seconds up to the year 5138; a remote clock that's merely wrong is handled by the hub.
        guard let seconds = Double(raw), seconds.isFinite, seconds >= 0, seconds < 1e11 else { throw .invalid("ts") }
        return Date(timeIntervalSince1970: seconds)
    }
}
