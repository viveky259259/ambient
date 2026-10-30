import Foundation
import Testing
@testable import AmbientCore

private let validID = "0123456789abcdef0123456789abcdef"

private func line(_ fields: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
}

private func base(_ extra: [String: Any] = [:]) -> [String: Any] {
    var f: [String: Any] = ["v": 1, "seq": 7, "id": validID, "ts": 1_761_600_000, "agent": "claude",
                            "session": "0b9e-41aa", "kind": "toolStarted"]
    for (k, v) in extra { f[k] = v }
    return f
}

private func rejection(_ data: Data) -> RemoteRejection? {
    do {
        _ = try RemoteEventDecoder.decode(data)
        return nil
    } catch {
        return error
    }
}

/// Deterministic, so a failing fuzz case can be replayed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct RemoteEventDecoderTests {
    @Test func decodesAValidLine() throws {
        let e = try RemoteEventDecoder.decode(line(base(["project": "api", "tool": "Bash", "title": "Fix the build"])))
        #expect(e.v == 1)
        #expect(e.seq == 7)
        #expect(e.id == validID)
        #expect(e.ts == Date(timeIntervalSince1970: 1_761_600_000))
        #expect(e.agent == .claude)
        #expect(e.session == "0b9e-41aa")
        #expect(e.kind == .toolStarted)
        #expect(e.eventKind == .toolStarted(name: "Bash", detail: nil))
        #expect(e.project == "api")
        #expect(e.title == "Fix the build")
    }

    @Test func everyKindMapsToAnEventOrATitle() throws {
        for kind in RemoteEvent.Kind.allCases {
            let e = try RemoteEventDecoder.decode(line(base(["kind": kind.rawValue, "message": "m"])))
            switch kind {
            case .titleChanged: #expect(e.eventKind == nil)
            case .agentExited, .sessionEnded: #expect(e.eventKind == .sessionEnded)
            default: #expect(e.eventKind != nil, "\(kind)")
            }
        }
        let needs = try RemoteEventDecoder.decode(line(base(["kind": "needsInput", "reason": "permission"])))
        #expect(needs.eventKind == .needsInput(reason: "permission", message: nil))
    }

    @Test func rejectsLinesOverSixtyFourKilobytes() {
        let padding = String(repeating: "a", count: RemoteEventDecoder.maxLineBytes)
        let data = line(base(["message": padding]))
        #expect(data.count > RemoteEventDecoder.maxLineBytes)
        #expect(rejection(data) == .tooLong(bytes: data.count))
    }

    @Test func cutsFreeTextToItsCap() throws {
        let long = String(repeating: "word ", count: 2_000)
        let e = try RemoteEventDecoder.decode(line(base(["message": long, "project": long, "tool": long, "title": long])))
        #expect(e.message!.count == RemoteEventDecoder.Caps.message)
        #expect(e.project!.count == RemoteEventDecoder.Caps.project)
        #expect(e.tool!.count == RemoteEventDecoder.Caps.tool)
        #expect(e.title!.count == RemoteEventDecoder.Caps.title)
    }

    @Test func rendersRemoteTextAsPlainText() throws {
        // Bidirectional overrides, zero-width joiners, escape sequences and line separators are stripped.
        let hostile = "ok\u{202E}gnp.exe\u{200B}\u{1B}[31mred\u{2028}next\nline\u{0}"
        let e = try RemoteEventDecoder.decode(line(base(["message": hostile])))
        #expect(e.message == "okgnp.exe[31mrednext line")
        #expect(e.message!.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control })
    }

    @Test func rejectsUnknownDuplicateAndNestedFields() {
        #expect(rejection(line(base(["host": "x"]))) == .unknownField("host"))
        #expect(rejection(line(base(["cwd": "/home/u/secret"]))) == .unknownField("cwd"))
        #expect(rejection(line(base(["pythonPath": "/tmp/x"]))) == .unknownField("pythonPath"))
        #expect(rejection(line(base(["message": ["nested": 1]]))) == .wrongType("message"))
        #expect(rejection(line(base(["project": [1, 2]]))) == .wrongType("project"))
        let dup = #"{"v":1,"seq":7,"id":"\#(validID)","ts":1,"agent":"claude","session":"s","kind":"notice","kind":"needsInput"}"#
        #expect(rejection(Data(dup.utf8)) == .duplicateField("kind"))
    }

    @Test func rejectsMissingAndInvalidRequiredFields() {
        for key in ["v", "seq", "id", "ts", "agent", "session", "kind"] {
            var f = base()
            f[key] = nil
            #expect(rejection(line(f)) == .missingField(key))
        }
        #expect(rejection(line(base(["id": "XYZ"]))) == .invalid("id"))
        #expect(rejection(line(base(["id": validID.uppercased()]))) == .invalid("id"))
        #expect(rejection(line(base(["agent": "skynet"]))) == .invalid("agent"))
        #expect(rejection(line(base(["kind": "setTaskModel"]))) == .invalid("kind"))
        #expect(rejection(line(base(["kind": "open"]))) == .invalid("kind"))
        #expect(rejection(line(base(["session": String(repeating: "s", count: 129)]))) == .invalid("session"))
        #expect(rejection(line(base(["session": "a b"]))) == .invalid("session"))
        #expect(rejection(line(base(["session": "a\nb"]))) == .invalid("session"))
        #expect(rejection(line(base(["seq": 0]))) == .invalid("seq"))
        #expect(rejection(line(base(["seq": 1.5]))) == .invalid("seq"))
        #expect(rejection(line(base(["seq": "7"]))) == .wrongType("seq"))
        #expect(rejection(line(base(["ts": -1]))) == .invalid("ts"))
        #expect(rejection(line(base(["ts": 1e12]))) == .invalid("ts"))
        #expect(rejection(line(base(["reason": "root"]))) == .invalid("reason"))
    }

    @Test func acceptsOnlyTheCurrentAndPreviousVersion() {
        #expect(RemoteEvent.supportedVersions.contains(RemoteEvent.currentVersion))
        #expect(rejection(line(base(["v": RemoteEvent.currentVersion + 1]))) == .unsupportedVersion(RemoteEvent.currentVersion + 1))
        #expect(rejection(line(base(["v": 0]))) == .unsupportedVersion(0))
        #expect(rejection(line(base(["v": "1"]))) == .wrongType("v"))
    }

    @Test func rejectsWhatIsntAnObject() {
        #expect(rejection(Data("not json".utf8)) == .notJSON)
        #expect(rejection(Data()) == .notJSON)
        #expect(rejection(Data("[1,2]".utf8)) == .notAnObject)
        #expect(rejection(Data(#""event""#.utf8)) == .notAnObject)
        // Deep nesting is refused before parsing: the shared parser would otherwise recurse hundreds of frames.
        #expect(rejection(Data(String(repeating: "[", count: 60_000).utf8)) == .tooDeep)
        #expect(rejection(Data((#"{"message":"#  + String(repeating: "{\"a\":", count: 5_000)).utf8)) == .tooDeep)
        // Brackets inside strings don't count.
        #expect(rejection(line(base(["message": String(repeating: "[{", count: 500)]))) == nil)
    }

    @Test func rejectionCodesCarryNoContent() {
        let secret = "sk-live-hunter2"
        for r: RemoteRejection in [.unknownField(secret), .duplicateField(secret), .wrongType(secret), .missingField(secret),
                                   .invalid(secret), .tooLong(bytes: 1), .notJSON, .notAnObject, .tooDeep, .unsupportedVersion(9)] {
            #expect(!r.code.contains(secret))
            #expect(r.code.range(of: #"\A[A-Za-z]+\z"#, options: .regularExpression) != nil)
        }
    }

    // MARK: - Separation from WireMessage (ER-6)

    @Test func noWireMessageDecodesAsARemoteEvent() throws {
        let task = AgentTask(id: "t1", title: "x", status: .backlog, project: nil, manual: true)
        let messages: [WireMessage] = [
            .event(AgentEvent(agent: .claude, sessionId: "s", cwd: "/x", kind: .sessionStarted,
                              host: HostInfo(bundleId: "com.apple.Terminal", agentPid: 1, tty: "/dev/ttys001"))),
            .statusRequest, .acknowledgeAll, .open(query: nil), .open(query: "api"), .listTasks, .upsertTask(task),
            .openTask("t1"), .ping, .pong(version: "1"), .opened(sessionID: "s"), .tasks([task]),
            .status(sessions: [], mood: .idle), .upsertTaskResult(task),
        ]
        for message in messages {
            var data = try Wire.encode(message)
            data.removeLast() // the newline
            #expect(rejection(data) != nil, "\(message)")
        }
    }

    @Test func aRemoteLineIsNotAWireMessage() {
        // Even if a spool line reached the socket, the app would drop it rather than act on it.
        #expect(throws: (any Error).self) { try Wire.decode(line(base())) }
        #expect(throws: (any Error).self) { try Wire.decode(line(base(["kind": "needsInput", "reason": "permission"]))) }
    }

    // MARK: - Fuzzing

    @Test func randomBytesNeverCrashAndAlmostAlwaysReject() {
        var rng = SplitMix64(state: 0xA3B1E7)
        for _ in 0..<3_000 {
            let n = Int.random(in: 0...256, using: &rng)
            let bytes = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
            #expect(rejection(Data(bytes)) != nil)
        }
    }

    @Test func mutatedValidLinesNeverCrashOrBreakTheirCaps() {
        var rng = SplitMix64(state: 0x5EED)
        let seed = Array(line(base(["project": "api", "tool": "Bash", "title": "t", "message": "m", "reason": "question"])))
        let alphabet = Array(#"{}[]",:0123456789-.eE\u"abcdefnrt "#.utf8) + [0x00, 0x0A, 0xC3, 0xA9, 0xFF, 0xE2, 0x80, 0xAE]
        for _ in 0..<5_000 {
            var bytes = seed
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                let at = Int.random(in: 0..<max(1, bytes.count), using: &rng)
                switch Int.random(in: 0..<4, using: &rng) {
                case 0 where !bytes.isEmpty: bytes[at] = alphabet.randomElement(using: &rng)!
                case 1: bytes.insert(alphabet.randomElement(using: &rng)!, at: min(at, bytes.count))
                case 2 where !bytes.isEmpty: bytes.remove(at: at)
                default: bytes = Array(bytes.prefix(at))
                }
            }
            guard let e = try? RemoteEventDecoder.decode(Data(bytes)) else { continue }
            #expect(RemoteEvent.supportedVersions.contains(e.v))
            #expect(e.seq >= 1)
            #expect(e.id.count == 32)
            #expect(e.session.count <= RemoteEventDecoder.Caps.session)
            #expect((e.message?.count ?? 0) <= RemoteEventDecoder.Caps.message)
            #expect((e.project?.count ?? 0) <= RemoteEventDecoder.Caps.project)
            #expect((e.tool?.count ?? 0) <= RemoteEventDecoder.Caps.tool)
            #expect((e.title?.count ?? 0) <= RemoteEventDecoder.Caps.title)
            for text in [e.message, e.project, e.tool, e.title].compactMap({ $0 }) {
                #expect(text.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control && $0.properties.generalCategory != .format })
            }
        }
    }
}
