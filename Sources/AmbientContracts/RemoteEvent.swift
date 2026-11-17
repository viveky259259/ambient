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
    /// `permission` or `question`, for `needsInput`. The hub works out the finer `Need` itself (`eventKind`).
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
        case .needsInput: Self.needsInput(reason: reason, tool: tool, message: message)
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

    /// Remote machines say only `permission` or `question`, so older hubs can read them. From `ambient-remote` 1.0.7 a
    /// permission request names its tool from the standard level on, and the tool gives the need. Without one, the
    /// full level's message does: the tool's name, or the agent's own words for the prompt.
    private static func needsInput(reason: String?, tool: String?, message: String?) -> EventKind {
        guard reason == Need.permission.rawValue else {
            return .needsInput(reason: reason ?? Need.question.rawValue, message: message)
        }
        let said = Need.fromText(message)
        let (need, name) = tool.map(Need.named) ?? said
        // The message is kept only when it says more than the headline. Today's shim sends the tool's name again.
        return .needsInput(reason: need.rawValue, message: said.detail ?? name)
    }
}
