import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA Activity and Mood")
struct QAActivityMoodTests {
    static let busy: [(Activity, Bool)] = [
        (.idle, false), (.thinking, true), (.tool(name: "Bash", detail: nil), true), (.compacting, true),
        (.waiting(reason: "command", message: nil), false), (.done(summary: nil), false), (.error(message: nil), false),
    ]

    @Test(arguments: busy)
    func isBusyOnlyWhileTheAgentWorks(activity: Activity, expected: Bool) {
        #expect(activity.isBusy == expected)
    }

    @Test func moodOrderIsByAttention() {
        #expect(Mood.allCases.sorted() == [.idle, .working, .done, .error, .waiting])
        #expect(Mood.allCases.max() == .waiting)
        #expect(Mood.idle < .working && .working < .done && .done < .error && .error < .waiting)
        #expect(!(Mood.waiting < .waiting))
        #expect([Mood.done, .idle, .error].max() == .error)
    }

    @Test func moodRawValuesAreTheWireFormat() throws {
        #expect(Mood.allCases.map(\.rawValue) == [0, 2, 3, 4, 5])
        #expect(try QA.decode([Mood].self, "[0,2,3,4,5]") == Mood.allCases)
        #expect(String(decoding: try QA.encode(Mood.waiting), as: UTF8.self) == "5")
    }

    @Test(arguments: [1, 6, -1, 100])
    func moodRejectsUnknownRawValues(raw: Int) {
        #expect(throws: DecodingError.self) { try QA.decode(Mood.self, "\(raw)") }
    }

    @Test func moodRejectsStrings() {
        #expect(throws: DecodingError.self) { try QA.decode(Mood.self, "\"waiting\"") }
    }

    @Test(arguments: Mood.allCases)
    func onlyWaitingDoneAndErrorWantAttention(mood: Mood) {
        #expect(mood.wantsAttention == [.waiting, .done, .error].contains(mood))
    }

    static let allActivities: [Activity] = [
        .idle, .thinking, .compacting,
        .tool(name: "Bash", detail: "make"), .tool(name: "", detail: nil), .tool(name: "Read", detail: ""),
        .waiting(reason: "permission", message: "Allow?"), .waiting(reason: "", message: nil),
        .done(summary: "ok"), .done(summary: nil), .done(summary: ""),
        .error(message: "boom"), .error(message: nil),
        .tool(name: "名前 🚀", detail: "line\nbreak\u{0}nul"),
    ]

    @Test(arguments: allActivities)
    func activityRoundTrips(activity: Activity) throws {
        #expect(try QA.roundTrip(activity) == activity)
    }

    @Test func activityOmitsNilPayloadsButAcceptsExplicitNull() throws {
        let data = try QA.encode(Activity.tool(name: "Bash", detail: nil))
        #expect(String(decoding: data, as: UTF8.self) == #"{"tool":{"name":"Bash"}}"#)
        #expect(try QA.decode(Activity.self, #"{"tool":{"name":"Bash","detail":null}}"#) == .tool(name: "Bash", detail: nil))
        #expect(try QA.decode(Activity.self, #"{"done":{}}"#) == .done(summary: nil))
        #expect(try QA.decode(Activity.self, #"{"idle":{}}"#) == .idle)
    }

    @Test func activityIgnoresExtraPayloadKeys() throws {
        #expect(try QA.decode(Activity.self, #"{"waiting":{"reason":"edit","message":"x","extra":1}}"#)
            == .waiting(reason: "edit", message: "x"))
    }

    @Test(arguments: [
        #"{"sleeping":{}}"#,           // a case from a newer version
        #"{"tool":{}}"#,               // missing required name
        #"{"tool":{"name":5}}"#,       // wrong type
        #"{"waiting":{"message":"x"}}"#, // missing reason
        #""idle""#,                    // bare string
        #"{}"#,
        #"{"idle":{},"thinking":{}}"#, // two cases at once
    ])
    func activityRejectsMalformedShapes(json: String) {
        #expect(throws: DecodingError.self) { try QA.decode(Activity.self, json) }
    }
}

@Suite("QA Session")
struct QASessionTests {
    @Test func localInitDefaults() {
        let s = Session(agent: .codex, sessionId: "abc", at: QA.t0)
        #expect(s.id == "codex:abc")
        #expect(s.agent == .codex && s.sessionId == "abc")
        #expect(s.activity == .idle && s.activitySince == QA.t0 && s.lastEventAt == QA.t0)
        #expect(s.turnStartedAt == nil && s.turnEndedAt == nil)
        #expect(s.toolCount == 0 && s.subagents == 0 && !s.acknowledged)
        #expect(s.cwd == nil && s.host == nil && s.origin == nil && s.title == nil && s.agentName == nil)
        #expect(s.beforeCompaction == nil && s.beforeWaiting == nil)
        #expect(!s.isRemote)
    }

    @Test(arguments: AgentKind.allCases)
    func remoteIdsCanNeverCollideWithLocalOnes(agent: AgentKind) {
        let remote = Session(agent: agent, sessionId: "x", at: QA.t0, origin: QA.origin())
        let local = Session(agent: agent, sessionId: "x", at: QA.t0)
        #expect(remote.id == "remote/m1/\(agent.rawValue):x")
        #expect(remote.id == Session.remoteID(machine: "m1", agent: agent, sessionId: "x"))
        #expect(local.id == "\(agent.rawValue):x")
        #expect(remote.id != local.id)
        #expect(remote.isRemote && !local.isRemote)
        #expect(!local.id.hasPrefix("remote/"))
        #expect(!AgentKind.allCases.map(\.rawValue).contains("remote"))
    }

    @Test func remoteIdKeepsSessionIdsVerbatim() {
        #expect(Session.remoteID(machine: "m", agent: .claude, sessionId: "a:b/c") == "remote/m/claude:a:b/c")
        #expect(Session.remoteID(machine: "", agent: .claude, sessionId: "") == "remote//claude:")
    }

    static let cwdProjects: [(String?, String?)] = [
        ("/Users/me/src/api", "api"), ("/Users/me/src/api/", "api"), ("/Users/me/src/api//", "api"),
        ("/", nil), ("", nil), (nil, nil), ("/tmp/with space", "with space"), ("/x/项目", "项目"),
    ]

    @Test(arguments: cwdProjects)
    func localProjectIsTheLastFolderOfCwd(cwd: String?, project: String?) {
        #expect(QA.session(cwd: cwd).project == project)
    }

    @Test func remoteProjectComesFromOriginNeverFromCwd() {
        #expect(QA.session(origin: QA.origin(project: "web"), cwd: "/Users/me/api").project == "web")
        #expect(QA.session(origin: QA.origin(project: nil), cwd: "/Users/me/api").project == nil)
    }

    @Test(arguments: AgentKind.hooked)
    func hookedAgentsKeepTheirOwnLabel(agent: AgentKind) {
        var s = QA.session(agent)
        s.agentName = "Impostor"
        #expect(s.agentLabel == agent.displayName)
    }

    @Test func customAgentsUseTheirNameElseAgent() {
        var s = QA.session(.custom)
        #expect(s.agentLabel == "Agent")
        s.agentName = "Aider"
        #expect(s.agentLabel == "Aider")
        s.agentName = ""
        #expect(s.agentLabel == "", "an empty custom name is shown as given")
    }

    struct MoodCase: Sendable, CustomTestStringConvertible {
        var activity: Activity
        var acknowledged: Bool
        var missed = false
        var unreachable = false
        var remote = false
        var mood: Mood
        var testDescription: String {
            "\(activity) ack=\(acknowledged) remote=\(remote) missed=\(missed) unreachable=\(unreachable)"
        }
    }

    static let moodCases: [MoodCase] = [
        .init(activity: .idle, acknowledged: false, mood: .idle),
        .init(activity: .idle, acknowledged: true, mood: .idle),
        .init(activity: .thinking, acknowledged: false, mood: .working),
        .init(activity: .thinking, acknowledged: true, mood: .working),
        .init(activity: .tool(name: "x", detail: nil), acknowledged: true, mood: .working),
        .init(activity: .compacting, acknowledged: false, mood: .working),
        .init(activity: .waiting(reason: "edit", message: nil), acknowledged: false, mood: .waiting),
        .init(activity: .waiting(reason: "edit", message: nil), acknowledged: true, mood: .working),
        .init(activity: .done(summary: nil), acknowledged: false, mood: .done),
        .init(activity: .done(summary: nil), acknowledged: true, mood: .idle),
        .init(activity: .error(message: nil), acknowledged: false, mood: .error),
        .init(activity: .error(message: nil), acknowledged: true, mood: .idle),
        // Remote, reachable, not missed: same as local.
        .init(activity: .waiting(reason: "q", message: nil), acknowledged: true, remote: true, mood: .working),
        .init(activity: .done(summary: nil), acknowledged: false, remote: true, mood: .done),
        // A missed prompt: seeing it ends it.
        .init(activity: .waiting(reason: "q", message: nil), acknowledged: false, missed: true, remote: true, mood: .waiting),
        .init(activity: .waiting(reason: "q", message: nil), acknowledged: true, missed: true, remote: true, mood: .idle),
        .init(activity: .done(summary: nil), acknowledged: false, missed: true, remote: true, mood: .done),
        .init(activity: .thinking, acknowledged: false, missed: true, remote: true, mood: .working),
        // Unreachable: never working, never alerting.
        .init(activity: .thinking, acknowledged: false, unreachable: true, remote: true, mood: .idle),
        .init(activity: .waiting(reason: "q", message: nil), acknowledged: false, unreachable: true, remote: true, mood: .idle),
        .init(activity: .error(message: nil), acknowledged: false, unreachable: true, remote: true, mood: .idle),
        .init(activity: .done(summary: nil), acknowledged: false, missed: true, unreachable: true, remote: true, mood: .idle),
    ]

    @Test(arguments: moodCases)
    func moodFollowsActivityAcknowledgementAndOrigin(c: MoodCase) {
        let origin = c.remote ? QA.origin(missed: c.missed, unreachable: c.unreachable) : nil
        let s = QA.session(activity: c.activity, acknowledged: c.acknowledged, origin: origin)
        #expect(s.mood == c.mood)
    }

    @Test func turnDuration() {
        var s = QA.session()
        #expect(s.turnDuration == nil)
        s.turnStartedAt = QA.t0
        #expect(s.turnDuration == nil, "a running turn has no duration")
        s.turnEndedAt = QA.t0.addingTimeInterval(65)
        #expect(s.turnDuration == 65)
        s.turnEndedAt = QA.t0
        #expect(s.turnDuration == 0)
        s.turnEndedAt = QA.t0.addingTimeInterval(-1)
        #expect(s.turnDuration == nil, "an end before the start is not a duration")
        s.turnStartedAt = nil
        #expect(s.turnDuration == nil)
    }

    // MARK: Codable

    static var richSession: Session {
        var s = QA.session(.claude, id: "s-9", activity: .tool(name: "Bash", detail: "ls"), acknowledged: true,
                           cwd: "/w/api", title: "Fix")
        s.host = HostInfo(bundleId: "b", pids: [1, 2], agentPid: 3, tty: "/dev/ttys001")
        s.turnStartedAt = QA.t0
        s.turnEndedAt = QA.t0.addingTimeInterval(5)
        s.toolCount = 3
        s.subagents = 2
        s.agentName = "x"
        s.beforeCompaction = .thinking
        s.beforeWaiting = .tool(name: "Edit", detail: nil)
        return s
    }

    @Test(arguments: QAActivityMoodTests.allActivities)
    func sessionRoundTripsWithEveryActivity(activity: Activity) throws {
        var s = Self.richSession
        s.activity = activity
        #expect(try QA.roundTrip(s) == s)
    }

    @Test func remoteSessionRoundTripsWithOrigin() throws {
        let s = QA.session(.gemini, activity: .waiting(reason: "command", message: "make"),
                           origin: QA.origin(missed: true, unreachable: true))
        let back = try QA.roundTrip(s)
        #expect(back == s)
        #expect(back.origin?.missed == true && back.origin?.unreachable == true)
        #expect(back.id == "remote/m1/gemini:s1")
    }

    @Test func sessionKeepsWhatItInterrupted() throws {
        let back = try QA.roundTrip(Self.richSession)
        #expect(back.beforeCompaction == .thinking)
        #expect(back.beforeWaiting == .tool(name: "Edit", detail: nil))
    }

    @Test func minimalSessionShapeDecodes() throws {
        let json = #"""
        {"id":"claude:a","agent":"claude","sessionId":"a","activity":{"idle":{}},"activitySince":0,
         "lastEventAt":0,"toolCount":0,"subagents":0,"acknowledged":false}
        """#
        let s = try QA.decode(Session.self, json)
        #expect(s.id == "claude:a" && s.cwd == nil && s.origin == nil && s.host == nil && s.title == nil)
        #expect(s.activitySince == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func sessionIgnoresUnknownKeysFromNewerVersions() throws {
        let data = try QA.edited(Self.richSession) { $0["futureField"] = ["a": 1]; $0["color"] = "red" }
        #expect(try JSONDecoder().decode(Session.self, from: data) == Self.richSession)
    }

    @Test(arguments: ["cwd", "host", "origin", "turnStartedAt", "turnEndedAt", "title", "agentName",
                      "beforeCompaction", "beforeWaiting"])
    func optionalSessionFieldsMayBeMissing(key: String) throws {
        let data = try QA.edited(Self.richSession) { $0.removeValue(forKey: key) }
        #expect(throws: Never.self) { try JSONDecoder().decode(Session.self, from: data) }
    }

    @Test(arguments: ["id", "agent", "sessionId", "activity", "activitySince", "lastEventAt", "toolCount",
                      "subagents", "acknowledged"])
    func requiredSessionFieldsAreRequired(key: String) throws {
        let data = try QA.edited(Self.richSession) { $0.removeValue(forKey: key) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Session.self, from: data) }
    }

    @Test func unknownAgentOrActivityFailsTheWholeSession() throws {
        let agent = try QA.edited(Self.richSession) { $0["agent"] = "windsurf" }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Session.self, from: agent) }
        let activity = try QA.edited(Self.richSession) { $0["activity"] = ["napping": [:] as [String: Any]] }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Session.self, from: activity) }
    }

    @Test func decodedIdIsTakenAsStoredNotRecomputed() throws {
        let data = try QA.edited(Self.richSession) { $0["id"] = "codex:other" }
        let s = try JSONDecoder().decode(Session.self, from: data)
        #expect(s.id == "codex:other" && s.agent == .claude)
    }

    @Test func datesAreReferenceDateSeconds() throws {
        let dict = try QA.object(Self.richSession)
        #expect(dict["activitySince"] as? Double == QA.t0.timeIntervalSinceReferenceDate)
        #expect(dict["acknowledged"] as? Bool == true)
        #expect(dict["origin"] == nil, "nil optionals are left out")
    }
}

@Suite("QA SessionChange")
struct QASessionChangeTests {
    @Test func newSessionCountsAsChanged() {
        let c = SessionChange(session: QA.session(), previous: nil, event: .sessionStarted, removed: false)
        #expect(c.changed)
        #expect(c.previousMood == nil)
    }

    @Test func sameActivityIsNotAChange() {
        let c = SessionChange(session: QA.session(activity: .thinking), previous: .thinking, event: .promptSubmitted,
                              removed: false)
        #expect(!c.changed)
        #expect(c.previousMood == .working)
    }

    @Test func removalIsAlwaysAChange() {
        let c = SessionChange(session: QA.session(activity: .thinking), previous: .thinking, event: .sessionEnded,
                              removed: true)
        #expect(c.changed)
    }

    @Test func differentPayloadIsAChange() {
        let c = SessionChange(session: QA.session(activity: .tool(name: "a", detail: "1")),
                              previous: .tool(name: "a", detail: "2"), event: nil, removed: false)
        #expect(c.changed)
        #expect(c.event == nil)
    }

    @Test func previousMoodUsesTheSessionsAcknowledgementAndOrigin() {
        let acked = SessionChange(session: QA.session(activity: .thinking, acknowledged: true),
                                  previous: .done(summary: nil), event: .promptSubmitted, removed: false)
        #expect(acked.previousMood == .idle)
        let fresh = SessionChange(session: QA.session(activity: .thinking), previous: .done(summary: nil),
                                  event: .promptSubmitted, removed: false)
        #expect(fresh.previousMood == .done)
        let gone = SessionChange(session: QA.session(activity: .thinking, origin: QA.origin(unreachable: true)),
                                 previous: .waiting(reason: "q", message: nil), event: nil, removed: false)
        #expect(gone.previousMood == .idle)
        #expect(gone.session.activity == .thinking, "previousMood must not change the session")
    }
}
