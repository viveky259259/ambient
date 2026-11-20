import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA DayLog")
struct QADayLogTests {
    static let cal = QA.utc
    static let morning = QA.date(2026, 11, 21, 9)

    static func finished(_ agent: AgentKind = .claude, id: String = "s1", start: Date, end: Date,
                         cwd: String? = nil, title: String? = nil, origin: RemoteOrigin? = nil) -> Session {
        var s = QA.session(agent, id: id, activity: .done(summary: nil), origin: origin, cwd: cwd, title: title)
        s.turnStartedAt = start
        s.turnEndedAt = end
        s.lastEventAt = end
        return s
    }

    static func change(_ s: Session, _ event: EventKind?, previous: Activity? = .thinking) -> SessionChange {
        SessionChange(session: s, previous: previous, event: event, removed: false)
    }

    @Test func startsAtLocalMidnight() {
        let log = DayLog(now: QA.date(2026, 11, 21, 23, 59, 59), calendar: Self.cal)
        #expect(log.day == QA.date(2026, 11, 21))
        #expect(log.finishedSeconds == 0 && log.tools == 0 && log.turnsDone == 0 && log.turnsFailed == 0)
        #expect(log.neededYou == 0 && log.projects.isEmpty && log.longestRun == 0)
        #expect(log.marks.isEmpty && log.moments.isEmpty)
        #expect(DayLog.maxMarks == 40 && DayLog.maxMoments == 20)
    }

    @Test(arguments: [
        ("UTC", QA.date(2026, 11, 20, 20, 0), QA.date(2026, 11, 20)),
        // 01:30 in Kolkata on the 21st: its day began at 18:30 UTC on the 20th.
        ("Asia/Kolkata", QA.date(2026, 11, 20, 20, 0), QA.date(2026, 11, 20, 18, 30)),
        // 09:00 in Kiritimati (UTC+14) on the 21st.
        ("Pacific/Kiritimati", QA.date(2026, 11, 20, 19, 0), QA.date(2026, 11, 20, 10, 0)),
        // 08:00 on the 20th in Honolulu (UTC-10).
        ("Pacific/Honolulu", QA.date(2026, 11, 20, 18, 0), QA.date(2026, 11, 20, 10, 0)),
    ])
    func dayDependsOnTheCalendarsZone(zone: String, now: Date, day: Date) {
        #expect(DayLog(now: now, calendar: QA.calendar(zone)).day == day)
    }

    @Test func rollOverAtMidnightExactly() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let r1 = log.rollOver(now: QA.date(2026, 11, 21, 23, 59, 59), calendar: Self.cal)
        #expect(!r1)
        let r2 = log.rollOver(now: QA.date(2026, 11, 22), calendar: Self.cal)
        #expect(r2)
        #expect(log.day == QA.date(2026, 11, 22))
        let r3 = log.rollOver(now: QA.date(2026, 11, 22, 0, 0, 1), calendar: Self.cal)
        #expect(!r3)
    }

    @Test func clockGoingBackwardsNeverRollsOver() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(QA.session(), .toolStarted(name: "x", detail: nil)), now: Self.morning, calendar: Self.cal)
        let r4 = log.rollOver(now: QA.date(2026, 11, 19), calendar: Self.cal)
        #expect(!r4)
        #expect(log.tools == 1 && log.day == QA.date(2026, 11, 21))
    }

    @Test func rollOverClearsEverything() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let s = Self.finished(start: Self.morning, end: Self.morning.addingTimeInterval(60), cwd: "/w/api")
        log.apply(Self.change(s, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        #expect(log.turnsDone == 1)
        let tomorrow = QA.date(2026, 11, 22, 1)
        log.apply(Self.change(QA.session(), nil), now: tomorrow, calendar: Self.cal)
        #expect(log == DayLog(now: tomorrow, calendar: Self.cal), "a sweep after midnight still starts the new day")
    }

    @Test func dstShortDayRollsOverOnce() {
        let ny = QA.calendar("America/New_York")
        // 2026-03-08: clocks jump from 02:00 to 03:00, so the day is 23 hours long.
        var log = DayLog(now: QA.date(2026, 3, 8, 6, in: ny), calendar: ny)
        #expect(log.day == QA.date(2026, 3, 8, 5))
        let r5 = log.rollOver(now: QA.date(2026, 3, 9, 3, 59, 59), calendar: ny)
        #expect(!r5)
        let r6 = log.rollOver(now: QA.date(2026, 3, 9, 4), calendar: ny)
        #expect(r6)
        #expect(log.day == QA.date(2026, 3, 9, 4))
    }

    @Test func eventlessAndDemoChangesDoNotCount() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let demo = Self.finished(id: "demo-1", start: Self.morning, end: Self.morning.addingTimeInterval(5), cwd: "/w/demo")
        log.apply(Self.change(demo, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(demo, .toolStarted(name: "x", detail: nil)), now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(QA.session(cwd: "/w/api"), nil), now: Self.morning, calendar: Self.cal)
        #expect(log == DayLog(now: Self.morning, calendar: Self.cal))
    }

    @Test func demoPrefixIsCaseSensitiveAndAnchored() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for id in ["Demo-1", "my-demo-1", "demo1"] {
            log.apply(Self.change(QA.session(id: id), .toolStarted(name: "x", detail: nil)), now: Self.morning,
                      calendar: Self.cal)
        }
        #expect(log.tools == 3)
    }

    @Test(arguments: [EventKind.sessionStarted, .promptSubmitted, .toolFinished(name: "x", failed: true), .answered,
                      .compactStarted, .compactFinished, .subagentStarted, .subagentFinished, .sessionEnded,
                      .notice(message: "n")])
    func otherEventsOnlyRecordTheProject(event: EventKind) {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(QA.session(cwd: "/w/api"), event), now: Self.morning, calendar: Self.cal)
        #expect(log.projects == ["api"])
        #expect(log.tools == 0 && log.turnsDone == 0 && log.turnsFailed == 0 && log.neededYou == 0)
        #expect(log.marks.isEmpty && log.moments.isEmpty)
    }

    @Test func projectsAreUniqueSortedAndLocalOnly() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for cwd in ["/w/zeta", "/w/alpha", "/x/zeta", "/w/Beta", "/"] {
            log.apply(Self.change(QA.session(cwd: cwd), .promptSubmitted), now: Self.morning, calendar: Self.cal)
        }
        log.apply(Self.change(QA.session(origin: QA.origin(project: "secret")), .promptSubmitted), now: Self.morning,
                  calendar: Self.cal)
        #expect(log.projects == ["Beta", "alpha", "zeta"], "plain String order: uppercase sorts first")
    }

    @Test func toolsCount() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for _ in 0..<3 {
            log.apply(Self.change(QA.session(), .toolStarted(name: "Bash", detail: nil)), now: Self.morning,
                      calendar: Self.cal)
        }
        #expect(log.tools == 3)
    }

    @Test func neededYouCountsOncePerWait() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        var s = QA.session(activity: .waiting(reason: "command", message: nil), title: "Deploy")
        s.lastEventAt = Self.morning
        log.apply(Self.change(s, .needsInput(reason: "command", message: nil), previous: .thinking), now: Self.morning,
                  calendar: Self.cal)
        log.apply(Self.change(s, .needsInput(reason: "edit", message: nil),
                              previous: .waiting(reason: "command", message: nil)), now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(s, .needsInput(reason: "edit", message: nil), previous: nil), now: Self.morning,
                  calendar: Self.cal)
        #expect(log.neededYou == 2)
        #expect(log.moments.map(\.kind) == [.neededYou, .neededYou])
        #expect(log.moments.first == DayMoment(kind: .neededYou, agent: .claude, place: "Deploy", at: Self.morning))
        #expect(log.marks.isEmpty)
    }

    @Test func finishedTurnsAddTimeMarksAndMoments() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let a = Self.finished(start: Self.morning, end: Self.morning.addingTimeInterval(120), cwd: "/w/api")
        let b = Self.finished(.gemini, id: "g", start: Self.morning, end: Self.morning.addingTimeInterval(30))
        log.apply(Self.change(a, .turnCompleted(summary: "ok")), now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(b, .turnFailed(message: nil)), now: Self.morning, calendar: Self.cal)
        #expect(log.turnsDone == 1 && log.turnsFailed == 1)
        #expect(log.finishedSeconds == 150 && log.longestRun == 120)
        #expect(log.marks == [DayMark(agent: .claude, outcome: .done, at: a.lastEventAt),
                              DayMark(agent: .gemini, outcome: .failed, at: b.lastEventAt)])
        #expect(log.moments.map(\.kind) == [.failed, .done], "newest first")
        #expect(log.moments.map(\.place) == ["Gemini", "api"])
    }

    @Test func turnAcrossMidnightCountsOnlyTodaysPartButLongestRunIsWhole() {
        let start = QA.date(2026, 11, 20, 23, 30), end = QA.date(2026, 11, 21, 0, 30)
        var log = DayLog(now: end, calendar: Self.cal)
        log.apply(Self.change(Self.finished(start: start, end: end), .turnCompleted(summary: nil)), now: end,
                  calendar: Self.cal)
        #expect(log.finishedSeconds == 1_800)
        #expect(log.longestRun == 3_600)
    }

    @Test func turnsWithoutTimesOrWithReversedTimesAddNoTimeButStillMark() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        var noTimes = QA.session(activity: .done(summary: nil))
        noTimes.lastEventAt = Self.morning
        log.apply(Self.change(noTimes, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        let reversed = Self.finished(start: Self.morning, end: Self.morning.addingTimeInterval(-60))
        log.apply(Self.change(reversed, .turnFailed(message: nil)), now: Self.morning, calendar: Self.cal)
        #expect(log.finishedSeconds == 0 && log.longestRun == 0)
        #expect(log.marks.count == 2 && log.turnsDone == 1 && log.turnsFailed == 1)
    }

    @Test func marksKeepTheNewestForty() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for i in 0..<45 {
            let at = Self.morning.addingTimeInterval(Double(i))
            log.apply(Self.change(Self.finished(start: at, end: at), .turnCompleted(summary: nil)), now: Self.morning,
                      calendar: Self.cal)
        }
        #expect(log.marks.count == DayLog.maxMarks)
        #expect(log.marks.first?.at == Self.morning.addingTimeInterval(5), "oldest first, the first five dropped")
        #expect(log.marks.last?.at == Self.morning.addingTimeInterval(44))
        #expect(log.turnsDone == 45)
    }

    @Test func momentsKeepTheNewestTwenty() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for i in 0..<25 {
            let at = Self.morning.addingTimeInterval(Double(i))
            log.apply(Self.change(Self.finished(start: at, end: at), .turnCompleted(summary: nil)), now: Self.morning,
                      calendar: Self.cal)
        }
        #expect(log.moments.count == DayLog.maxMoments)
        #expect(log.moments.first?.at == Self.morning.addingTimeInterval(24), "newest first")
        #expect(log.moments.last?.at == Self.morning.addingTimeInterval(5))
    }

    @Test func remoteMomentsNameOnlyTheAgentAndMachine() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let codex = Self.finished(.codex, start: Self.morning, end: Self.morning, title: "Secret title",
                                  origin: QA.origin(project: "secret"))
        var aider = Self.finished(.custom, id: "a", start: Self.morning, end: Self.morning, origin: QA.origin())
        aider.agentName = "Aider"
        log.apply(Self.change(codex, .turnCompleted(summary: "private")), now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(aider, .turnFailed(message: nil)), now: Self.morning, calendar: Self.cal)
        #expect(log.moments.map(\.place) == ["Aider on Studio", "Codex on Studio"])
        #expect(log.moments.allSatisfy { $0.machine == "m1" })
        #expect(log.projects.isEmpty)
    }

    @Test func localMomentPlaceFallsBackFromTitleToProjectToAgent() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        for s in [Self.finished(start: Self.morning, end: Self.morning, cwd: "/w/api", title: "Fix"),
                  Self.finished(start: Self.morning, end: Self.morning, cwd: "/w/api"),
                  Self.finished(.cursor, start: Self.morning, end: Self.morning)] {
            log.apply(Self.change(s, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        }
        #expect(log.moments.map(\.place) == ["Cursor", "api", "Fix"])
        #expect(log.moments.allSatisfy { $0.machine == nil })
    }

    @Test func removeMomentsForgetsOnlyThatMachineAndKeepsTotals() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let other = RemoteOrigin(machine: MachineRef(id: "m2", label: "Laptop"), lastSeq: 1)
        for s in [Self.finished(start: Self.morning, end: Self.morning, origin: QA.origin()),
                  Self.finished(id: "b", start: Self.morning, end: Self.morning, origin: other),
                  Self.finished(id: "c", start: Self.morning, end: Self.morning)] {
            log.apply(Self.change(s, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        }
        log.removeMoments(machine: "m1")
        #expect(log.moments.map(\.machine) == [nil, "m2"])
        #expect(log.turnsDone == 3 && log.marks.count == 3)
        log.removeMoments(machine: "nope")
        log.removeMoments(machine: "")
        #expect(log.moments.count == 2)
        log.removeMoments(machine: "m2")
        #expect(log.moments.map(\.machine) == [nil])
    }

    @Test func agentTimeAddsLiveBusyTurnsFromTodayOnly() {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        let done = Self.finished(start: Self.morning, end: Self.morning.addingTimeInterval(100))
        log.apply(Self.change(done, .turnCompleted(summary: nil)), now: Self.morning, calendar: Self.cal)
        let now = Self.morning.addingTimeInterval(600)

        func live(_ id: String, _ activity: Activity, start: Date?, end: Date? = nil) -> Session {
            var s = QA.session(id: id, activity: activity)
            s.turnStartedAt = start
            s.turnEndedAt = end
            return s
        }
        let sessions: [Session] = [
            live("a", .thinking, start: Self.morning),                                   // +600
            live("b", .tool(name: "x", detail: nil), start: QA.date(2026, 11, 20, 23)),   // clamped to midnight: +9h+600
            live("c", .waiting(reason: "q", message: nil), start: Self.morning),         // not busy
            live("d", .compacting, start: Self.morning, end: now),                       // turn already ended
            live("e", .thinking, start: nil),                                            // no turn
            live("demo-f", .thinking, start: Self.morning),                              // demo
            live("g", .thinking, start: now.addingTimeInterval(50)),                     // future start: 0
        ]
        let expected: TimeInterval = 100 + 600 + (9 * 3_600 + 600)
        let measured: TimeInterval = log.agentTime(live: sessions, now: now)
        #expect(measured == expected)
        #expect(log.agentTime(live: [], now: now) == 100)
    }

    @Test func roundTripsAfterAFullDay() throws {
        var log = DayLog(now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(QA.session(cwd: "/w/api"), .toolStarted(name: "x", detail: nil)), now: Self.morning,
                  calendar: Self.cal)
        log.apply(Self.change(Self.finished(start: Self.morning, end: Self.morning.addingTimeInterval(9),
                                            origin: QA.origin()), .turnCompleted(summary: nil)),
                  now: Self.morning, calendar: Self.cal)
        log.apply(Self.change(QA.session(), .needsInput(reason: "q", message: nil)), now: Self.morning, calendar: Self.cal)
        #expect(try QA.roundTrip(log) == log)
    }

    @Test(arguments: ["day", "finishedSeconds", "tools", "turnsDone", "turnsFailed", "neededYou", "projects",
                      "longestRun", "marks", "moments"])
    func everyDayLogKeyIsRequired(key: String) throws {
        let data = try QA.edited(DayLog(now: Self.morning, calendar: Self.cal)) { $0.removeValue(forKey: key) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DayLog.self, from: data) }
    }

    @Test func dayMomentMachineIsOptionalAndUnknownKindsFail() throws {
        let m = try QA.decode(DayMoment.self, #"{"kind":"done","agent":"claude","place":"p","at":0}"#)
        #expect(m.machine == nil)
        #expect(throws: DecodingError.self) {
            try QA.decode(DayMoment.self, #"{"kind":"celebrated","agent":"claude","place":"p","at":0}"#)
        }
        #expect(throws: DecodingError.self) { try QA.decode(DayMark.self, #"{"agent":"claude","outcome":"ok","at":0}"#) }
    }
}
