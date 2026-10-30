import Foundation
import Testing
@testable import AmbientCore

private func sandbox() throws -> AmbientPaths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("amb-health-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return AmbientPaths(userHome: root)
}

@Suite struct AgentRecordTests {
    @Test func installingAndRemovingIsRemembered() throws {
        let paths = try sandbox()
        #expect(AgentRecord.load(paths) == nil)
        try FileManager.default.createDirectory(at: paths.userHome.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let installer = HookInstaller(paths: paths)
        try installer.install(.claude, dryRun: true)
        #expect(AgentRecord.load(paths) == nil)
        try installer.install(.claude)
        #expect(AgentRecord.load(paths)?.connected == [.claude])
        try installer.uninstall(.claude)
        #expect(AgentRecord.load(paths)?.connected == [])
    }

    @Test func theFirstRecordCountsAgentsConnectedBeforeIt() throws {
        let paths = try sandbox()
        let fm = FileManager.default
        for dir in [".claude", ".codex", ".gemini"] {
            try fm.createDirectory(at: paths.userHome.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        let installer = HookInstaller(paths: paths)
        try installer.install(.claude)
        try installer.install(.codex)
        // As on a Mac upgraded from an Ambient that kept no record.
        try fm.removeItem(at: paths.agentRecord)
        try installer.install(.gemini)
        #expect(AgentRecord.load(paths)?.connected == [.claude, .codex, .gemini])

        try fm.removeItem(at: paths.agentRecord)
        try installer.uninstall(.gemini)
        #expect(AgentRecord.load(paths)?.connected == [.claude, .codex])
    }

    @Test func roundTrips() throws {
        let paths = try sandbox()
        let record = AgentRecord(connected: [.codex, .gemini])
        try record.save(paths)
        #expect(AgentRecord.load(paths) == record)
    }
}

@Suite struct HookHealthTests {
    @Test func onlyConnectedAgentsHaveProblems() {
        let statuses: [AgentKind: InstallState] = [.claude: .notInstalled, .codex: .unreadable("bad"), .gemini: .notInstalled,
                                                    .antigravity: .agentMissing]
        #expect(HookHealth.problems(statuses: statuses, connected: [.claude, .codex, .antigravity])
                == [.removed(.claude), .unreadable(.codex)])
    }

    @Test func outOfDateHooksAreRepairedNotReported() {
        let statuses: [AgentKind: InstallState] = [.claude: .partial, .codex: .installed]
        #expect(HookHealth.problems(statuses: statuses, connected: [.claude, .codex]).isEmpty)
        #expect(HookHealth.outdated(statuses: statuses) == [.claude])
    }

    @Test func aMacWithoutARecordCountsWhatsInstalled() {
        let statuses: [AgentKind: InstallState] = [.claude: .installed, .codex: .partial, .gemini: .notInstalled, .antigravity: .agentMissing]
        #expect(HookHealth.seed(statuses: statuses) == [.claude, .codex])
    }

    @Test func everyProblemSaysWhatFixesIt() {
        #expect(HookProblem.removed(.claude).summary == "Claude's hooks were removed")
        #expect(HookProblem.silent(.codex).remedy.contains("/hooks"))
        #expect(HookProblem.silent(.claude).remedy.contains("Restart"))
    }
}

@Suite struct AgentExecutableTests {
    @Test func anUpdateChangesTheFingerprint() throws {
        let paths = try sandbox()
        let home = paths.userHome.path
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(home)/.local/share/claude/versions", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(home)/.local/bin", withIntermediateDirectories: true)
        #expect(AgentExecutable.fingerprint(.claude, home: home) == nil)
        try Data("v1".utf8).write(to: URL(fileURLWithPath: "\(home)/.local/share/claude/versions/2.1.1"))
        try Data("v2!".utf8).write(to: URL(fileURLWithPath: "\(home)/.local/share/claude/versions/2.1.2"))
        try fm.createSymbolicLink(atPath: "\(home)/.local/bin/claude", withDestinationPath: "\(home)/.local/share/claude/versions/2.1.1")
        let before = try #require(AgentExecutable.fingerprint(.claude, home: home))
        #expect(before.contains("versions/2.1.1"))
        try fm.removeItem(atPath: "\(home)/.local/bin/claude")
        try fm.createSymbolicLink(atPath: "\(home)/.local/bin/claude", withDestinationPath: "\(home)/.local/share/claude/versions/2.1.2")
        #expect(AgentExecutable.fingerprint(.claude, home: home) != before)
    }

    @Test func executablesBelongToAgentsByPath() {
        #expect(ProcessTree.agent(forExecutable: "/Users/me/.local/share/claude/versions/2.1.299") == .claude)
        #expect(ProcessTree.agent(forExecutable: "/opt/homebrew/bin/claude") == .claude)
        #expect(ProcessTree.agent(forExecutable: "/opt/homebrew/bin/codex") == .codex)
        #expect(ProcessTree.agent(forExecutable: "/Users/me/.local/bin/agy") == .antigravity)
        #expect(ProcessTree.agent(forExecutable: "/opt/homebrew/bin/node") == nil)
        #expect(ProcessTree.agent(forExecutable: "/usr/bin/codex-code-mode-host") == nil)
    }

    @Test func helpersOfASessionAreNotSessions() {
        func process(_ pid: Int32, _ agent: AgentKind = .claude) -> AgentProcess {
            AgentProcess(agent: agent, pid: pid, started: Date(), cpuSeconds: 30, interactive: true)
        }
        // 10 is a session in a shell, 11 a helper it started, 20 another session.
        let found = ProcessTree.sessions([process(10), process(11), process(20, .codex)], parents: [10: 5, 11: 10, 20: 5])
        #expect(found.map(\.pid) == [10, 20])
    }

    @Test func listingTerminalSessionsWorks() {
        // Whatever runs on this Mac: only shape and sanity.
        for p in ProcessTree.interactiveAgents() {
            #expect(p.interactive && p.pid > 0 && p.cpuSeconds >= 0)
        }
    }
}

@Suite struct SilenceDetectorTests {
    private let since = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { since.addingTimeInterval(3_600) }

    private func process(_ pid: Int32 = 42, agent: AgentKind = .claude, startedAfter: TimeInterval = 60,
                         cpu: Double = 30, interactive: Bool = true, age: TimeInterval? = nil) -> AgentProcess {
        let started = age.map { now.addingTimeInterval(-$0) } ?? since.addingTimeInterval(startedAfter)
        return AgentProcess(agent: agent, pid: pid, started: started, cpuSeconds: cpu, interactive: interactive)
    }

    @Test func aBusySessionThatNeverReportedIsSilent() {
        let detector = SilenceDetector()
        #expect(detector.silent([process()], now: now, since: [.claude: since]) == [.claude])
    }

    @Test func aSessionThatReportedIsFine() {
        var detector = SilenceDetector()
        detector.heard(from: .claude, host: HostInfo(pids: [7, 42, 1], agentPid: 42))
        #expect(detector.silent([process()], now: now, since: [.claude: since]).isEmpty)
    }

    @Test func cautiousAboutEverythingElse() {
        let detector = SilenceDetector()
        let quiet = [
            process(interactive: false),                     // an app's helper
            process(age: 60),                                // too new to judge
            process(cpu: 2),                                 // idle at its prompt
            process(startedAfter: -10),                      // started before its hooks were in place
            process(agent: .codex),                          // an agent not being watched
        ]
        for p in quiet { #expect(detector.silent([p], now: now, since: [.claude: since]).isEmpty, "\(p)") }
    }

    @Test func forgetsExitedProcesses() {
        var detector = SilenceDetector()
        detector.heard(from: .claude, host: HostInfo(pids: [42], agentPid: 42))
        detector.keep(only: [7])
        #expect(detector.silent([process()], now: now, since: [.claude: since]) == [.claude])
    }
}
