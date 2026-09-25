import Foundation
import Testing
@testable import AmbientCore

@Suite struct StateFileTests {
    private func tempFile() throws -> URL {
        try shortTempDir().appendingPathComponent("state.json")
    }

    @Test func sessionsSurviveARoundTrip() throws {
        let url = try tempFile()
        let store = SessionStore()
        store.apply(AgentEvent(agent: .claude, sessionId: "a", cwd: "/p", kind: .toolStarted(name: "Bash", detail: "ls"),
                               timestamp: Date(timeIntervalSince1970: 50)))
        try StateFile.save(store.sessions, to: url)
        #expect(StateFile.load(from: url) == store.sessions)
    }

    @Test func missingOrCorruptFilesLoadEmpty() throws {
        let url = try tempFile()
        #expect(StateFile.load(from: url).isEmpty)
        try Data("{nope".utf8).write(to: url)
        #expect(StateFile.load(from: url).isEmpty)
    }

    @Test func stateIsPrivate() throws {
        let url = try tempFile()
        try StateFile.save([], to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func restoredSessionsKeepAging() throws {
        let store = SessionStore(isAlive: { _ in false })
        var s = Session(agent: .codex, sessionId: "x", at: Date())
        s.host = HostInfo(agentPid: 999_999)
        store.load([s])
        store.sweep(now: Date())
        #expect(store.sessions.isEmpty)
    }
}
