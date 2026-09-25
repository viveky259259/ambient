import Foundation

/// Which hook events Ambient registers for an agent, and what each registration looks like.
public struct AgentHookSpec: Sendable {
    public let agent: AgentKind
    /// The agent's directory under the user's home; its absence means the agent isn't installed.
    public let agentDirectory: String
    public let configFile: String
    public let events: [String]
    let entry: @Sendable (_ command: String, _ event: String) -> JSONValue
}

public enum InstallState: Equatable, Sendable {
    case installed
    /// Some events are missing or point at an old location. Reinstall fixes it.
    case partial
    case notInstalled
    case agentMissing
    case unreadable(String)
}

public enum InstallerError: Error, Equatable, CustomStringConvertible {
    case agentNotFound(AgentKind)
    case unreadable(path: String, reason: String)
    case unexpectedShape(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case let .agentNotFound(agent): "\(agent.displayName) doesn't appear to be installed (no ~/\(HookInstaller.spec(for: agent).agentDirectory))."
        case let .unreadable(path, reason): "Couldn't parse \(path): \(reason). It was left untouched."
        case let .unexpectedShape(path, reason): "\(path) has an unexpected shape (\(reason)). It was left untouched."
        case let .writeFailed(path, reason): "Couldn't write \(path): \(reason)"
        }
    }
}

public struct InstallReport: Sendable {
    public let agent: AgentKind
    public let config: URL
    public let changed: Bool
    public let backup: URL?
    /// The new file contents, for dry runs.
    public let preview: String?
}

/// Adds and removes Ambient's entries in agent hook configs, leaving everything else alone.
public struct HookInstaller: Sendable {
    public let paths: AmbientPaths

    public init(paths: AmbientPaths) {
        self.paths = paths
    }

    public static func spec(for agent: AgentKind) -> AgentHookSpec {
        switch agent {
        case .claude:
            AgentHookSpec(
                agent: .claude, agentDirectory: ".claude", configFile: ".claude/settings.json",
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                         "PermissionRequest", "Notification", "PreCompact", "PostCompact", "SubagentStart",
                         "SubagentStop", "Stop", "StopFailure", "SessionEnd"],
                entry: { command, event in
                    var members: [JSONValue.Member] = [.init("type", .string("command")), .init("command", .string(command))]
                    // Background hooks never delay the agent. SessionEnd runs as the process exits, so wait for it.
                    if event != "SessionEnd" { members.append(.init("async", .bool(true))) }
                    members.append(.init("timeout", .number("5")))
                    return .object(members)
                })
        case .codex:
            AgentHookSpec(
                agent: .codex, agentDirectory: ".codex", configFile: ".codex/hooks.json",
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                         "PreCompact", "PostCompact", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"],
                entry: { command, event in
                    var members: [JSONValue.Member] = [.init("type", .string("command")), .init("command", .string(command))]
                    // Codex always runs SessionEnd synchronously.
                    if event != "SessionEnd" { members.append(.init("async", .bool(true))) }
                    members.append(.init("timeout", .number("5")))
                    return .object(members)
                })
        case .gemini:
            AgentHookSpec(
                agent: .gemini, agentDirectory: ".gemini", configFile: ".gemini/settings.json",
                events: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "PreCompress",
                         "AfterAgent", "SessionEnd"],
                entry: { command, _ in
                    // Gemini hooks are synchronous and timed in milliseconds.
                    .object([.init("name", .string("ambient")), .init("type", .string("command")),
                             .init("command", .string(command)), .init("timeout", .number("1500"))])
                })
        }
    }

    /// The shell command agents run. Guarded, so a removed app never breaks the agent.
    public func command(for agent: AgentKind) -> String {
        let cli = paths.cliLink.path
        let home = paths.userHome.path.hasSuffix("/") ? paths.userHome.path : paths.userHome.path + "/"
        let shown = cli.hasPrefix(home) ? "$HOME/" + cli.dropFirst(home.count) : cli
        return #"[ -x "\#(shown)" ] && "\#(shown)" hook \#(agent.rawValue) || true"#
    }

    public static func isAmbientCommand(_ command: String) -> Bool {
        command.contains("bin/ambient\" hook ") || command.contains("bin/ambient hook ")
    }

    public func configURL(_ agent: AgentKind) -> URL {
        paths.userHome.appendingPathComponent(Self.spec(for: agent).configFile)
    }

    private func agentExists(_ agent: AgentKind) -> Bool {
        var isDir: ObjCBool = false
        let dir = paths.userHome.appendingPathComponent(Self.spec(for: agent).agentDirectory).path
        return FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Status

    public func status(_ agent: AgentKind) -> InstallState {
        guard agentExists(agent) else { return .agentMissing }
        let url = configURL(agent)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .notInstalled }
        let root: JSONValue
        do { root = try Self.parseConfig(text) } catch { return .unreadable(String(describing: error)) }

        let spec = Self.spec(for: agent)
        let current = command(for: agent)
        var exact = 0, any = false
        for event in spec.events {
            let commands = Self.commands(in: root["hooks"]?[event])
            if commands.contains(current) { exact += 1 }
            if commands.contains(where: Self.isAmbientCommand) { any = true }
        }
        // Stale entries under events we no longer register also count.
        if case let .object(members)? = root["hooks"], members.contains(where: { !spec.events.contains($0.key) && Self.commands(in: $0.value).contains(where: Self.isAmbientCommand) }) {
            any = true
        }
        if exact == spec.events.count { return .installed }
        return any ? .partial : .notInstalled
    }

    private static func commands(in eventValue: JSONValue?) -> [String] {
        guard case let .array(groups)? = eventValue else { return [] }
        return groups.flatMap { group -> [String] in
            guard case let .array(entries)? = group["hooks"] else { return [] }
            return entries.compactMap { $0["command"]?.stringValue }
        }
    }

    // MARK: - Install / uninstall

    @discardableResult
    public func install(_ agent: AgentKind, dryRun: Bool = false) throws -> InstallReport {
        try edit(agent, dryRun: dryRun) { hooks in
            let spec = Self.spec(for: agent)
            let command = command(for: agent)
            hooks = Self.removingAmbientEntries(from: hooks)
            for event in spec.events {
                let group = JSONValue.object([.init("hooks", .array([spec.entry(command, event)]))])
                switch hooks[event] {
                case nil: hooks[event] = .array([group])
                case var .array(groups)?:
                    groups.append(group)
                    hooks[event] = .array(groups)
                default:
                    throw InstallerError.unexpectedShape(path: configURL(agent).path, reason: "hooks.\(event) isn't a list")
                }
            }
        }
    }

    @discardableResult
    public func uninstall(_ agent: AgentKind, dryRun: Bool = false) throws -> InstallReport {
        try edit(agent, dryRun: dryRun, createIfMissing: false) { hooks in
            hooks = Self.removingAmbientEntries(from: hooks)
        }
    }

    private static func parseConfig(_ text: String) throws -> JSONValue {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([]) }
        return try JSONValue.parse(text)
    }

    private func edit(_ agent: AgentKind, dryRun: Bool, createIfMissing: Bool = true,
                      _ change: (inout JSONValue) throws -> Void) throws -> InstallReport {
        let url = configURL(agent)
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        guard exists || agentExists(agent) else { throw InstallerError.agentNotFound(agent) }
        guard exists || createIfMissing else {
            return InstallReport(agent: agent, config: url, changed: false, backup: nil, preview: nil)
        }

        let original: String
        do { original = exists ? try String(contentsOf: url, encoding: .utf8) : "" } catch {
            throw InstallerError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        var root: JSONValue
        do { root = try Self.parseConfig(original) } catch {
            throw InstallerError.unreadable(path: url.path, reason: String(describing: error))
        }
        guard case .object = root else {
            throw InstallerError.unexpectedShape(path: url.path, reason: "the top level isn't an object")
        }

        let hadHooks = root["hooks"] != nil
        var hooks = root["hooks"] ?? .object([])
        guard case .object = hooks else {
            throw InstallerError.unexpectedShape(path: url.path, reason: "\"hooks\" isn't an object")
        }
        try change(&hooks)
        // Drop a hooks object that only ever held Ambient's entries.
        root["hooks"] = (hooks == .object([]) && !(hadHooks && root["hooks"] == .object([]))) ? nil : hooks

        let indent = JSONValue.detectIndent(original)
        let trailingNewline = original.hasSuffix("\n") ? "\n" : ""
        let text = root.serialized(indent: indent) + trailingNewline
        guard text != original else {
            return InstallReport(agent: agent, config: url, changed: false, backup: nil, preview: nil)
        }
        if dryRun { return InstallReport(agent: agent, config: url, changed: true, backup: nil, preview: text) }

        // Never write something we can't read back.
        _ = try JSONValue.parse(text)
        let target = url.resolvingSymlinksInPath()
        var backup: URL?
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if exists {
                try paths.ensureHome()
                let stamp = Self.stampFormatter.string(from: Date())
                let name = "\(agent.rawValue)-\(url.deletingPathExtension().lastPathComponent)-\(stamp).json"
                let dest = paths.backups.appendingPathComponent(name)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: target, to: dest)
                backup = dest
            }
            let permissions = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
            try Data(text.utf8).write(to: target, options: .atomic)
            if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        } catch {
            throw InstallerError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
        return InstallReport(agent: agent, config: url, changed: true, backup: backup, preview: nil)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    /// Removes Ambient's hook entries, then any groups and events that only held them.
    static func removingAmbientEntries(from hooks: JSONValue) -> JSONValue {
        guard case let .object(members) = hooks else { return hooks }
        var kept: [JSONValue.Member] = []
        for member in members {
            guard case let .array(groups) = member.value else { kept.append(member); continue }
            var newGroups: [JSONValue] = []
            var touched = false
            for group in groups {
                guard case let .array(entries)? = group["hooks"] else { newGroups.append(group); continue }
                let filtered = entries.filter { !($0["command"]?.stringValue.map(isAmbientCommand) ?? false) }
                if filtered.count == entries.count { newGroups.append(group); continue }
                touched = true
                if filtered.isEmpty { continue }
                var g = group
                g["hooks"] = .array(filtered)
                newGroups.append(g)
            }
            if touched && newGroups.isEmpty { continue }
            kept.append(JSONValue.Member(member.key, .array(newGroups)))
        }
        return .object(kept)
    }
}
