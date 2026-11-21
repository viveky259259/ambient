@testable import AmbientApp
@testable import AmbientCore
import Foundation
import Testing

/// HookDoctor against a throwaway home: no real agent settings are read or rewritten.
@MainActor @Suite struct HookDoctorTests {
    @Test func aHomeWithoutAgentsHasNoProblems() throws {
        let box = try AppSandbox()
        let doctor = HookDoctor(paths: box.paths, model: AppModel(prefs: box.preferences(), stateURL: nil))
        doctor.check()
        #expect(doctor.problems.isEmpty)
    }

    @Test func hooksRemovedSinceConnectingAreReportedAndFixed() throws {
        let box = try AppSandbox()
        let claude = box.root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try AgentRecord(connected: [.claude]).save(box.paths)
        try Data("{}".utf8).write(to: claude.appendingPathComponent("settings.json"))

        let doctor = HookDoctor(paths: box.paths, model: AppModel(prefs: box.preferences(), stateURL: nil))
        doctor.check()
        #expect(doctor.problems == [.removed(.claude)])

        #expect(doctor.fix(.removed(.claude)) == nil)
        #expect(doctor.problems.isEmpty)
        #expect(HookInstaller(paths: box.paths).status(.claude) == .installed)
    }

    @Test func outdatedHooksAreQuietlyRewritten() throws {
        let box = try AppSandbox()
        let claude = box.root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let installer = HookInstaller(paths: box.paths)
        try installer.install(.claude)
        // Drop one hook event so the install looks partial, as after an older Ambient.
        let url = try #require(installer.configURL(.claude))
        var root = try JSONValue.parse(String(contentsOf: url, encoding: .utf8))
        let first = try #require(root["hooks"]?.objectKeys?.first)
        root["hooks"]?[first] = nil
        try root.serialized().write(to: url, atomically: true, encoding: .utf8)
        #expect(installer.status(.claude) == .partial)

        let doctor = HookDoctor(paths: box.paths, model: AppModel(prefs: box.preferences(), stateURL: nil))
        doctor.check()
        #expect(installer.status(.claude) == .installed)
        #expect(doctor.problems.isEmpty)
    }
}
