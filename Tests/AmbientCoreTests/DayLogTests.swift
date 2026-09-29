import Foundation
import Testing
@testable import AmbientCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-09-29 00:00 UTC.
private let midnight = Date(timeIntervalSince1970: 1_790_640_000)

/// Runs events through a real store and folds each change into a log, like AppModel does.
private struct Harness {
    let store = SessionStore()
    var log: DayLog

    init(at start: Date) { log = DayLog(now: start, calendar: utc) }

    mutating func send(_ kind: EventKind, at seconds: TimeInterval, session: String = "s1", agent: AgentKind = .claude,
                       cwd: String = "/src/api") {
        let when = midnight.addingTimeInterval(seconds)
        guard let change = store.apply(AgentEvent(agent: agent, sessionId: session, cwd: cwd, kind: kind, timestamp: when))
        else { return }
        log.apply(change, now: when, calendar: utc)
    }
}

@Suite struct DayLogTests {
    @Test func countsWhatHappened() {
        var h = Harness(at: midnight.addingTimeInterval(3_600))
        h.send(.promptSubmitted, at: 3_600)
        h.send(.toolStarted(name: "Bash", detail: "npm test"), at: 3_610)
        h.send(.toolFinished(name: "Bash", failed: false), at: 3_620)
        h.send(.toolStarted(name: "Read", detail: "a.swift"), at: 3_630)
        h.send(.turnCompleted(summary: "Green"), at: 3_700)
        h.send(.promptSubmitted, at: 4_000, session: "s2", agent: .codex, cwd: "/src/web")
        h.send(.turnFailed(message: "Quota"), at: 4_060, session: "s2", agent: .codex, cwd: "/src/web")

        #expect(h.log.tools == 2)
        #expect(h.log.turnsDone == 1)
        #expect(h.log.turnsFailed == 1)
        #expect(h.log.projects == ["api", "web"])
        #expect(h.log.finishedSeconds == 160)
        #expect(h.log.longestRun == 100)
        #expect(h.log.marks.map(\.outcome) == [.done, .failed])
        #expect(h.log.marks.map(\.agent) == [.claude, .codex])
        #expect(h.log.moments.map(\.kind) == [.failed, .done])
        #expect(h.log.moments.first?.place == "web")
        #expect(h.log.moments.first?.at == midnight.addingTimeInterval(4_060))
    }

    @Test func aPromptCountsOnceWhileItWaits() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 10)
        h.send(.needsInput(reason: "permission", message: "Bash: rm"), at: 20)
        h.send(.needsInput(reason: "permission", message: "Bash: rm"), at: 25)
        #expect(h.log.neededYou == 1)
        h.send(.toolStarted(name: "Bash", detail: "rm"), at: 30)
        h.send(.needsInput(reason: "question", message: "Which one?"), at: 40)
        #expect(h.log.neededYou == 2)
        #expect(h.log.moments.map(\.kind) == [.neededYou, .neededYou])
    }

    @Test func midnightStartsAFreshDayAndSplitsATurnThatCrossesIt() {
        var h = Harness(at: midnight.addingTimeInterval(-600))
        h.send(.promptSubmitted, at: -600)
        h.send(.toolStarted(name: "Bash", detail: nil), at: -590)
        #expect(h.log.tools == 1)
        h.send(.turnCompleted(summary: nil), at: 300)
        #expect(h.log.day == midnight)
        #expect(h.log.tools == 0)
        #expect(h.log.turnsDone == 1)
        #expect(h.log.finishedSeconds == 300)
        #expect(h.log.longestRun == 900)
    }

    @Test func rollOverOnlyPastMidnight() {
        var log = DayLog(now: midnight.addingTimeInterval(-60), calendar: utc)
        #expect(log.rollOver(now: midnight.addingTimeInterval(-1), calendar: utc) == false)
        #expect(log.rollOver(now: midnight.addingTimeInterval(1), calendar: utc) == true)
        #expect(log.day == midnight)
    }

    @Test func demoSessionsAndSweepsDontCount() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 10, session: "demo-claude-web")
        h.send(.turnCompleted(summary: nil), at: 20, session: "demo-claude-web")
        let sweep = SessionChange(session: Session(agent: .claude, sessionId: "x", at: midnight),
                                  previous: .thinking, event: nil, removed: false)
        h.log.apply(sweep, now: midnight.addingTimeInterval(30), calendar: utc)
        #expect(h.log == DayLog(now: midnight, calendar: utc))
    }

    @Test func capsKeepTheNewestAndCountsStayExact() {
        var h = Harness(at: midnight)
        for i in 0..<50 {
            let t = TimeInterval(i * 100)
            h.send(.promptSubmitted, at: t + 1)
            h.send(.turnCompleted(summary: nil), at: t + 50)
        }
        #expect(h.log.turnsDone == 50)
        #expect(h.log.marks.count == DayLog.maxMarks)
        #expect(h.log.moments.count == DayLog.maxMoments)
        #expect(h.log.marks.last?.at == midnight.addingTimeInterval(4_950))
        #expect(h.log.moments.first?.at == midnight.addingTimeInterval(4_950))
    }

    @Test func agentTimeIncludesTurnsStillRunning() {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 0)
        h.send(.turnCompleted(summary: nil), at: 60)
        h.send(.promptSubmitted, at: 100, session: "s2")
        h.send(.toolStarted(name: "Bash", detail: nil), at: 110, session: "s2")
        #expect(h.log.agentTime(live: h.store.sessions, now: midnight.addingTimeInterval(160)) == 120)
    }

    @Test func savesWithoutFreeText() throws {
        var h = Harness(at: midnight)
        h.send(.promptSubmitted, at: 0)
        h.send(.toolStarted(name: "Bash", detail: "SECRET-HINT"), at: 1)
        h.send(.needsInput(reason: "permission", message: "SECRET-PROMPT"), at: 2)
        h.send(.turnCompleted(summary: "SECRET-SUMMARY"), at: 3)
        h.send(.turnFailed(message: "SECRET-ERROR"), at: 4, session: "s2")
        let url = try shortTempDir().appendingPathComponent("day.json")
        try DayLogFile.save(h.log, to: url)
        #expect(DayLogFile.load(from: url) == h.log)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("SECRET"))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func missingOrCorruptFilesLoadNothing() throws {
        let url = try shortTempDir().appendingPathComponent("day.json")
        #expect(DayLogFile.load(from: url) == nil)
        try Data("{nope".utf8).write(to: url)
        #expect(DayLogFile.load(from: url) == nil)
    }
}
