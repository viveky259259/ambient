import Foundation

/// Which hook events Ambient registers for an agent, and what each registration looks like.
public struct AgentHookSpec: Sendable {
    public let agent: AgentKind
    /// The agent's directory under the user's home; its absence means the agent isn't installed.
    public let agentDirectory: String
    /// Other directories under the user's home that also mean the agent is installed.
    let alsoFoundIn: [String]
    public let configFile: String
    public let events: [String]
    let layout: HookLayout
    let entry: @Sendable (_ command: String, _ event: String) -> JSONValue

    init(agent: AgentKind, agentDirectory: String, alsoFoundIn: [String] = [], configFile: String, events: [String],
         layout: HookLayout = .shared, entry: @escaping @Sendable (_ command: String, _ event: String) -> JSONValue) {
        self.agent = agent
        self.agentDirectory = agentDirectory
        self.alsoFoundIn = alsoFoundIn
        self.configFile = configFile
        self.events = events
        self.layout = layout
        self.entry = entry
    }
}

/// Where Ambient's hooks live in an agent's config file.
enum HookLayout: Sendable {
    /// `"hooks": {event: [{"hooks": [entry]}]}`, next to the user's own groups.
    case shared
    /// `"hooks": {event: [entry]}`, next to the user's own entries, in a file that declares `"version": 1`.
    case flat
    /// `name: {event: [entry]}`, a hook set Ambient owns whole. Tool events wrap the entry in a group that
    /// matches every tool. These agents' payloads don't name the event, so each command does.
    case hookSet(name: String, toolEvents: Set<String>)
    /// A whole file Ambient writes and removes: a hook file of its own, or a plugin.
    case ownedFile

    var key: String {
        switch self {
        case .shared, .flat, .ownedFile: "hooks"
        case let .hookSet(name, _): name
        }
    }
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
        case let .agentNotFound(agent):
            if let spec = HookInstaller.spec(for: agent) {
                "\(agent.displayName) doesn't appear to be installed (no ~/\(spec.agentDirectory))."
            } else {
                "Custom agents connect themselves with `ambient emit --session` or `ambient hook custom`."
            }
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

    /// Nil for custom agents, which have no hooks to install.
    public static func spec(for agent: AgentKind) -> AgentHookSpec? {
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
        case .antigravity:
            AgentHookSpec(
                agent: .antigravity, agentDirectory: ".gemini/antigravity",
                alsoFoundIn: [".gemini/antigravity-ide", ".gemini/antigravity-cli"],
                configFile: ".gemini/config/hooks.json",
                events: ["SessionStart", "PreInvocation", "PreToolUse", "PostToolUse", "Stop"],
                layout: .hookSet(name: "ambient", toolEvents: ["PreToolUse", "PostToolUse"]),
                entry: { command, _ in
                    // Antigravity waits for its hooks and times them in seconds.
                    .object([.init("type", .string("command")), .init("command", .string(command)),
                             .init("timeout", .number("5"))])
                })
        case .cursor:
            AgentHookSpec(
                agent: .cursor, agentDirectory: ".cursor", configFile: ".cursor/hooks.json",
                // Never preToolUse, beforeShellExecution, beforeMCPExecution and the like: Cursor reads their
                // reply as a permission decision, and an observer has none to give. After-* hooks are safe and
                // let Ambient show tools while Cursor works.
                events: ["sessionStart", "beforeSubmitPrompt", "postToolUse", "postToolUseFailure",
                         "afterShellExecution", "afterFileEdit", "afterMCPExecution",
                         "preCompact", "stop", "sessionEnd"],
                layout: .flat,
                entry: { command, _ in
                    .object([.init("command", .string(command)), .init("timeout", .number("5"))])
                })
        case .copilot:
            AgentHookSpec(
                agent: .copilot, agentDirectory: ".copilot", configFile: ".copilot/hooks/ambient.json",
                events: ["sessionStart", "userPromptSubmitted", "preToolUse", "postToolUse", "postToolUseFailure",
                         "notification", "preCompact", "subagentStart", "subagentStop", "agentStop", "errorOccurred",
                         "sessionEnd"],
                layout: .ownedFile,
                entry: { command, _ in
                    // Copilot waits for most hooks; an empty reply means "carry on as usual".
                    .object([.init("type", .string("command")), .init("bash", .string(command)),
                             .init("timeoutSec", .number("5"))])
                })
        case .opencode:
            AgentHookSpec(
                agent: .opencode, agentDirectory: ".config/opencode", alsoFoundIn: [".local/share/opencode"],
                configFile: ".config/opencode/plugins/ambient.js",
                events: [], layout: .ownedFile, entry: { _, _ in .null })
        case .custom:
            nil
        }
    }

    /// The shell command agents run. Guarded, so a removed app never breaks the agent.
    public func command(for agent: AgentKind, event: String? = nil) -> String {
        let cli = paths.cliLink.path
        let home = paths.userHome.path.hasSuffix("/") ? paths.userHome.path : paths.userHome.path + "/"
        let shown = cli.hasPrefix(home) ? "$HOME/" + cli.dropFirst(home.count) : cli
        let hook = event.map { "\(agent.rawValue) \($0)" } ?? agent.rawValue
        return #"[ -x "\#(shown)" ] && "\#(shown)" hook \#(hook) || true"#
    }

    /// Everything under a `.hookSet` key, exactly as Ambient installs it.
    func hookSet(_ spec: AgentHookSpec) -> JSONValue {
        guard case let .hookSet(_, toolEvents) = spec.layout else { return .object([]) }
        return .object(spec.events.map { event in
            let entry = spec.entry(command(for: spec.agent, event: event), event)
            let value: JSONValue = toolEvents.contains(event)
                ? .object([.init("matcher", .string("*")), .init("hooks", .array([entry]))])
                : entry
            return JSONValue.Member(event, .array([value]))
        })
    }

    /// The whole file for an `.ownedFile` agent, exactly as Ambient writes it.
    func ownedContents(_ spec: AgentHookSpec) -> String {
        switch spec.agent {
        case .opencode:
            let home = paths.userHome.path.hasSuffix("/") ? paths.userHome.path : paths.userHome.path + "/"
            let cli = paths.cliLink.path
            return OpenCodePlugin.source(cli: cli.hasPrefix(home) ? .home(String(cli.dropFirst(home.count))) : .absolute(cli))
        default:
            let hooks = JSONValue.object(spec.events.map { event in
                JSONValue.Member(event, .array([spec.entry(command(for: spec.agent, event: event), event)]))
            })
            return JSONValue.object([.init("version", .number("1")), .init("hooks", hooks)]).serialized(indent: "  ") + "\n"
        }
    }

    public static func isAmbientCommand(_ command: String) -> Bool {
        command.contains("bin/ambient\" hook ") || command.contains("bin/ambient hook ")
    }

    /// Nil for custom agents.
    public func configURL(_ agent: AgentKind) -> URL? {
        Self.spec(for: agent).map { paths.userHome.appendingPathComponent($0.configFile) }
    }

    private func agentExists(_ agent: AgentKind) -> Bool {
        guard let spec = Self.spec(for: agent) else { return false }
        return ([spec.agentDirectory] + spec.alsoFoundIn).contains { relative in
            var isDir: ObjCBool = false
            let dir = paths.userHome.appendingPathComponent(relative).path
            return FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
        }
    }

    // MARK: - Status

    public func status(_ agent: AgentKind) -> InstallState {
        guard let spec = Self.spec(for: agent), let url = configURL(agent), agentExists(agent) else { return .agentMissing }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .notInstalled }
        // The file is Ambient's own, so any other contents are an older version of it.
        if case .ownedFile = spec.layout { return text == ownedContents(spec) ? .installed : .partial }
        let root: JSONValue
        do { root = try Self.parseConfig(text) } catch { return .unreadable(String(describing: error)) }

        if case .hookSet = spec.layout {
            guard let set = root[spec.layout.key] else { return .notInstalled }
            return set == hookSet(spec) ? .installed : .partial
        }
        let current = command(for: agent)
        var exact = 0, any = false
        for event in spec.events {
            let wanted = spec.entry(current, event)
            if Self.entries(in: root["hooks"]?[event]).contains(wanted) { exact += 1 }
            if Self.commands(in: root["hooks"]?[event]).contains(where: Self.isAmbientCommand) { any = true }
        }
        // Stale entries under events we no longer register also count.
        if case let .object(members)? = root["hooks"], members.contains(where: { !spec.events.contains($0.key) && Self.commands(in: $0.value).contains(where: Self.isAmbientCommand) }) {
            any = true
        }
        if exact == spec.events.count { return .installed }
        return any ? .partial : .notInstalled
    }

    /// The entries under an event: inside groups, or listed directly in flat layouts.
    private static func entries(in eventValue: JSONValue?) -> [JSONValue] {
        guard case let .array(items)? = eventValue else { return [] }
        return items.flatMap { item -> [JSONValue] in
            if case let .array(entries)? = item["hooks"] { return entries }
            return item["hooks"] == nil ? [item] : []
        }
    }

    private static func commands(in eventValue: JSONValue?) -> [String] {
        entries(in: eventValue).compactMap(command(of:))
    }

    private static func command(of entry: JSONValue) -> String? {
        entry["command"]?.stringValue ?? entry["bash"]?.stringValue
    }

    // MARK: - Install / uninstall

    @discardableResult
    public func install(_ agent: AgentKind, dryRun: Bool = false) throws -> InstallReport {
        let report = try write(agent, dryRun: dryRun)
        if !dryRun { AgentRecord.update(paths, agent, connected: true, seed: connectedNow) }
        return report
    }

    /// Agents whose settings hold Ambient's hooks, current or out of date.
    func connectedNow() -> Set<AgentKind> {
        HookHealth.seed(statuses: Dictionary(uniqueKeysWithValues: AgentKind.hooked.map { ($0, status($0)) }))
    }

    private func write(_ agent: AgentKind, dryRun: Bool) throws -> InstallReport {
        guard let spec = Self.spec(for: agent) else { throw InstallerError.agentNotFound(agent) }
        if case .ownedFile = spec.layout { return try writeOwned(spec, contents: ownedContents(spec), dryRun: dryRun) }
        let path = paths.userHome.appendingPathComponent(spec.configFile).path
        return try edit(agent, dryRun: dryRun) { hooks in
            if case .hookSet = spec.layout {
                hooks = hookSet(spec)
                return
            }
            let command = command(for: agent)
            hooks = Self.removingAmbientEntries(from: hooks)
            for event in spec.events {
                let entry = spec.entry(command, event)
                let item = if case .flat = spec.layout { entry } else { JSONValue.object([.init("hooks", .array([entry]))]) }
                switch hooks[event] {
                case nil: hooks[event] = .array([item])
                case var .array(items)?:
                    items.append(item)
                    hooks[event] = .array(items)
                default:
                    throw InstallerError.unexpectedShape(path: path, reason: "hooks.\(event) isn't a list")
                }
            }
        }
    }

    @discardableResult
    public func uninstall(_ agent: AgentKind, dryRun: Bool = false) throws -> InstallReport {
        guard let spec = Self.spec(for: agent) else { throw InstallerError.agentNotFound(agent) }
        let report: InstallReport
        if case .ownedFile = spec.layout {
            report = try writeOwned(spec, contents: nil, dryRun: dryRun)
        } else {
            let owned = if case .hookSet = spec.layout { true } else { false }
            report = try edit(agent, dryRun: dryRun, createIfMissing: false) { hooks in
                hooks = owned ? .object([]) : Self.removingAmbientEntries(from: hooks)
            }
        }
        if !dryRun { AgentRecord.update(paths, agent, connected: false, seed: connectedNow) }
        return report
    }

    private static func parseConfig(_ text: String) throws -> JSONValue {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([]) }
        return try JSONValue.parse(text)
    }

    /// Writes an `.ownedFile` agent's file, or removes it when `contents` is nil, backing up what was there.
    private func writeOwned(_ spec: AgentHookSpec, contents: String?, dryRun: Bool) throws -> InstallReport {
        let agent = spec.agent
        let url = paths.userHome.appendingPathComponent(spec.configFile)
        let fm = FileManager.default
        let original = try? String(contentsOf: url, encoding: .utf8)
        if original == nil, !agentExists(agent) { throw InstallerError.agentNotFound(agent) }
        guard original != contents else {
            return InstallReport(agent: agent, config: url, changed: false, backup: nil, preview: nil)
        }
        if dryRun { return InstallReport(agent: agent, config: url, changed: true, backup: nil, preview: contents ?? "") }
        do {
            let backup = original == nil ? nil : try backUp(url, agent: agent)
            if let contents {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: url, options: .atomic)
            } else {
                try fm.removeItem(at: url)
            }
            return InstallReport(agent: agent, config: url, changed: true, backup: backup, preview: nil)
        } catch {
            throw InstallerError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    private func backUp(_ url: URL, agent: AgentKind) throws -> URL {
        try paths.ensureHome()
        let stamp = Self.stampFormatter.string(from: Date())
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let name = "\(agent.rawValue)-\(url.deletingPathExtension().lastPathComponent)-\(stamp).\(ext)"
        let dest = paths.backups.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: url.resolvingSymlinksInPath(), to: dest)
        return dest
    }

    private func edit(_ agent: AgentKind, dryRun: Bool, createIfMissing: Bool = true,
                      _ change: (inout JSONValue) throws -> Void) throws -> InstallReport {
        guard let spec = Self.spec(for: agent), let url = configURL(agent) else { throw InstallerError.agentNotFound(agent) }
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

        let key = spec.layout.key
        let hadHooks = root[key] != nil
        var hooks = root[key] ?? .object([])
        guard case .object = hooks else {
            throw InstallerError.unexpectedShape(path: url.path, reason: "\"\(key)\" isn't an object")
        }
        try change(&hooks)
        // Drop a hooks object that only ever held Ambient's entries.
        root[key] = (hooks == .object([]) && !(hadHooks && root[key] == .object([]))) ? nil : hooks
        // Flat hook files only load with a version, which goes first in a new one.
        let version = JSONValue.Member("version", .number("1"))
        if case .flat = spec.layout, root[key] != nil, root["version"] == nil, case let .object(members) = root {
            root = .object([version] + members)
        }
        // Nothing left but the version Ambient added: the file goes, as it came.
        if case .flat = spec.layout, root == .object([version]) {
            if dryRun { return InstallReport(agent: agent, config: url, changed: true, backup: nil, preview: "") }
            do {
                let backup = try backUp(url, agent: agent)
                try fm.removeItem(at: url)
                return InstallReport(agent: agent, config: url, changed: true, backup: backup, preview: nil)
            } catch {
                throw InstallerError.writeFailed(path: url.path, reason: error.localizedDescription)
            }
        }

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
            if exists { backup = try backUp(url, agent: agent) }
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
                // A flat layout lists entries directly.
                if group["hooks"] == nil, let command = command(of: group) {
                    if isAmbientCommand(command) { touched = true } else { newGroups.append(group) }
                    continue
                }
                guard case let .array(entries)? = group["hooks"] else { newGroups.append(group); continue }
                let filtered = entries.filter { !(command(of: $0).map(isAmbientCommand) ?? false) }
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
