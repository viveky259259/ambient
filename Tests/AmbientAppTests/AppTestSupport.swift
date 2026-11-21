@testable import AmbientApp
@testable import AmbientCore
import Foundation

/// A throwaway home and UserDefaults suite, so no test reads or writes the real ~/.ambient or app defaults.
final class AppSandbox {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults

    var paths: AmbientPaths { AmbientPaths(userHome: root) }

    init() throws {
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("amb-app-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "ambient.app.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func preferences() -> Preferences { Preferences(defaults: defaults, paths: paths) }

    /// A second Preferences over the same storage, as on the next launch.
    func relaunched() -> Preferences { Preferences(defaults: UserDefaults(suiteName: suiteName)!, paths: paths) }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

let testNow = Date(timeIntervalSince1970: 1_790_000_000)

func makeSession(_ id: String, agent: AgentKind = .claude, activity: Activity = .thinking,
                 acknowledged: Bool = false, project: String = "api") -> Session {
    var s = Session(agent: agent, sessionId: id, at: testNow)
    s.cwd = "/src/\(project)"
    s.activity = activity
    s.acknowledged = acknowledged
    return s
}

func event(_ kind: EventKind, session: String = "s1", agent: AgentKind = .claude, cwd: String = "/src/api",
           at offset: TimeInterval = 0) -> AgentEvent {
    AgentEvent(agent: agent, sessionId: session, cwd: cwd, kind: kind, timestamp: Date().addingTimeInterval(offset))
}

/// A machine that passes `Machine.isValidID` and `isValidFingerprint`.
func makeMachine(_ id: String = "devbox", label: String? = "Devbox") -> Machine {
    Machine(id: id, label: label, transport: ["ssh", id], fingerprint: "id:" + String(repeating: "a", count: 32))
}
