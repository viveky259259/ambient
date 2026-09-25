import Foundation
import Testing
@testable import AmbientCore

private let t0 = Date(timeIntervalSince1970: 2_000_000)

/// Runs events through a store and returns the last transition.
private func transition(_ kinds: [(EventKind, TimeInterval)], session: String = "s") -> Transition {
    let store = SessionStore()
    var last: Transition?
    for (kind, at) in kinds {
        last = store.apply(AgentEvent(agent: .claude, sessionId: session, cwd: "/p", kind: kind, timestamp: t0.addingTimeInterval(at)))
    }
    return last!
}

private let loud = AlertPolicy.Settings(notifications: true, sounds: true, doneThreshold: 20, quiet: false)

@Suite struct AlertPolicyTests {
    @Test func longTurnFinishingAlerts() {
        let t = transition([(.promptSubmitted, 0), (.turnCompleted(summary: nil), 60)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false) == .init(mood: .done, notify: true, sound: true))
    }

    @Test func quickTurnFinishingStaysQuiet() {
        let t = transition([(.promptSubmitted, 0), (.turnCompleted(summary: nil), 5)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false) == nil)
    }

    @Test func waitingAlwaysAlertsRegardlessOfDuration() {
        let t = transition([(.promptSubmitted, 0), (.needsInput(reason: "permission", message: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false)?.mood == .waiting)
    }

    @Test func errorsAlert() {
        let t = transition([(.promptSubmitted, 0), (.turnFailed(message: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false)?.mood == .error)
    }

    @Test func noAlertWhenTheUserIsAlreadyThere() {
        let t = transition([(.promptSubmitted, 0), (.needsInput(reason: "permission", message: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: true) == nil)
    }

    @Test func repeatedWaitingDoesNotAlertTwice() {
        let t = transition([(.promptSubmitted, 0), (.needsInput(reason: "permission", message: "a"), 1),
                            (.needsInput(reason: "permission", message: "b"), 2)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false) == nil)
    }

    @Test func workingNeverAlerts() {
        let t = transition([(.promptSubmitted, 0), (.toolStarted(name: "Bash", detail: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false) == nil)
    }

    @Test func quietModeSilencesEverything() {
        var quiet = loud
        quiet.quiet = true
        let t = transition([(.promptSubmitted, 0), (.needsInput(reason: "permission", message: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: quiet, hostIsFrontmost: false) == nil)
    }

    @Test func channelsFollowSettings() {
        let settings = AlertPolicy.Settings(notifications: false, sounds: true, doneThreshold: 20, quiet: false)
        let t = transition([(.promptSubmitted, 0), (.turnFailed(message: nil), 1)])
        #expect(AlertPolicy.decide(t, settings: settings, hostIsFrontmost: false) == .init(mood: .error, notify: false, sound: true))
        let off = AlertPolicy.Settings(notifications: false, sounds: false, doneThreshold: 20, quiet: false)
        #expect(AlertPolicy.decide(t, settings: off, hostIsFrontmost: false) == nil)
    }

    @Test func endedSessionsDoNotAlert() {
        let t = transition([(.promptSubmitted, 0), (.sessionEnded, 1)])
        #expect(AlertPolicy.decide(t, settings: loud, hostIsFrontmost: false) == nil)
    }
}

@Suite struct IslandPolicyTests {
    private func session(_ activity: Activity, id: String = "s", ack: Bool = false) -> Session {
        var s = Session(agent: .claude, sessionId: id, at: t0)
        s.activity = activity
        s.acknowledged = ack
        return s
    }

    @Test func primaryIsTheMostUrgentNonIdleSession() {
        let sessions = [session(.waiting(reason: "permission", message: nil), id: "a"), session(.thinking, id: "b")]
        #expect(IslandPolicy.primary(sessions)?.sessionId == "a")
        #expect(IslandPolicy.primary([session(.idle), session(.done(summary: nil), ack: true)]) == nil)
    }

    @Test func workingIsShownOnlyWhenWanted() {
        let working = [session(.thinking)]
        #expect(IslandPolicy.isVisible(working, showWhileWorking: true))
        #expect(!IslandPolicy.isVisible(working, showWhileWorking: false))
        #expect(IslandPolicy.isVisible([session(.done(summary: nil))], showWhileWorking: false))
        #expect(!IslandPolicy.isVisible([], showWhileWorking: true))
    }

    @Test func bloomsOnAttentionTransitions() {
        let waiting = transition([(.promptSubmitted, 0), (.needsInput(reason: "permission", message: nil), 1)])
        #expect(IslandPolicy.bloomDuration(for: waiting, quiet: false) == 8)
        let done = transition([(.promptSubmitted, 0), (.turnCompleted(summary: nil), 1)])
        #expect(IslandPolicy.bloomDuration(for: done, quiet: false) == 5)
        let working = transition([(.promptSubmitted, 0)])
        #expect(IslandPolicy.bloomDuration(for: working, quiet: false) == nil)
        #expect(IslandPolicy.bloomDuration(for: done, quiet: true) == nil)
    }
}

@Suite struct GlowStyleTests {
    @Test func stylesPerMood() {
        #expect(GlowStyle.for(mood: .idle, agent: .claude) == nil)
        #expect(GlowStyle.for(mood: .working, agent: .claude)?.color == Palette.claude)
        #expect(GlowStyle.for(mood: .working, agent: .codex)?.color == Palette.codex)
        #expect(GlowStyle.for(mood: .waiting, agent: .gemini)?.color == Palette.waiting)
        #expect(GlowStyle.for(mood: .done, agent: .claude)?.period == nil)
        let waiting = GlowStyle.for(mood: .waiting, agent: .claude)!
        let working = GlowStyle.for(mood: .working, agent: .claude)!
        #expect(waiting.period! < working.period!)
    }

    @Test func hexColorsParse() {
        #expect(RGB(hex: "#D97757") == RGB(r: 0xD9 / 255.0, g: 0x77 / 255.0, b: 0x57 / 255.0))
    }
}
