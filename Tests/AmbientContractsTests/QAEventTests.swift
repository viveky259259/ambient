import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA AgentKind")
struct QAAgentKindTests {
    @Test func rawValuesAreTheWireNames() {
        #expect(AgentKind.allCases.map(\.rawValue)
            == ["claude", "codex", "gemini", "antigravity", "cursor", "copilot", "opencode", "custom"])
    }

    @Test func hookedIsEveryAgentButCustomInOrder() {
        #expect(AgentKind.hooked == Array(AgentKind.allCases.dropLast()))
        #expect(!AgentKind.hooked.contains(.custom))
    }

    @Test(arguments: AgentKind.allCases)
    func displayNamesAreNonEmptyAndDistinct(agent: AgentKind) {
        #expect(!agent.displayName.isEmpty)
        #expect(AgentKind.allCases.filter { $0.displayName == agent.displayName } == [agent])
    }

    @Test(arguments: ["Claude", "CLAUDE", "", "windsurf", "remote"])
    func unknownOrMiscasedAgentsDoNotDecode(raw: String) {
        #expect(throws: DecodingError.self) { try QA.decode(AgentKind.self, "\"\(raw)\"") }
    }

    @Test func customIsNotBeta() { #expect(!AgentKind.custom.isBeta) }
}

@Suite("QA EventKind and AgentEvent")
struct QAEventKindTests {
    static let kinds: [EventKind] = [
        .sessionStarted, .promptSubmitted, .toolStarted(name: "Bash", detail: "x"), .toolStarted(name: "Bash", detail: nil),
        .toolFinished(name: "Bash", failed: false), .toolFinished(name: "Bash", failed: true),
        .needsInput(reason: "edit", message: "f.swift"), .needsInput(reason: "question", message: nil), .answered,
        .compactStarted, .compactFinished, .subagentStarted, .subagentFinished, .turnCompleted(summary: "ok"),
        .turnCompleted(summary: nil), .turnFailed(message: "x"), .turnFailed(message: nil), .sessionEnded,
        .notice(message: ""), .notice(message: "hi"),
    ]

    @Test(arguments: kinds)
    func eventKindRoundTrips(kind: EventKind) throws {
        #expect(try QA.roundTrip(kind) == kind)
    }

    @Test func wireShapes() throws {
        #expect(String(decoding: try QA.encode(EventKind.answered), as: UTF8.self) == #"{"answered":{}}"#)
        #expect(String(decoding: try QA.encode(EventKind.turnCompleted(summary: nil)), as: UTF8.self)
            == #"{"turnCompleted":{}}"#)
        let failed = try QA.object(EventKind.toolFinished(name: "x", failed: true))
        #expect((failed["toolFinished"] as? [String: Any])?["failed"] as? Bool == true)
    }

    @Test(arguments: [
        #"{"teleport":{}}"#, #"{"toolFinished":{"name":"x"}}"#, #"{"notice":{}}"#, #"{"needsInput":{"message":"m"}}"#,
        #"{"toolFinished":{"name":"x","failed":"yes"}}"#, #"[]"#, #"null"#,
    ])
    func malformedEventKindsDoNotDecode(json: String) {
        #expect(throws: DecodingError.self) { try QA.decode(EventKind.self, json) }
    }

    @Test func agentEventRoundTripsEveryField() throws {
        let e = AgentEvent(agent: .custom, sessionId: "a-1", cwd: "/w/x", kind: .answered,
                           timestamp: QA.t0.addingTimeInterval(0.25), host: HostInfo(pids: [9]), agentName: "Aider")
        #expect(try QA.roundTrip(e) == e)
    }

    @Test func agentEventMinimalShape() throws {
        let json = #"{"agent":"codex","sessionId":"s","kind":{"sessionStarted":{}},"timestamp":10}"#
        let e = try QA.decode(AgentEvent.self, json)
        #expect(e.cwd == nil && e.host == nil && e.agentName == nil)
        #expect(e.timestamp == Date(timeIntervalSinceReferenceDate: 10))
    }

    @Test(arguments: ["agent", "sessionId", "kind", "timestamp"])
    func agentEventRequiredFields(key: String) throws {
        let e = AgentEvent(agent: .claude, sessionId: "s", cwd: nil, kind: .sessionEnded, timestamp: QA.t0)
        let data = try QA.edited(e) { $0.removeValue(forKey: key) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AgentEvent.self, from: data) }
    }

    @Test func agentEventIgnoresUnknownKeys() throws {
        let e = AgentEvent(agent: .claude, sessionId: "s", cwd: nil, kind: .sessionEnded, timestamp: QA.t0)
        let data = try QA.edited(e) { $0["v"] = 2; $0["extra"] = [1, 2] }
        #expect(try JSONDecoder().decode(AgentEvent.self, from: data) == e)
    }

    @Test(arguments: [("/a/b", "b"), ("/a/b/", "b"), ("/", nil), ("", nil), ("rel", "rel")] as [(String, String?)])
    func agentEventProject(cwd: String, project: String?) {
        #expect(AgentEvent(agent: .claude, sessionId: "s", cwd: cwd, kind: .sessionStarted).project == project)
    }
}

@Suite("QA HostInfo")
struct QAHostInfoTests {
    @Test func defaultsAreEmpty() {
        let h = HostInfo()
        #expect(h.pids.isEmpty)
        #expect(h.bundleId == nil && h.termProgram == nil && h.agentPid == nil && h.appServer == nil && h.tty == nil)
        #expect(h.hostSessionId == nil && h.tmuxSocket == nil && h.tmuxPane == nil)
        #expect(h.cmuxWorkspace == nil && h.cmuxSurface == nil && h.cmuxSocket == nil)
    }

    @Test func emptyHostWritesOnlyPids() throws {
        #expect(String(decoding: try QA.encode(HostInfo()), as: UTF8.self) == #"{"pids":[]}"#)
        #expect(try QA.decode(HostInfo.self, #"{"pids":[]}"#) == HostInfo())
    }

    @Test func pidsAreRequired() {
        #expect(throws: DecodingError.self) { try QA.decode(HostInfo.self, "{}") }
    }

    @Test(arguments: [#"{"pids":[2147483648]}"#, #"{"pids":[-2147483649]}"#, #"{"pids":[1.5]}"#,
                      #"{"pids":["1"]}"#, #"{"pids":[],"agentPid":4294967296}"#])
    func pidsOutsideInt32AreRejected(json: String) {
        #expect(throws: DecodingError.self) { try QA.decode(HostInfo.self, json) }
    }

    @Test func extremesWithinInt32Decode() throws {
        let h = try QA.decode(HostInfo.self, #"{"pids":[2147483647,-2147483648,0],"agentPid":-1,"future":true}"#)
        #expect(h.pids == [.max, .min, 0] && h.agentPid == -1)
    }
}
