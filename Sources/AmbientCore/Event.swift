import Foundation

/// A coding agent that Ambient can follow.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex, gemini

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }
}

/// What happened in an agent session, normalized across agents.
public enum EventKind: Codable, Equatable, Sendable {
    case sessionStarted
    case promptSubmitted
    case toolStarted(name: String, detail: String?)
    case toolFinished(name: String, failed: Bool)
    /// The agent is blocked on the user: a permission prompt, a question, an elicitation.
    case needsInput(reason: String, message: String?)
    case compactStarted
    case compactFinished
    case subagentStarted
    case subagentFinished
    case turnCompleted(summary: String?)
    case turnFailed(message: String?)
    case sessionEnded
    /// Informational; doesn't change the session's activity.
    case notice(message: String)
}

/// Where the agent is running, so Ambient can bring the user back to it.
public struct HostInfo: Codable, Equatable, Sendable {
    /// Bundle id of the GUI app the agent runs in (Terminal, iTerm, VS Code, Claude…).
    public var bundleId: String?
    /// `TERM_PROGRAM`, when the agent runs in a terminal.
    public var termProgram: String?
    /// The hook's parent process chain, nearest first. Used to find the host app when `bundleId` is unknown.
    public var pids: [Int32]
    /// The agent process itself. When it's gone, so is the session.
    public var agentPid: Int32?

    // Return addresses: enough to bring the user back to the exact chat, tab or pane.

    /// The agent's controlling terminal, e.g. "/dev/ttys004".
    public var tty: String?
    /// Claude desktop's id for a Code session (`CLAUDE_CODE_HOST_SESSION_ID`).
    public var hostSessionId: String?
    public var tmuxSocket: String?
    public var tmuxPane: String?
    public var cmuxWorkspace: String?
    public var cmuxSurface: String?
    public var cmuxSocket: String?

    public init(bundleId: String? = nil, termProgram: String? = nil, pids: [Int32] = [], agentPid: Int32? = nil,
                tty: String? = nil, hostSessionId: String? = nil, tmuxSocket: String? = nil, tmuxPane: String? = nil,
                cmuxWorkspace: String? = nil, cmuxSurface: String? = nil, cmuxSocket: String? = nil) {
        self.bundleId = bundleId
        self.termProgram = termProgram
        self.pids = pids
        self.agentPid = agentPid
        self.tty = tty
        self.hostSessionId = hostSessionId
        self.tmuxSocket = tmuxSocket
        self.tmuxPane = tmuxPane
        self.cmuxWorkspace = cmuxWorkspace
        self.cmuxSurface = cmuxSurface
        self.cmuxSocket = cmuxSocket
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var cwd: String?
    public var kind: EventKind
    public var timestamp: Date
    public var host: HostInfo?

    public init(agent: AgentKind, sessionId: String, cwd: String?, kind: EventKind,
                timestamp: Date = Date(), host: HostInfo? = nil) {
        self.agent = agent
        self.sessionId = sessionId
        self.cwd = cwd
        self.kind = kind
        self.timestamp = timestamp
        self.host = host
    }

    /// The project the session works in: the last component of its working directory.
    public var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
