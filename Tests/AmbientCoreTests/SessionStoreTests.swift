import Foundation
import Testing
@testable import AmbientCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func ev(_ kind: EventKind, at seconds: TimeInterval, session: String = "s1", agent: AgentKind = .claude,
                cwd: String? = "/src/api", host: HostInfo? = nil) -> AgentEvent {
    AgentEvent(agent: agent, sessionId: session, cwd: cwd, kind: kind, timestamp: t0.addingTimeInterval(seconds), host: host)
}

@Suite struct SessionStoreTests {
    @Test func aFullTurnEndsDone() {
        let store = SessionStore()
        store.apply(ev(.sessionStarted, at: 0))
        #expect(store.mood == .idle)
        store.apply(ev(.promptSubmitted, at: 1))
        #expect(store.sessions.first?.activity == .thinking)
        #expect(store.mood == .working)
        store.apply(ev(.toolStarted(name: "Bash", detail: "npm test"), at: 2))
        #expect(store.sessions.first?.activity == .tool(name: "Bash", detail: "npm test"))
        store.apply(ev(.toolFinished(name: "Bash", failed: false), at: 3))
        #expect(store.sessions.first?.activity == .thinking)
        let t = store.apply(ev(.turnCompleted(summary: "Green"), at: 30))
        #expect(t?.previous == .thinking)
        #expect(t?.session.activity == .done(summary: "Green"))
        #expect(store.mood == .done)
        #expect(store.sessions.first?.toolCount == 1)
        #expect(store.sessions.first?.turnDuration == 29)
    }

    @Test func unknownSessionIsCreatedOnFirstEvent() {
        let store = SessionStore()
        let t = store.apply(ev(.toolStarted(name: "Read", detail: nil), at: 5))
        #expect(t?.previous == nil)
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.project == "api")
        #expect(store.sessions.first?.id == "claude:s1")
        #expect(store.sessions.first?.turnStartedAt == t0.addingTimeInterval(5))
    }

    @Test func olderEventsAreIgnored() {
        let store = SessionStore()
        store.apply(ev(.toolFinished(name: "Bash", failed: false), at: 10))
        let t = store.apply(ev(.toolStarted(name: "Bash", detail: nil), at: 9))
        #expect(t == nil)
        #expect(store.sessions.first?.activity == .thinking)
    }

    @Test func permissionThenToolRunResumesWork() {
        let store = SessionStore()
        store.apply(ev(.needsInput(reason: "permission", message: "Bash: rm"), at: 1))
        #expect(store.mood == .waiting)
        store.apply(ev(.toolStarted(name: "Bash", detail: "rm"), at: 5))
        #expect(store.mood == .working)
    }

    @Test func waitingOutranksDoneAndErrorAcrossSessions() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 1, session: "a"))
        store.apply(ev(.turnFailed(message: "rate"), at: 2, session: "b"))
        #expect(store.mood == .error)
        store.apply(ev(.needsInput(reason: "permission", message: nil), at: 3, session: "c"))
        #expect(store.mood == .waiting)
        #expect(store.sessions.map(\.sessionId) == ["c", "b", "a"])
        #expect(store.waitingCount == 1)
    }

    @Test func acknowledgingDoneQuietsIt() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 1))
        #expect(store.acknowledge(sessionID: "claude:s1"))
        #expect(store.mood == .idle)
        #expect(!store.acknowledge(sessionID: "claude:s1"))
    }

    @Test func acknowledgingByHostAppOnlyTouchesItsSessions() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 1, session: "a", host: HostInfo(bundleId: "com.apple.Terminal")))
        store.apply(ev(.turnCompleted(summary: nil), at: 1, session: "b", host: HostInfo(bundleId: "com.microsoft.VSCode")))
        #expect(store.acknowledge(hostBundleId: "com.apple.Terminal") == ["claude:a"])
        #expect(store.mood == .done)
    }

    @Test func seeingAPromptSettlesItToWorking() {
        let store = SessionStore()
        store.apply(ev(.needsInput(reason: "permission", message: nil), at: 1, host: HostInfo(bundleId: "com.apple.Terminal")))
        #expect(store.acknowledge(hostBundleId: "com.apple.Terminal") == ["claude:s1"])
        // The user has seen it, and has likely approved a command that's now running.
        #expect(store.mood == .working)
        #expect(store.sessions.first?.activity == .waiting(reason: "permission", message: nil))
    }

    @Test func aNewPromptAsksAgain() {
        let store = SessionStore()
        store.apply(ev(.needsInput(reason: "permission", message: "a"), at: 1))
        store.acknowledge(sessionID: "claude:s1")
        store.apply(ev(.toolFinished(name: "Bash", failed: false), at: 2))
        store.apply(ev(.needsInput(reason: "permission", message: "b"), at: 3))
        #expect(store.mood == .waiting)
    }

    @Test func theSecondEventForTheSamePromptDoesNotAskAgain() {
        // Claude reports one prompt twice: PermissionRequest, then a permission_prompt notification.
        let store = SessionStore()
        store.apply(ev(.needsInput(reason: "permission", message: "Bash: rm"), at: 1))
        store.acknowledge(sessionID: "claude:s1")
        store.apply(ev(.needsInput(reason: "permission", message: "Claude needs your permission to use Bash"), at: 2))
        #expect(store.mood == .working)
    }

    @Test func newPromptResetsAcknowledgement() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 1))
        store.acknowledge(sessionID: "claude:s1")
        store.apply(ev(.promptSubmitted, at: 2))
        store.apply(ev(.turnCompleted(summary: nil), at: 3))
        #expect(store.mood == .done)
    }

    @Test func compactionReturnsToWhatWasBefore() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 1))
        store.acknowledge(sessionID: "claude:s1")
        store.apply(ev(.compactStarted, at: 2))
        #expect(store.mood == .working)
        store.apply(ev(.compactFinished, at: 3))
        #expect(store.sessions.first?.activity == .done(summary: nil))
        #expect(store.mood == .idle)

        store.apply(ev(.toolStarted(name: "Bash", detail: nil), at: 4))
        store.apply(ev(.compactStarted, at: 5))
        store.apply(ev(.compactFinished, at: 6))
        #expect(store.sessions.first?.activity == .thinking)
    }

    @Test func subagentCountNeverGoesNegative() {
        let store = SessionStore()
        store.apply(ev(.subagentFinished, at: 1))
        #expect(store.sessions.first?.subagents == 0)
        store.apply(ev(.subagentStarted, at: 2))
        store.apply(ev(.subagentStarted, at: 3))
        #expect(store.sessions.first?.subagents == 2)
        store.apply(ev(.turnCompleted(summary: nil), at: 4))
        #expect(store.sessions.first?.subagents == 0)
    }

    @Test func noticesDoNotChangeActivity() {
        let store = SessionStore()
        store.apply(ev(.promptSubmitted, at: 1))
        let t = store.apply(ev(.notice(message: "hi"), at: 2))
        #expect(t?.previous == .thinking)
        #expect(t?.session.activity == .thinking)
        #expect(t?.changed == false)
    }

    @Test func sessionEndRemovesIt() {
        let store = SessionStore()
        store.apply(ev(.promptSubmitted, at: 1))
        let t = store.apply(ev(.sessionEnded, at: 2))
        #expect(t?.removed == true)
        #expect(store.sessions.isEmpty)
    }

    @Test func sweepIdlesStaleBusySessions() {
        let store = SessionStore()
        store.apply(ev(.toolStarted(name: "Bash", detail: nil), at: 0))
        #expect(store.sweep(now: t0.addingTimeInterval(599)).isEmpty)
        let changes = store.sweep(now: t0.addingTimeInterval(601))
        #expect(changes.count == 1)
        #expect(store.sessions.first?.activity == .idle)
    }

    @Test func sweepGivesUpOnLongWaits() {
        let store = SessionStore()
        store.apply(ev(.needsInput(reason: "permission", message: nil), at: 0))
        store.sweep(now: t0.addingTimeInterval(1_700))
        #expect(store.mood == .waiting)
        store.sweep(now: t0.addingTimeInterval(1_801))
        #expect(store.mood == .idle)
    }

    @Test func sweepAutoAcknowledgesOldResults() {
        let store = SessionStore()
        store.apply(ev(.turnCompleted(summary: nil), at: 0))
        store.sweep(now: t0.addingTimeInterval(3_601))
        #expect(store.mood == .idle)
        #expect(store.sessions.count == 1)
    }

    @Test func sweepDropsLongIdleSessions() {
        let store = SessionStore()
        store.apply(ev(.sessionStarted, at: 0))
        let changes = store.sweep(now: t0.addingTimeInterval(7_201))
        #expect(changes.first?.removed == true)
        #expect(store.sessions.isEmpty)
    }

    @Test func sweepDropsSessionsWhoseAgentExited() {
        let store = SessionStore(isAlive: { $0 != 4242 })
        store.apply(ev(.promptSubmitted, at: 0, session: "gone", host: HostInfo(agentPid: 4242)))
        store.apply(ev(.promptSubmitted, at: 0, session: "alive", host: HostInfo(agentPid: 7)))
        store.sweep(now: t0.addingTimeInterval(1))
        #expect(store.sessions.map(\.sessionId) == ["alive"])
    }

    @Test func sameSessionIdFromDifferentAgentsAreDistinct() {
        let store = SessionStore()
        store.apply(ev(.promptSubmitted, at: 0, agent: .claude))
        store.apply(ev(.promptSubmitted, at: 0, agent: .gemini))
        #expect(store.sessions.count == 2)
    }

    @Test func hostAndCwdAreKeptWhenLaterEventsOmitThem() {
        let store = SessionStore()
        store.apply(ev(.promptSubmitted, at: 0, host: HostInfo(bundleId: "com.apple.Terminal")))
        store.apply(ev(.turnCompleted(summary: nil), at: 1, cwd: nil, host: nil))
        #expect(store.sessions.first?.host?.bundleId == "com.apple.Terminal")
        #expect(store.sessions.first?.project == "api")
    }

    @Test func sessionsRoundTripThroughJSON() throws {
        let store = SessionStore()
        store.apply(ev(.toolStarted(name: "Bash", detail: "ls"), at: 0))
        let data = try JSONEncoder().encode(store.sessions)
        #expect(try JSONDecoder().decode([Session].self, from: data) == store.sessions)
    }

    @Test func titlesAreSetWithoutTouchingState() {
        let store = SessionStore()
        store.apply(AgentEvent(agent: .claude, sessionId: "a", cwd: "/p", kind: .promptSubmitted, timestamp: Date()))
        let before = store.session(id: "claude:a")
        #expect(store.setTitle("Release checklist", sessionID: "claude:a"))
        #expect(!store.setTitle("Release checklist", sessionID: "claude:a"))
        #expect(!store.setTitle("Anything", sessionID: "claude:missing"))
        let after = store.session(id: "claude:a")
        #expect(after?.title == "Release checklist")
        #expect(after?.activity == before?.activity)
        #expect(after?.lastEventAt == before?.lastEventAt)
        // Later events keep the title.
        store.apply(AgentEvent(agent: .claude, sessionId: "a", cwd: "/p", kind: .turnCompleted(summary: nil), timestamp: Date()))
        #expect(store.session(id: "claude:a")?.title == "Release checklist")
    }
}
