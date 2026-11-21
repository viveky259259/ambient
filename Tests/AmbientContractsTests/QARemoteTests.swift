import Foundation
import Testing
@testable import AmbientContracts

@Suite("QA RemoteEvent")
struct QARemoteEventTests {
    static let id = String(repeating: "a1", count: 16)

    static func event(_ kind: RemoteEvent.Kind, tool: String? = nil, reason: String? = nil, message: String? = nil,
                      title: String? = nil, project: String? = nil) -> RemoteEvent {
        RemoteEvent(seq: 1, id: id, ts: QA.t0, agent: .codex, session: "s", kind: kind, project: project, tool: tool,
                    title: title, reason: reason, message: message)
    }

    @Test func versions() {
        #expect(RemoteEvent.currentVersion == 1)
        #expect(RemoteEvent.supportedVersions == 1...1)
        #expect(!RemoteEvent.supportedVersions.contains(0))
        #expect(!RemoteEvent.supportedVersions.contains(2))
        #expect(RemoteEvent.supportedVersions.lowerBound >= 1, "never accepts version 0")
    }

    @Test func initDefaultsAndStoresFields() {
        let e = RemoteEvent(seq: -3, id: "", ts: QA.t0, agent: .custom, session: "", kind: .notice)
        #expect(e.v == RemoteEvent.currentVersion)
        #expect(e.seq == -3 && e.id == "" && e.session == "" && e.agent == .custom)
        #expect(e.project == nil && e.tool == nil && e.title == nil && e.reason == nil && e.message == nil)
        let full = Self.event(.toolStarted, tool: "t", reason: "r", message: "m", title: "T", project: "p")
        #expect(full.tool == "t" && full.reason == "r" && full.message == "m" && full.title == "T" && full.project == "p")
    }

    @Test func kindRawValuesAreTheWireNames() {
        #expect(RemoteEvent.Kind.allCases.map(\.rawValue) == [
            "sessionStarted", "promptSubmitted", "toolStarted", "toolFinished", "toolFailed", "needsInput",
            "compactStarted", "compactFinished", "subagentStarted", "subagentFinished", "turnCompleted", "turnFailed",
            "sessionEnded", "notice", "titleChanged", "agentExited",
        ])
        #expect(RemoteEvent.Kind(rawValue: "answered") == nil, "remote machines never send answered")
        #expect(RemoteEvent.Kind(rawValue: "SessionStarted") == nil)
    }

    static let mapping: [(RemoteEvent.Kind, String?, String?, EventKind?)] = [
        (.sessionStarted, nil, "m", .sessionStarted),
        (.promptSubmitted, nil, "m", .promptSubmitted),
        (.toolStarted, "Bash", "m", .toolStarted(name: "Bash", detail: nil)),
        (.toolStarted, nil, nil, .toolStarted(name: "tool", detail: nil)),
        (.toolFinished, "Edit", nil, .toolFinished(name: "Edit", failed: false)),
        (.toolFinished, nil, nil, .toolFinished(name: "tool", failed: false)),
        (.toolFailed, "Edit", nil, .toolFinished(name: "Edit", failed: true)),
        (.toolFailed, nil, nil, .toolFinished(name: "tool", failed: true)),
        (.compactStarted, nil, nil, .compactStarted),
        (.compactFinished, nil, nil, .compactFinished),
        (.subagentStarted, nil, nil, .subagentStarted),
        (.subagentFinished, nil, nil, .subagentFinished),
        (.turnCompleted, nil, "Shipped", .turnCompleted(summary: "Shipped")),
        (.turnCompleted, nil, nil, .turnCompleted(summary: nil)),
        (.turnFailed, nil, "Boom", .turnFailed(message: "Boom")),
        (.turnFailed, nil, nil, .turnFailed(message: nil)),
        (.sessionEnded, nil, nil, .sessionEnded),
        (.agentExited, nil, "x", .sessionEnded),
        (.notice, nil, "Logged in", .notice(message: "Logged in")),
        (.notice, nil, nil, nil),
        (.titleChanged, nil, "New title", nil),
    ]

    @Test(arguments: mapping)
    func eventKindMapping(kind: RemoteEvent.Kind, tool: String?, message: String?, expected: EventKind?) {
        #expect(Self.event(kind, tool: tool, message: message).eventKind == expected)
    }

    @Test(arguments: RemoteEvent.Kind.allCases)
    func everyKindMapsWithoutTrapping(kind: RemoteEvent.Kind) {
        _ = Self.event(kind).eventKind
        _ = Self.event(kind, tool: "", reason: "", message: "").eventKind
    }

    static let prompts: [(String?, String?, String?, EventKind)] = [
        // reason, tool, message → event
        (nil, nil, nil, .needsInput(reason: "question", message: nil)),
        (nil, "Bash", "What now?", .needsInput(reason: "question", message: "What now?")),
        ("question", nil, "Which file?", .needsInput(reason: "question", message: "Which file?")),
        // A finer reason from a future shim passes through; Need(reason:) reads it later.
        ("command", "Bash", "make", .needsInput(reason: "command", message: "make")),
        ("bogus", nil, nil, .needsInput(reason: "bogus", message: nil)),
        // Permission prompts: the tool decides the need.
        ("permission", "Bash", "Bash", .needsInput(reason: "command", message: nil)),
        ("permission", "Bash", "rm -rf build", .needsInput(reason: "command", message: "rm -rf build")),
        ("permission", "apply_patch", nil, .needsInput(reason: "edit", message: nil)),
        ("permission", "mcp__github__create_pr", nil, .needsInput(reason: "permission", message: "github · create_pr")),
        ("permission", "Read", "Read", .needsInput(reason: "permission", message: "Read")),
        ("permission", "Bash", "Claude needs your permission to use Write",
         .needsInput(reason: "command", message: nil)),
        // No tool: the message decides.
        ("permission", nil, "Claude needs your permission to use WebFetch", .needsInput(reason: "web", message: nil)),
        ("permission", nil, "ExitPlanMode", .needsInput(reason: "plan", message: nil)),
        ("permission", nil, "Allow this?", .needsInput(reason: "permission", message: "Allow this?")),
        ("permission", nil, nil, .needsInput(reason: "permission", message: nil)),
        ("permission", nil, "   ", .needsInput(reason: "permission", message: nil)),
        ("permission", nil, "AskUserQuestion", .needsInput(reason: "question", message: nil)),
    ]

    @Test(arguments: prompts)
    func needsInputWorksOutTheNeed(reason: String?, tool: String?, message: String?, expected: EventKind) {
        #expect(Self.event(.needsInput, tool: tool, reason: reason, message: message).eventKind == expected)
    }

    @Test func permissionPromptTextIsCleanedAndCut() {
        let e = Self.event(.needsInput, reason: "permission", message: "Allow\n\n   this   " + String(repeating: "x ", count: 400))
        guard case let .needsInput(reason, message)? = e.eventKind else { Issue.record("not a prompt"); return }
        #expect(reason == "permission")
        #expect(message?.hasPrefix("Allow this x") == true)
        #expect(message?.count == 160)
    }

    @Test func nonPermissionPromptTextIsPassedThroughUntouched() {
        // Only the permission path cleans text: the decoder in AmbientCore must have done the rest.
        let raw = "line1\n\u{1B}[31mred\u{0}" + String(repeating: "q", count: 5_000)
        #expect(Self.event(.needsInput, reason: "question", message: raw).eventKind
            == .needsInput(reason: "question", message: raw))
        #expect(Self.event(.turnCompleted, message: raw).eventKind == .turnCompleted(summary: raw))
    }

    @Test func equalityCoversEveryField() {
        let a = Self.event(.toolStarted, tool: "x")
        #expect(a == Self.event(.toolStarted, tool: "x"))
        #expect(a != Self.event(.toolStarted, tool: "y"))
        #expect(a != Self.event(.toolFinished, tool: "x"))
        #expect(a != RemoteEvent(seq: 2, id: Self.id, ts: QA.t0, agent: .codex, session: "s", kind: .toolStarted, tool: "x"))
        #expect(a != RemoteEvent(v: 0, seq: 1, id: Self.id, ts: QA.t0, agent: .codex, session: "s", kind: .toolStarted,
                                 tool: "x"))
    }
}

@Suite("QA RemoteDelivery and RemoteCursor")
struct QARemoteDeliveryTests {
    @Test func deliveryKeepsWhatTheHubDecided() {
        let e = QARemoteEventTests.event(.sessionStarted)
        let d = RemoteDelivery(event: e, at: QA.t0, missed: true)
        #expect(d.event == e && d.at == QA.t0 && d.missed)
        #expect(d != RemoteDelivery(event: e, at: QA.t0, missed: false))
        #expect(d != RemoteDelivery(event: e, at: QA.t0.addingTimeInterval(1), missed: true))
    }

    @Test func cursorDefaults() {
        let c = RemoteCursor()
        #expect(c.seq == 0 && c.epoch == nil)
    }

    @Test(arguments: [RemoteCursor(), RemoteCursor(seq: .max, epoch: "e"), RemoteCursor(seq: .min, epoch: ""),
                      RemoteCursor(seq: 42, epoch: "🙂\u{0}")])
    func cursorRoundTrips(cursor: RemoteCursor) throws {
        #expect(try QA.roundTrip(cursor) == cursor)
    }

    @Test func cursorShapes() throws {
        #expect(try QA.decode(RemoteCursor.self, #"{"seq":3}"#) == RemoteCursor(seq: 3))
        #expect(try QA.decode(RemoteCursor.self, #"{"seq":3,"epoch":null,"x":1}"#) == RemoteCursor(seq: 3))
        #expect(String(decoding: try QA.encode(RemoteCursor()), as: UTF8.self) == #"{"seq":0}"#)
    }

    @Test(arguments: [#"{}"#, #"{"epoch":"e"}"#, #"{"seq":"1"}"#, #"{"seq":9223372036854775808}"#, #"{"seq":1.5}"#])
    func malformedCursorsAreRejected(json: String) {
        #expect(throws: DecodingError.self) { try QA.decode(RemoteCursor.self, json) }
    }
}

@Suite("QA RemoteOrigin and MachineRef")
struct QARemoteOriginTests {
    @Test func defaults() {
        let o = RemoteOrigin(machine: QA.machine)
        #expect(o.project == nil && o.lastSeq == 0 && !o.missed && !o.unreachable)
    }

    @Test(arguments: [false, true], [false, true])
    func roundTripsEveryFlag(missed: Bool, unreachable: Bool) throws {
        let o = RemoteOrigin(machine: QA.machine, project: missed ? "p" : nil, lastSeq: 9, missed: missed,
                             unreachable: unreachable)
        #expect(try QA.roundTrip(o) == o)
    }

    @Test func alwaysWritesTheFlags() throws {
        let dict = try QA.object(RemoteOrigin(machine: QA.machine))
        #expect(dict["missed"] as? Bool == false && dict["unreachable"] as? Bool == false)
        #expect(dict["project"] == nil)
        #expect(Set(dict.keys) == ["machine", "lastSeq", "missed", "unreachable"])
    }

    @Test func olderShapeWithoutFlagsDecodes() throws {
        let o = try QA.decode(RemoteOrigin.self, #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":5}"#)
        #expect(o == RemoteOrigin(machine: QA.machine, lastSeq: 5))
    }

    @Test func nullFlagsReadAsFalse() throws {
        let o = try QA.decode(RemoteOrigin.self,
                              #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":5,"missed":null,"unreachable":null,"project":null}"#)
        #expect(!o.missed && !o.unreachable && o.project == nil)
    }

    @Test func extraKeysAreIgnored() throws {
        let o = try QA.decode(RemoteOrigin.self,
                              #"{"machine":{"id":"m1","label":"Studio","os":"mac"},"lastSeq":5,"path":"/Users/me"}"#)
        #expect(o == RemoteOrigin(machine: QA.machine, lastSeq: 5))
    }

    @Test(arguments: [
        #"{"lastSeq":5}"#,
        #"{"machine":{"id":"m1","label":"Studio"}}"#,
        #"{"machine":{"id":"m1"},"lastSeq":5}"#,
        #"{"machine":{"label":"Studio"},"lastSeq":5}"#,
        #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":"5"}"#,
        #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":5,"missed":"yes"}"#,
        #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":5,"unreachable":1}"#,
        #"{"machine":{"id":"m1","label":"Studio"},"lastSeq":5,"project":7}"#,
        #"{"machine":"m1","lastSeq":5}"#,
        #"[]"#,
    ])
    func malformedOriginsAreRejected(json: String) {
        #expect(throws: DecodingError.self) { try QA.decode(RemoteOrigin.self, json) }
    }

    @Test func lastSeqKeepsInt64Extremes() throws {
        let max = try QA.decode(RemoteOrigin.self,
                                #"{"machine":{"id":"m","label":"l"},"lastSeq":9223372036854775807}"#)
        #expect(max.lastSeq == .max)
        let negative = try QA.decode(RemoteOrigin.self, #"{"machine":{"id":"m","label":"l"},"lastSeq":-1}"#)
        #expect(negative.lastSeq == -1, "negative sequence numbers are accepted as stored")
    }

    @Test func machineRefEqualityAndHashingUseIdAndLabel() {
        let a = MachineRef(id: "m1", label: "Studio")
        var renamed = a
        renamed.label = "Studio 2"
        #expect(a != renamed)
        #expect(Set([a, a, renamed]).count == 2)
        #expect(a == MachineRef(id: "m1", label: "Studio"))
    }

    @Test func hostileMachineStringsSurviveTheRoundTrip() throws {
        let label = "Stu\u{202E}dio\u{0}\n" + String(repeating: "🙂", count: 1_000)
        let o = RemoteOrigin(machine: MachineRef(id: "../../etc", label: label), project: "a/b")
        #expect(try QA.roundTrip(o) == o, "the contract stores; checking is the decoder's job in AmbientCore")
    }
}
