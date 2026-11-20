import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA Describe")
struct QADescribeTests {
    static let activityText: [(Activity, String, String)] = [
        (.idle, "Idle", "Idle"),
        (.thinking, "Thinking", "Thinking"),
        (.compacting, "Compacting context", "Compacting"),
        (.tool(name: "Bash", detail: "swift test"), "Bash · swift test", "Bash"),
        (.tool(name: "run_shell_command", detail: nil), "Shell", "Shell"),
        (.tool(name: "mcp__github__create_pr", detail: ""), "github · create_pr", "github · create_pr"),
        (.waiting(reason: "command", message: "make"), "Approve a command · make", "Approve command"),
        (.waiting(reason: "permission", message: nil), "Approve a tool", "Approve tool"),
        (.waiting(reason: "something-new", message: "Pick one"), "Answer a question · Pick one", "Answer question"),
        (.done(summary: "Fixed it"), "Done · Fixed it", "Done"),
        (.done(summary: ""), "Done", "Done"),
        (.error(message: "Rate limited"), "Failed · Rate limited", "Failed"),
        (.error(message: nil), "Failed", "Failed"),
    ]

    @Test(arguments: activityText)
    func activityAndShortActivity(activity: Activity, long: String, short: String) {
        #expect(Describe.activity(activity) == long)
        #expect(Describe.shortActivity(activity) == short)
    }

    @Test func activityDoesNotTrimOrCutDetail() {
        let long = String(repeating: "x", count: 5_000)
        #expect(Describe.activity(.tool(name: "Bash", detail: long)) == "Bash · " + long)
        #expect(Describe.activity(.done(summary: " ")) == "Done ·  ", "whitespace-only text is still shown")
    }

    @Test func titleFallsBackToProjectThenAgent() {
        #expect(Describe.title(QA.session(cwd: "/w/api", title: "Fix login")) == "Fix login")
        #expect(Describe.title(QA.session(cwd: "/w/api")) == "api")
        #expect(Describe.title(QA.session(.codex)) == "Codex")
        var custom = QA.session(.custom)
        custom.agentName = "Aider"
        #expect(Describe.title(custom) == "Aider")
        #expect(Describe.title(QA.session(origin: QA.origin(project: "web"), cwd: "/w/api")) == "web")
        #expect(Describe.title(QA.session(cwd: "/w/api", title: "")) == "", "an empty title is still a title")
    }

    @Test func placeOnlyWhenItAddsSomething() {
        #expect(Describe.place(QA.session(cwd: "/w/api")) == nil, "no title: the project is already the title")
        #expect(Describe.place(QA.session(cwd: "/w/api", title: "api")) == nil)
        #expect(Describe.place(QA.session(cwd: "/w/api", title: "Fix")) == "api")
        #expect(Describe.place(QA.session(title: "Fix")) == nil)
        #expect(Describe.place(QA.session(origin: QA.origin(project: "web"), title: "Fix")) == "web")
    }

    @Test func machineOnlyForRemoteSessions() {
        #expect(Describe.machine(QA.session()) == nil)
        #expect(Describe.machine(QA.session(origin: QA.origin())) == "Studio")
    }

    static let statuses: [(Activity, Bool, Bool, Bool, String?, String, String)] = [
        // activity, remote, missed, unreachable, remoteState, status, shortStatus
        (.thinking, false, false, false, nil, "Thinking", "Thinking"),
        (.thinking, true, false, false, nil, "Thinking", "Thinking"),
        (.thinking, true, false, true, "Unknown", "Unknown · Thinking", "Unknown"),
        (.idle, true, true, true, "Unknown", "Unknown · Idle", "Unknown"),
        (.waiting(reason: "command", message: "make"), true, true, false, "Missed",
         "Missed · Approve a command · make", "Missed"),
        (.waiting(reason: "question", message: nil), true, false, false, nil, "Answer a question", "Answer question"),
        (.done(summary: nil), true, true, false, nil, "Done", "Done"),
        (.waiting(reason: "edit", message: nil), true, true, true, "Unknown", "Unknown · Review a change", "Unknown"),
    ]

    @Test(arguments: statuses)
    func remoteCaveatsComeFirst(activity: Activity, remote: Bool, missed: Bool, unreachable: Bool, state: String?,
                                status: String, short: String) {
        let s = QA.session(activity: activity, origin: remote ? QA.origin(missed: missed, unreachable: unreachable) : nil)
        #expect(Describe.remoteState(s) == state)
        #expect(Describe.status(s) == status)
        #expect(Describe.shortStatus(s) == short)
    }

    static let durations: [(TimeInterval, String, String)] = [
        (-5, "0s", "0s"), (0, "0s", "0s"), (0.9, "0s", "0s"), (59.99, "59s", "59s"), (60, "1m", "1m"),
        (119, "1m", "1m"), (3_599, "59m", "59m"), (3_599.9, "59m", "59m"), (3_600, "1h", "1h"),
        (3_659, "1h", "1h"), (3_660, "1h 1m", "1h"), (7_199, "1h 59m", "1h"), (7_200, "2h", "2h"),
        (86_400, "24h", "24h"), (90_061, "25h 1m", "25h"), (1e9, "277777h 46m", "277777h"),
    ]

    @Test(arguments: durations)
    func durationsAndCompactDurations(seconds: TimeInterval, full: String, compact: String) {
        #expect(Describe.duration(seconds) == full)
        #expect(Describe.compactDuration(seconds) == compact)
    }

    @Test(arguments: [(Mood.idle, "idle"), (.working, "working"), (.done, "done"), (.error, "failed"),
                      (.waiting, "needs you")])
    func moodWords(mood: Mood, word: String) {
        #expect(Describe.mood(mood) == word)
    }

    // MARK: clock

    static let now = QA.t0

    static func timed(_ activity: Activity, started: TimeInterval? = nil, ended: TimeInterval? = nil,
                      since: TimeInterval = 0) -> Session {
        var s = QA.session(activity: activity)
        s.turnStartedAt = started.map { now.addingTimeInterval(-$0) }
        s.turnEndedAt = ended.map { now.addingTimeInterval(-$0) }
        s.activitySince = now.addingTimeInterval(-since)
        return s
    }

    @Test func idleHasNoClock() {
        #expect(Describe.clock(Self.timed(.idle, started: 100, since: 100), now: Self.now) == nil)
    }

    @Test(arguments: [Activity.thinking, .tool(name: "Bash", detail: nil), .compacting])
    func workingShowsTheTurnSoFar(activity: Activity) {
        #expect(Describe.clock(Self.timed(activity, started: 3_900, since: 5), now: Self.now) == "1h 5m")
        #expect(Describe.clock(Self.timed(activity, started: 3_900, since: 5), now: Self.now, compact: true) == "1h")
        #expect(Describe.clock(Self.timed(activity, since: 5), now: Self.now) == nil, "no turn start, no clock")
        #expect(Describe.clock(Self.timed(activity, started: -30), now: Self.now) == "0s", "a start in the future")
    }

    @Test func waitingShowsHowLongItHasWaited() {
        let s = Self.timed(.waiting(reason: "edit", message: nil), started: 9_999, since: 125)
        #expect(Describe.clock(s, now: Self.now) == "2m")
        #expect(Describe.clock(Self.timed(.waiting(reason: "q", message: nil), since: 0), now: Self.now) == "0s")
    }

    @Test(arguments: [Activity.done(summary: nil), .error(message: "x")])
    func finishedShowsHowLongAgo(activity: Activity) {
        #expect(Describe.clock(Self.timed(activity, started: 99, ended: 0), now: Self.now) == "just now")
        #expect(Describe.clock(Self.timed(activity, started: 99, ended: 9.99), now: Self.now) == "just now")
        #expect(Describe.clock(Self.timed(activity, started: 99, ended: 10), now: Self.now) == "10s ago")
        #expect(Describe.clock(Self.timed(activity, started: 9_999, ended: 3_900), now: Self.now) == "1h 5m ago")
        #expect(Describe.clock(Self.timed(activity, started: 9_999, ended: 3_900), now: Self.now, compact: true)
            == "1h ago")
        #expect(Describe.clock(Self.timed(activity, since: 300), now: Self.now) == "5m ago",
                "without a turn end, the activity's start counts")
        #expect(Describe.clock(Self.timed(activity, ended: -500), now: Self.now) == "just now", "an end in the future")
    }

    @Test func tookOnlyForFinishedTurns() {
        #expect(Describe.took(Self.timed(.done(summary: nil), started: 70, ended: 5)) == "took 1m")
        #expect(Describe.took(Self.timed(.error(message: nil), started: 7, ended: 0)) == "took 7s")
        #expect(Describe.took(Self.timed(.done(summary: nil))) == nil)
        #expect(Describe.took(Self.timed(.done(summary: nil), started: 0, ended: 10)) == nil, "end before start")
        #expect(Describe.took(Self.timed(.thinking, started: 70, ended: 5)) == nil)
        #expect(Describe.took(Self.timed(.waiting(reason: "q", message: nil), started: 70, ended: 5)) == nil)
    }

    // MARK: Hostile durations

    /// `duration` converts with `Int(seconds)`, which traps for NaN, infinity and anything past `Int.max`. Session
    /// dates come from disk and the socket, so a corrupt or hostile timestamp (e.g. `turnStartedAt` of -1e300) turns
    /// `Describe.clock` into a crash of every surface that draws the session.
    @Test func infiniteDurationMustNotTrap() async {
        await withKnownIssue("BUG: Describe.duration traps on infinite seconds (Int(seconds))") {
            await #expect(processExitsWith: .success) { _ = Describe.duration(.infinity) }
        }
    }

    @Test func nanDurationMustNotTrap() async {
        await withKnownIssue("BUG: Describe.duration traps on NaN seconds (Int(seconds))") {
            await #expect(processExitsWith: .success) { _ = Describe.duration(.nan) }
        }
    }

    @Test func durationPastIntMaxMustNotTrap() async {
        await withKnownIssue("BUG: Describe.duration traps past Int.max seconds (Int(seconds))") {
            await #expect(processExitsWith: .success) { _ = Describe.duration(1e19) }
        }
    }

    @Test func compactDurationPastIntMaxMustNotTrap() async {
        await withKnownIssue("BUG: Describe.compactDuration traps past Int.max hours (Int(seconds / 3_600))") {
            await #expect(processExitsWith: .success) { _ = Describe.compactDuration(1e30) }
        }
    }

    @Test func clockWithAnAbsurdlyOldTurnStart() async {
        await withKnownIssue("BUG: Describe.clock crashes for a session whose turnStartedAt is far in the past") {
            await #expect(processExitsWith: .success) {
                var s = Session(agent: .claude, sessionId: "s", at: Date(timeIntervalSinceReferenceDate: 0))
                s.activity = .thinking
                s.turnStartedAt = Date(timeIntervalSinceReferenceDate: -1e300)
                _ = Describe.clock(s, now: Date(timeIntervalSinceReferenceDate: 0))
            }
        }
    }
}
