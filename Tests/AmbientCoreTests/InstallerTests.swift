import Foundation
import Testing
@testable import AmbientCore

private struct Sandbox {
    let root: URL
    let paths: AmbientPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("amb-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = AmbientPaths(userHome: root)
    }

    func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    var installer: HookInstaller { HookInstaller(paths: paths) }
}

private let foreignSettings = """
{
  "model": "sonnet",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "say done"
          }
        ]
      }
    ]
  },
  "theme": "dark"
}
"""

@Suite struct InstallerTests {
    @Test func hookCommandUsesHomeRelativeGuardedPath() {
        let paths = AmbientPaths(userHome: URL(fileURLWithPath: "/Users/me"))
        #expect(HookInstaller(paths: paths).command(for: .claude)
                == #"[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true"#)
        let custom = AmbientPaths(userHome: URL(fileURLWithPath: "/Users/me"), home: URL(fileURLWithPath: "/opt/amb"))
        #expect(HookInstaller(paths: custom).command(for: .gemini)
                == #"[ -x "/opt/amb/bin/ambient" ] && "/opt/amb/bin/ambient" hook gemini || true"#)
    }

    @Test func recognizesItsOwnCommands() {
        #expect(HookInstaller.isAmbientCommand(#"[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true"#))
        #expect(HookInstaller.isAmbientCommand("/Users/x/.ambient/bin/ambient hook codex"))
        #expect(!HookInstaller.isAmbientCommand("say done"))
        #expect(!HookInstaller.isAmbientCommand("/usr/local/bin/ambient-lights on"))
    }

    @Test func installsIntoMissingFileWhenAgentExists() throws {
        let box = try Sandbox()
        try box.mkdir(".claude")
        let report = try box.installer.install(.claude)
        #expect(report.changed)
        let root = try JSONValue.parse(box.read(".claude/settings.json"))
        #expect(root["hooks"]?.objectKeys == HookInstaller.spec(for: .claude)?.events)
        let entry = root["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]
        #expect(entry?["async"] == .bool(true))
        #expect(entry?["type"] == .string("command"))
        #expect(box.installer.status(.claude) == .installed)
    }

    @Test func skipsAgentsThatAreNotInstalled() throws {
        let box = try Sandbox()
        #expect(throws: InstallerError.agentNotFound(.gemini)) { try box.installer.install(.gemini) }
        #expect(box.installer.status(.gemini) == .agentMissing)
    }

    @Test func preservesForeignHooksAndKeyOrder() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        try box.installer.install(.claude)
        let root = try JSONValue.parse(box.read(".claude/settings.json"))
        #expect(root.objectKeys == ["model", "hooks", "theme"])
        let stop = root["hooks"]?["Stop"]
        #expect(stop?[0]?["hooks"]?[0]?["command"] == .string("say done"))
        #expect(stop?.arrayCount == 2)
    }

    @Test func reinstallIsByteIdentical() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        try box.installer.install(.claude)
        let first = try box.read(".claude/settings.json")
        let report = try box.installer.install(.claude)
        #expect(!report.changed)
        #expect(try box.read(".claude/settings.json") == first)
    }

    @Test func uninstallRestoresTheOriginal() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        try box.installer.install(.claude)
        try box.installer.uninstall(.claude)
        #expect(try box.read(".claude/settings.json") == foreignSettings)
        #expect(box.installer.status(.claude) == .notInstalled)
    }

    @Test func uninstallPrunesHooksItCreated() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", "{\n  \"model\": \"opus\"\n}\n")
        try box.installer.install(.claude)
        try box.installer.uninstall(.claude)
        #expect(try box.read(".claude/settings.json") == "{\n  \"model\": \"opus\"\n}\n")
    }

    @Test func reinstallReplacesStaleCommands() throws {
        let box = try Sandbox()
        try box.write(".codex/hooks.json", """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/old/place/.ambient/bin/ambient hook codex"
                  }
                ]
              }
            ]
          }
        }
        """)
        #expect(box.installer.status(.codex) == .partial)
        try box.installer.install(.codex)
        let root = try JSONValue.parse(box.read(".codex/hooks.json"))
        #expect(root["hooks"]?["Stop"]?.arrayCount == 1)
        #expect(root["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["command"] == .string(box.installer.command(for: .codex)))
        #expect(box.installer.status(.codex) == .installed)
    }

    @Test func entriesWithAnOldShapeNeedAnUpdate() throws {
        let box = try Sandbox()
        try box.mkdir(".claude")
        try box.installer.install(.claude)
        // Simulate an older release that registered Stop without "async".
        var root = try JSONValue.parse(box.read(".claude/settings.json"))
        root["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["async"] = nil
        try box.write(".claude/settings.json", root.serialized())
        #expect(box.installer.status(.claude) == .partial)
        try box.installer.install(.claude)
        #expect(box.installer.status(.claude) == .installed)
    }

    @Test func codexSessionEndIsSynchronous() throws {
        let box = try Sandbox()
        try box.mkdir(".codex")
        try box.installer.install(.codex)
        let root = try JSONValue.parse(box.read(".codex/hooks.json"))
        #expect(root["hooks"]?["SessionEnd"]?[0]?["hooks"]?[0]?["async"] == nil)
        #expect(root["hooks"]?["Stop"]?[0]?["hooks"]?[0]?["async"] == .bool(true))
    }

    @Test func geminiHooksAreNamedWithMillisecondTimeout() throws {
        let box = try Sandbox()
        try box.write(".gemini/settings.json", "{\n  \"theme\": \"Atom One\"\n}")
        try box.installer.install(.gemini)
        let root = try JSONValue.parse(box.read(".gemini/settings.json"))
        let entry = root["hooks"]?["BeforeTool"]?[0]?["hooks"]?[0]
        #expect(entry?["name"] == .string("ambient"))
        #expect(entry?["timeout"] == .number("1500"))
        #expect(entry?["async"] == nil)
    }

    @Test func antigravityGetsAHookSetNamedAmbientWithTheEventInEachCommand() throws {
        let box = try Sandbox()
        try box.write(".gemini/config/hooks.json", "{\n  \"lint\": {\n    \"Stop\": []\n  }\n}\n")
        try box.mkdir(".gemini/antigravity")
        try box.installer.install(.antigravity)
        let root = try JSONValue.parse(box.read(".gemini/config/hooks.json"))
        #expect(root.objectKeys == ["lint", "ambient"])
        let set = root["ambient"]
        #expect(set?.objectKeys == HookInstaller.spec(for: .antigravity)?.events)
        let start = set?["SessionStart"]?[0]
        #expect(start?["command"]?.stringValue?.hasSuffix(#"hook antigravity SessionStart || true"#) == true)
        #expect(start?["timeout"] == .number("5"))
        let tool = set?["PreToolUse"]?[0]
        #expect(tool?["matcher"] == .string("*"))
        #expect(tool?["hooks"]?[0]?["command"]?.stringValue?.contains("hook antigravity PreToolUse") == true)
        #expect(box.installer.status(.antigravity) == .installed)
    }

    @Test func antigravityIsFoundByAnyOfItsDataDirectories() throws {
        let box = try Sandbox()
        #expect(box.installer.status(.antigravity) == .agentMissing)
        try box.mkdir(".gemini/antigravity-ide")
        #expect(box.installer.status(.antigravity) == .notInstalled)
        try box.installer.install(.antigravity)
        #expect(box.installer.status(.antigravity) == .installed)
    }

    @Test func antigravityStaleHookSetNeedsUpdateAndUninstallRestoresTheFile() throws {
        let box = try Sandbox()
        let original = "{\n  \"lint\": {}\n}\n"
        try box.write(".gemini/config/hooks.json", original)
        try box.mkdir(".gemini/antigravity")
        try box.installer.install(.antigravity)
        let moved = HookInstaller(paths: AmbientPaths(userHome: box.root, home: box.root.appendingPathComponent("elsewhere")))
        #expect(moved.status(.antigravity) == .partial)
        try box.installer.uninstall(.antigravity)
        #expect(try box.read(".gemini/config/hooks.json") == original)
        #expect(box.installer.status(.antigravity) == .notInstalled)
    }

    @Test func cursorHooksAreFlatVersionedAndNeverPermissionHooks() throws {
        let box = try Sandbox()
        try box.mkdir(".cursor")
        try box.installer.install(.cursor)
        let root = try JSONValue.parse(box.read(".cursor/hooks.json"))
        #expect(root.objectKeys == ["version", "hooks"])
        #expect(root["version"] == .number("1"))
        let entry = root["hooks"]?["stop"]?[0]
        #expect(entry?["command"]?.stringValue?.hasSuffix("hook cursor || true") == true)
        #expect(entry?["hooks"] == nil)
        let events = try #require(HookInstaller.spec(for: .cursor)?.events)
        for blocking in ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "subagentStart"] {
            #expect(!events.contains(blocking))
        }
        #expect(box.installer.status(.cursor) == .installed)
        try box.installer.uninstall(.cursor)
        #expect(!FileManager.default.fileExists(atPath: box.root.appendingPathComponent(".cursor/hooks.json").path))
    }

    @Test func cursorKeepsTheUsersOwnHooks() throws {
        let box = try Sandbox()
        let original = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              { "command": "./hooks/audit.sh" }
            ]
          }
        }

        """
        try box.write(".cursor/hooks.json", original)
        try box.installer.install(.cursor)
        let root = try JSONValue.parse(box.read(".cursor/hooks.json"))
        #expect(root["hooks"]?["stop"]?.arrayCount == 2)
        #expect(root["hooks"]?["stop"]?[0]?["command"] == .string("./hooks/audit.sh"))
        try box.installer.install(.cursor)
        #expect(try JSONValue.parse(box.read(".cursor/hooks.json"))["hooks"]?["stop"]?.arrayCount == 2)
        try box.installer.uninstall(.cursor)
        let after = try JSONValue.parse(box.read(".cursor/hooks.json"))
        #expect(after == (try JSONValue.parse(original)))
        #expect(box.installer.status(.cursor) == .notInstalled)
    }

    @Test func copilotGetsAHookFileOfItsOwn() throws {
        let box = try Sandbox()
        try box.mkdir(".copilot")
        let report = try box.installer.install(.copilot)
        #expect(report.config.path.hasSuffix(".copilot/hooks/ambient.json"))
        let root = try JSONValue.parse(box.read(".copilot/hooks/ambient.json"))
        #expect(root["version"] == .number("1"))
        let entry = root["hooks"]?["preToolUse"]?[0]
        #expect(entry?["bash"]?.stringValue?.hasSuffix("hook copilot preToolUse || true") == true)
        #expect(entry?["timeoutSec"] == .number("5"))
        #expect(box.installer.status(.copilot) == .installed)
        #expect(try box.installer.install(.copilot).changed == false)
    }

    @Test func anOwnedFileThatChangedNeedsUpdateAndUninstallRemovesIt() throws {
        let box = try Sandbox()
        try box.mkdir(".copilot")
        try box.installer.install(.copilot)
        try box.write(".copilot/hooks/ambient.json", "{}")
        #expect(box.installer.status(.copilot) == .partial)
        let report = try box.installer.uninstall(.copilot)
        #expect(report.changed)
        let backup = try #require(report.backup)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{}")
        #expect(!FileManager.default.fileExists(atPath: box.root.appendingPathComponent(".copilot/hooks/ambient.json").path))
        #expect(box.installer.status(.copilot) == .notInstalled)
        #expect(try box.installer.uninstall(.copilot).changed == false)
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".copilot"))
        #expect(throws: InstallerError.agentNotFound(.copilot)) { try box.installer.uninstall(.copilot) }
    }

    @Test func openCodeGetsAPluginThatExportsOneFunction() throws {
        let box = try Sandbox()
        try box.mkdir(".config/opencode")
        try box.installer.install(.opencode)
        let plugin = try box.read(".config/opencode/plugins/ambient.js")
        #expect(plugin.contains(#"join(homedir(), ".ambient/bin/ambient")"#))
        #expect(plugin.components(separatedBy: "\nexport ").count == 2)
        #expect(plugin.contains(#"["hook", "opencode"]"#))
        #expect(box.installer.status(.opencode) == .installed)
    }

    @Test func openCodeOutsideHomeUsesTheAbsolutePath() throws {
        let box = try Sandbox()
        try box.mkdir(".local/share/opencode")
        let custom = HookInstaller(paths: AmbientPaths(userHome: box.root, home: URL(fileURLWithPath: "/opt/amb \"x\"")))
        try custom.install(.opencode)
        #expect(try box.read(".config/opencode/plugins/ambient.js").contains(#"const cli = "/opt/amb \"x\"/bin/ambient""#))
    }

    @Test func customAgentsHaveNothingToInstall() throws {
        let box = try Sandbox()
        #expect(HookInstaller.spec(for: .custom) == nil)
        #expect(box.installer.status(.custom) == .agentMissing)
        #expect(throws: InstallerError.agentNotFound(.custom)) { try box.installer.install(.custom) }
        #expect(!AgentKind.hooked.contains(.custom))
    }

    @Test func answeringFromTheIslandMakesOnlyThePermissionHookWait() throws {
        let box = try Sandbox()
        try box.mkdir(".claude")
        try box.mkdir(".codex")
        let on = PermissionSettings(enabled: true, wait: 30)
        let answering = HookInstaller(paths: box.paths, permissions: on)
        try answering.install(.claude)
        try answering.install(.codex)
        for (agent, file) in [(AgentKind.claude, ".claude/settings.json"), (.codex, ".codex/hooks.json")] {
            let root = try JSONValue.parse(box.read(file))
            let permission = root["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]
            #expect(permission?["async"] == nil)
            #expect(permission?["timeout"] == .number("70"))
            // Another wait leaves the hook as it is, so Codex needn't approve it again.
            #expect(HookInstaller(paths: box.paths, permissions: PermissionSettings(enabled: true, wait: 10)).status(agent) == .installed)
            #expect(permission?["command"]?.stringValue?.hasSuffix("hook \(agent.rawValue) --answer || true") == true)
            let other = root["hooks"]?["PreToolUse"]?[0]?["hooks"]?[0]
            #expect(other?["async"] == .bool(true))
            #expect(other?["command"]?.stringValue?.contains("--answer") == false)
            #expect(answering.status(agent) == .installed)
            // Turned off again, the waiting hook is out of date until reinstalled in the background.
            let off = HookInstaller(paths: box.paths, permissions: PermissionSettings())
            #expect(off.status(agent) == .partial)
            try off.install(agent)
            let restored = try JSONValue.parse(box.read(file))["hooks"]?["PermissionRequest"]?[0]?["hooks"]?[0]
            #expect(restored?["async"] == .bool(true))
            #expect(off.status(agent) == .installed)
        }
    }

    @Test func anInstallerFindsTheSavedSettingByItself() throws {
        // Hook repair builds its installer this way: missing the setting, it would undo answering from the island.
        let box = try Sandbox()
        try box.mkdir(".claude")
        let on = PermissionSettings(enabled: true)
        try on.save(box.paths)
        try HookInstaller(paths: box.paths, permissions: on).install(.claude)
        #expect(HookInstaller(paths: box.paths).status(.claude) == .installed)
    }

    @Test func agentsWithoutDecisionsAreUnaffected() throws {
        let box = try Sandbox()
        try box.mkdir(".gemini")
        try HookInstaller(paths: box.paths, permissions: PermissionSettings(enabled: true)).install(.gemini)
        #expect(!(try box.read(".gemini/settings.json")).contains("--answer"))
        #expect(HookInstaller(paths: box.paths, permissions: PermissionSettings()).status(.gemini) == .installed)
    }

    @Test func unparsableConfigIsNeverOverwritten() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", "{ nope")
        #expect(throws: InstallerError.self) { try box.installer.install(.claude) }
        #expect(try box.read(".claude/settings.json") == "{ nope")
        if case .unreadable = box.installer.status(.claude) {} else { Issue.record("expected unreadable") }
    }

    @Test func backsUpBeforeWriting() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        let report = try box.installer.install(.claude)
        let backup = try #require(report.backup)
        #expect(try String(contentsOf: backup, encoding: .utf8) == foreignSettings)
        #expect(backup.path.hasPrefix(box.paths.backups.path))
    }

    @Test func symlinkedConfigStaysASymlink() throws {
        let box = try Sandbox()
        try box.write("dotfiles/claude-settings.json", foreignSettings)
        try box.mkdir(".claude")
        let link = box.root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.root.appendingPathComponent("dotfiles/claude-settings.json"))
        try box.installer.install(.claude)
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try box.read("dotfiles/claude-settings.json").contains("hook claude"))
    }

    @Test func filePermissionsArePreserved() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        let path = box.root.appendingPathComponent(".claude/settings.json").path
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        try box.installer.install(.claude)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func dryRunWritesNothing() throws {
        let box = try Sandbox()
        try box.write(".claude/settings.json", foreignSettings)
        let report = try box.installer.install(.claude, dryRun: true)
        #expect(report.changed)
        #expect(report.preview?.contains("hook claude") == true)
        #expect(try box.read(".claude/settings.json") == foreignSettings)
    }
}
