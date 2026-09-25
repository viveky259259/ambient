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
        #expect(root["hooks"]?.objectKeys == HookInstaller.spec(for: .claude).events)
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
