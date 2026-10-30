import Foundation

/// Answering permission prompts from the island. Off unless the user turns it on, and kept in ~/.ambient so
/// the app and the CLI, which installs the hooks, agree on it.
public struct PermissionSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Seconds the island waits for an answer before the agent asks in its own way.
    public var wait = 20

    public static let waits = [10, 20, 30, 60]
    /// How long an agent lets the permission hook run: the longest wait and a margin. Fixed, so choosing another
    /// wait never changes the hook itself (Codex asks you to approve a changed hook again).
    public static let hookTimeout = (waits.last ?? 60) + 10

    public init(enabled: Bool = false, wait: Int = 20) {
        self.enabled = enabled
        self.wait = wait
    }

    /// The saved settings, or the defaults (off) when there are none or they can't be read.
    public static func load(_ paths: AmbientPaths) -> PermissionSettings {
        guard let data = try? Data(contentsOf: paths.permissionSettings),
              var settings = try? JSONDecoder().decode(PermissionSettings.self, from: data) else { return PermissionSettings() }
        // One of the waits Settings offers: a hand-edited value would match none of them.
        let wait = settings.wait
        settings.wait = waits.min { abs($0 - wait) < abs($1 - wait) } ?? 20
        return settings
    }

    public func save(_ paths: AmbientPaths) throws {
        try paths.ensureHome()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: paths.permissionSettings, options: .atomic)
    }
}

extension AmbientPaths {
    public var permissionSettings: URL { home.appendingPathComponent("permissions.json") }
}

/// A permission prompt the island may answer for the agent.
public struct PermissionAsk: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// The prompt as an event: a `needsInput(reason: "permission")` for the session.
    public let event: AgentEvent
    /// The tool as the agent names it, e.g. "Bash".
    public let toolName: String
    /// What it would do: the command's first words, a file name, a host. At most 80 characters.
    public let hint: String?

    public init(id: String = UUID().uuidString, event: AgentEvent, toolName: String, hint: String?) {
        self.id = id
        self.event = event
        self.toolName = toolName
        self.hint = hint
    }

    /// The ask for a permission hook's payload, or nil when the event isn't a permission request.
    public static func make(event: AgentEvent, payload: HookPayload) -> PermissionAsk? {
        guard case .needsInput(reason: "permission", _) = event.kind,
              payload.string("hook_event_name") == "PermissionRequest" else { return nil }
        let name = payload.string("tool_name") ?? "tool"
        return PermissionAsk(event: event, toolName: name,
                             hint: ToolNames.detail(name: name, input: payload.object("tool_input")))
    }

    public var tool: String { ToolNames.display(toolName) }
}

/// The user's answer. `ask` means "no answer": the agent shows its own prompt as if Ambient weren't there.
public enum PermissionAnswer: String, Codable, Sendable {
    case allow, deny, ask
}

public enum PermissionReply {
    /// Agents whose permission hook accepts a decision. Antigravity, Cursor and Gemini have none.
    public static let agents: Set<AgentKind> = [.claude, .codex]

    /// What the hook prints. Claude Code and Codex read the same shape; Codex rejects any field beyond
    /// `behavior` and `message`, so allowing never carries rules or rewritten input: it's for this call only.
    public static func stdout(_ answer: PermissionAnswer) -> String? {
        let decision: String
        switch answer {
        case .allow: decision = #"{"behavior":"allow"}"#
        case .deny: decision = #"{"behavior":"deny","message":"The user denied this from Ambient's island."}"#
        case .ask: return nil
        }
        return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":"# + decision + "}}\n"
    }
}

/// Permission prompts waiting for the user, oldest first. Nothing in here ever answers on the user's
/// behalf: a prompt nobody answers, or one the agent moved past, leaves with `ask`.
public struct PermissionQueue: Sendable {
    public struct Entry: Equatable, Sendable {
        public let ask: PermissionAsk
        public let deadline: Date
    }

    /// More than this, and new prompts go straight to the agent.
    public static let capacity = 8

    public private(set) var entries: [Entry] = []

    public init() {}

    public var current: Entry? { entries.first }

    /// Queues a prompt; false when the queue is full.
    public mutating func add(_ ask: PermissionAsk, now: Date, wait: TimeInterval) -> Bool {
        guard entries.count < Self.capacity, !entries.contains(where: { $0.ask.id == ask.id }) else { return false }
        entries.append(Entry(ask: ask, deadline: now.addingTimeInterval(wait)))
        return true
    }

    /// Takes a prompt out of the queue, if it's still there.
    @discardableResult
    public mutating func remove(_ id: String) -> PermissionAsk? {
        guard let i = entries.firstIndex(where: { $0.ask.id == id }) else { return nil }
        return entries.remove(at: i).ask
    }

    /// Prompts whose time is up.
    public mutating func expire(now: Date) -> [PermissionAsk] {
        let (gone, kept) = (entries.filter { $0.deadline <= now }, entries.filter { $0.deadline > now })
        entries = kept
        return gone.map(\.ask)
    }

    /// Prompts a later event shows the agent no longer waits on: its turn moved on or ended, or the tool ran
    /// (answered in the agent's own app, say).
    public mutating func withdraw(after event: AgentEvent) -> [PermissionAsk] {
        let gone = entries.filter { entry in
            let ask = entry.ask
            guard ask.event.agent == event.agent, ask.event.sessionId == event.sessionId,
                  event.timestamp > ask.event.timestamp else { return false }
            switch event.kind {
            case .promptSubmitted, .turnCompleted, .turnFailed, .sessionEnded: return true
            case let .toolFinished(name, _): return name == ask.toolName
            default: return false
            }
        }
        entries.removeAll { entry in gone.contains { $0.ask.id == entry.ask.id } }
        return gone.map(\.ask)
    }
}

/// `ambient hook <agent> [event] [--answer]`. `--answer` is only on the permission hook Ambient installs
/// when answering from the island is on; that hook is the only one an agent waits for.
public struct HookArguments: Equatable, Sendable {
    public let agent: AgentKind
    public let eventHint: String?
    public let answer: Bool

    public init?(_ arguments: [String]) {
        let words = arguments.filter { !$0.hasPrefix("--") }
        guard let name = words.first, let agent = AgentKind(rawValue: name) else { return nil }
        self.agent = agent
        eventHint = words.dropFirst().first
        answer = arguments.contains("--answer")
    }
}
