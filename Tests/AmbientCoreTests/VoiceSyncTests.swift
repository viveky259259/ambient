import Foundation
import Testing
@testable import AmbientCore

private let now = Date(timeIntervalSince1970: 1_793_000_000)
private let hub = String(repeating: "ab", count: 16)
private let otherHub = String(repeating: "cd", count: 16)
private let daily = MachineRef(id: "daily", label: "Daily")

private func voiceID(_ n: Int) -> String { String(format: "%032x", n) }

/// `count` frames of a pretend AAC packet each, at `rate`.
private func audio(frames count: Int = 12, rate: Int = 24_000, size: Int = 90) -> Data {
    (0..<count).reduce(into: Data()) { data, i in data += ADTS.frame(Data(repeating: UInt8(i % 250), count: size), sampleRate: rate)! }
}

private func line(_ vseq: Int64, _ voice: Int, to: String = hub, _ part: VoiceLine.Part) -> VoiceLine {
    VoiceLine(vseq: vseq, to: to, voice: voiceID(voice), part: part)
}

private func line(_ vseq: Int64, to: String = hub, _ part: VoiceLine.Part) -> VoiceLine {
    line(vseq, 1, to: to, part)
}

private func decode(_ text: String) throws(RemoteRejection) -> VoiceLine? {
    if case let .voice(v) = try RemoteLineDecoder.decode(Data(text.utf8)) { return v }
    return nil
}

private func scratch() -> AmbientPaths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("vs-" + UUID().uuidString.prefix(8))
    return AmbientPaths(userHome: root, home: root.appendingPathComponent(".ambient"))
}

@Suite struct ADTSTests {
    @Test func framesAreCountedAndTimed() {
        let frames = ADTS.frames(in: audio(frames: 47))
        #expect(frames == ADTS.Frames(count: 47, sampleRate: 24_000))
        #expect(abs((frames?.seconds ?? 0) - 47 * 1024 / 24_000.0) < 0.0001)
    }

    @Test func anythingButWholeFramesIsRefused() {
        let good = audio(frames: 3)
        #expect(ADTS.frames(in: Data()) == nil)
        #expect(ADTS.frames(in: good.dropLast()) == nil, "a partial frame at the end")
        #expect(ADTS.frames(in: good + Data([0x00])) == nil, "trailing bytes")
        #expect(ADTS.frames(in: Data(repeating: 0xFF, count: 64)) == nil)
        var stereo = good
        stereo[3] = stereo[3] & 0x3F | 0x80 // channel configuration 2
        #expect(ADTS.frames(in: stereo) == nil)
        var crc = good
        crc[1] = 0xF0 // a CRC follows the header
        #expect(ADTS.frames(in: crc) == nil)
        var main = good
        main[2] = main[2] & 0x3F // AAC Main, not LC
        #expect(ADTS.frames(in: main) == nil)
        #expect(ADTS.frames(in: audio(frames: 1) + audio(frames: 1, rate: 16_000)) == nil, "two rates in one chunk")
        #expect(ADTS.frame(Data([1]), sampleRate: 8_000) == nil, "a rate voices don't use")
        #expect(ADTS.frame(Data(), sampleRate: 24_000) == nil)
    }
}

@Suite struct VoiceLineTests {
    @Test func everyPartGoesThroughTheDecoderUnchanged() throws {
        let parts: [VoiceLine.Part] = [.start(at: now), .audio(n: 3, data: audio()), .text("Ship the fix, then tag 0.9"),
                                       .end(text: "Ship the fix."), .end(text: nil), .cancel]
        for (i, part) in parts.enumerated() {
            let sent = line(Int64(i + 1), part)
            #expect(try decode(String(decoding: sent.encoded(), as: UTF8.self)) == sent)
        }
    }

    @Test func theLineStartsTheWayFollowMatchesIt() {
        let text = String(decoding: line(42, .cancel).encoded(), as: UTF8.self)
        #expect(text.hasPrefix(#"{"v":1,"type":"voice","vseq":42,"to":"\#(hub)","#))
    }

    @Test func aBadLineIsRejectedWhole() {
        let id = voiceID(1)
        let base = #""v":1,"type":"voice","vseq":1,"to":"\#(hub)","voice":"\#(id)""#
        let bad: [(String, RemoteRejection)] = [
            (#"{\#(base),"part":"start"}"#, .missingField("ts")),
            (#"{\#(base),"part":"start","ts":1,"data":"AAAA"}"#, .invalid("data")),
            (#"{\#(base),"part":"shout"}"#, .invalid("part")),
            (#"{\#(base),"part":"cancel","prompt":"x"}"#, .unknownField("prompt")),
            (#"{"v":1,"type":"voice","vseq":1,"to":"\#(hub)","voice":"XYZ","part":"cancel"}"#, .invalid("voice")),
            (#"{"v":1,"type":"voice","vseq":1,"to":"\#(hub.uppercased())","voice":"\#(id)","part":"cancel"}"#, .invalid("to")),
            (#"{"v":1,"type":"voice","vseq":0,"to":"\#(hub)","voice":"\#(id)","part":"cancel"}"#, .invalid("vseq")),
            (#"{"v":9,"type":"voice","vseq":1,"to":"\#(hub)","voice":"\#(id)","part":"cancel"}"#, .unsupportedVersion(9)),
            (#"{\#(base),"part":"audio","n":0,"data":"not base64!"}"#, .invalid("data")),
            (#"{\#(base),"part":"audio","n":0,"data":"\#(Data(repeating: 7, count: 300).base64EncodedString())"}"#, .invalid("data")),
            (#"{\#(base),"part":"audio","n":-1,"data":"\#(audio().base64EncodedString())"}"#, .invalid("n")),
            (#"{\#(base),"part":"audio","n":0,"data":"\#(audio(frames: 400).base64EncodedString())"}"#, .invalid("data")),
            (#"{\#(base),"part":"text","text":{"x":1}}"#, .wrongType("text")),
        ]
        for (text, rejection) in bad {
            #expect(throws: rejection, "\(text.prefix(120))") { _ = try decode(text) }
        }
    }

    @Test func aTranscriptIsPlainTextUnderItsCap() throws {
        let sneaky = "rm -rf ~\u{202E}gpj.exe\u{0007}\nnext line"
        let got = try decode(String(decoding: line(1, .text(sneaky)).encoded(), as: UTF8.self))
        #expect(got?.part == .text("rm -rf ~gpj.exe next line"))
        let long = try decode(String(decoding: line(1, .text(String(repeating: "word ", count: 4_000))).encoded(), as: UTF8.self))
        guard case let .text(text)? = long?.part else { Issue.record("no text"); return }
        #expect(text.count <= VoiceLine.maxText)
    }

    @Test func aSentTranscriptKeepsItsLineUnderTheCap() {
        let family = String(repeating: "👨‍👩‍👧‍👦 ", count: 6_000)
        let capped = VoiceLine.cap(family)
        #expect(capped.count <= VoiceLine.maxText)
        #expect(capped.utf8.count <= 40_000)
        #expect(line(1, .text(capped)).encoded().count < RemoteEventDecoder.maxLineBytes)
        #expect(VoiceLine.cap("short  and\nsweet") == "short and sweet")
    }

    @Test func helloSaysWhereTheOutboxIsOnlyWhenAsked() throws {
        let fields = #""v":1,"type":"hello","shim":"1.0.5","proto":1,"caps":"exit,title,heartbeat,voice","level":"standard","seq":0,"epoch":"0123456789abcdef","identity":"id:\#(String(repeating: "a", count: 32))","ts":1"#
        guard case let .hello(plain) = try RemoteLineDecoder.decode(Data("{\(fields)}".utf8)),
              case let .hello(asked) = try RemoteLineDecoder.decode(Data(#"{\#(fields),"voice":17}"#.utf8)) else {
            Issue.record("not a hello"); return
        }
        #expect(plain.voice == nil)
        #expect(asked.voice == 17)
        #expect(asked.caps.contains("voice"))
    }

    @Test func followIsAskedForVoicesWithArgumentsThatCantBreakItsQuoting() {
        let plain = RemoteTransport.follow(since: 5)
        #expect(plain == #"sh -c 'exec "$HOME/.ambient/bin/ambient-remote" follow --since 5'"#)
        let asked = RemoteTransport.follow(since: 5, voice: VoiceFollow(hub: VoiceHub(id: hub, label: #"Vivek's "Studio" $(rm) `x`"#), since: 9))
        #expect(asked == #"sh -c 'exec "$HOME/.ambient/bin/ambient-remote" follow --since 5 --hub \#(hub) --hub-label "Viveks Studio rm x" --voice-since 9'"#)
        #expect(RemoteTransport.follow(since: 5, voice: VoiceFollow(hub: VoiceHub(id: "nope", label: "Mac"), since: 9)) == plain)
    }
}

@Suite struct VoiceHubTests {
    @Test func aLabelKeepsOnlyWhatTheShimAccepts() {
        #expect(VoiceHub.label("Advait’s Mac Studio") == "Advaits Mac Studio")
        #expect(VoiceHub.label("  ") == "Mac")
        #expect(VoiceHub.label("José's  MacBook\tAir") == "Joss MacBookAir")
        #expect(VoiceHub.label(String(repeating: "x", count: 99)).count == 40)
    }

    @Test func theIDIsMadeOnceAndKept() {
        let paths = scratch()
        let first = VoiceHub.load(paths, name: "Studio")
        #expect(VoiceLine.isID(first.id))
        #expect(VoiceHub.load(paths, name: "Studio").id == first.id)
        #expect((try? FileManager.default.attributesOfItem(atPath: paths.voiceHubID.path))?[.posixPermissions] as? Int == 0o600)
    }

    @Test func destinationsAreTheHubsThatFollowedMostRecentFirst() throws {
        let dir = scratch().voiceHubsSeen
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "Mac Studio\n".write(to: dir.appendingPathComponent(hub), atomically: true, encoding: .utf8)
        try "Old Mini\n".write(to: dir.appendingPathComponent(otherHub), atomically: true, encoding: .utf8)
        try "junk".write(to: dir.appendingPathComponent("not-a-hub"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3_600)],
                                              ofItemAtPath: dir.appendingPathComponent(otherHub).path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)],
                                              ofItemAtPath: dir.appendingPathComponent(hub).path)
        let found = VoiceDestination.load(from: dir)
        #expect(found.map(\.label) == ["Mac Studio", "Old Mini"])
        #expect(found[0].isOnline(now: now))
        #expect(!found[1].isOnline(now: now))
    }
}

@Suite struct VoiceOutboxTests {
    @Test func linesAreNumberedAndTheSeqFileFollows() throws {
        let box = VoiceOutbox(dir: scratch().voiceOutbox)
        #expect(try box.append(to: hub, voice: voiceID(1), .start(at: now)) == 1)
        #expect(try box.append(to: hub, voice: voiceID(1), .audio(n: 0, data: audio())) == 2)
        let seq = try String(contentsOf: box.dir.appendingPathComponent("outbox.seq"), encoding: .utf8)
        #expect(seq == "2\n")
        let lines = try String(contentsOf: box.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(try FileManager.default.attributesOfItem(atPath: box.file.path)[.posixPermissions] as? Int == 0o600)
        // A new writer carries on from the same number.
        #expect(try VoiceOutbox(dir: box.dir).append(to: hub, voice: voiceID(1), .cancel) == 3)
    }

    @Test func theLiveMarkerComesAndGoes() {
        let box = VoiceOutbox(dir: scratch().voiceOutbox)
        let marker = box.dir.appendingPathComponent("outbox.live")
        box.setLive(true)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        box.setLive(false)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func tidyingEndsOpenVoicesAndDropsOldOnesWhole() throws {
        let box = VoiceOutbox(dir: scratch().voiceOutbox)
        try box.append(to: hub, voice: voiceID(1), .start(at: now.addingTimeInterval(-100_000)))
        try box.append(to: hub, voice: voiceID(1), .end(text: "old"))
        try box.append(to: hub, voice: voiceID(2), .start(at: now.addingTimeInterval(-60)))
        try box.append(to: hub, voice: voiceID(2), .audio(n: 0, data: audio()))
        try box.append(to: otherHub, voice: voiceID(3), .start(at: now))
        try box.append(to: otherHub, voice: voiceID(3), .end(text: nil))
        box.setLive(true)
        box.tidy(now: now)

        let kept = try String(contentsOf: box.file, encoding: .utf8).split(separator: "\n").compactMap { raw -> VoiceLine? in
            guard case let .voice(v) = try RemoteLineDecoder.decode(Data(raw.utf8)) else { return nil }
            return v
        }
        #expect(kept.map(\.vseq) == [3, 4, 5, 6, 7], "numbers never change, and the cancel comes last")
        #expect(kept.last == VoiceLine(vseq: 7, to: hub, voice: voiceID(2), part: .cancel))
        #expect(!FileManager.default.fileExists(atPath: box.dir.appendingPathComponent("outbox.live").path))
        #expect(try box.append(to: hub, voice: voiceID(4), .cancel) == 8)
    }

    @Test func tidyingKeepsTheNewestVoicesUnderTheSizeCap() throws {
        let box = VoiceOutbox(dir: scratch().voiceOutbox)
        for v in 1...3 {
            try box.append(to: hub, voice: voiceID(v), .start(at: now))
            try box.append(to: hub, voice: voiceID(v), .audio(n: 0, data: audio(frames: 40)))
            try box.append(to: hub, voice: voiceID(v), .end(text: nil))
        }
        let size = try Data(contentsOf: box.file).count
        box.tidy(now: now, maxBytes: size * 2 / 3 + 10)
        let voices = Set(try String(contentsOf: box.file, encoding: .utf8).split(separator: "\n").compactMap { raw -> String? in
            guard case let .voice(v) = try RemoteLineDecoder.decode(Data(raw.utf8)) else { return nil }
            return v.voice
        })
        #expect(voices == [voiceID(2), voiceID(3)])
    }
}

@Suite struct VoiceInboxTests {
    private func inbox(cursor: Int64 = 0, known: Set<String> = [], limits: VoiceInbox.Limits = .init(),
                       audit: RemoteAudit? = nil) -> VoiceInbox {
        VoiceInbox(machine: daily, hub: hub, cursor: cursor, known: known, limits: limits, audit: audit)
    }

    @Test func aWholeVoiceArrivesWithItsAudioAndLastWords() {
        let box = inbox()
        let a = audio(frames: 12), b = audio(frames: 12)
        #expect(box.receive(line(1, .start(at: now)), now: now) == [.incoming(id: voiceID(1), since: now)])
        #expect(box.cursor == 0, "never past the start of a voice still coming in")
        _ = box.receive(line(2, .audio(n: 0, data: a)), now: now)
        let progress = box.receive(line(3, .text("ship it")), now: now)
        #expect(progress == [.progress(id: voiceID(1), seconds: 12 * 1024 / 24_000.0, text: "ship it")])
        _ = box.receive(line(4, .audio(n: 1, data: b)), now: now)
        let end = box.receive(line(5, .end(text: "Ship it.")), now: now)
        let expected = VoiceArrival(id: voiceID(1), machine: daily, recordedAt: now, seconds: 24 * 1024 / 24_000.0,
                                    text: "Ship it.", audio: a + b)
        #expect(end == [.arrived(expected)])
        #expect(box.cursor == 5)
        #expect(expected.record.direction == .received)
    }

    @Test func aRepeatOrAVoiceAlreadyKeptChangesNothing() {
        let box = inbox(known: [voiceID(9)])
        _ = box.receive(line(1, .start(at: now)), now: now)
        #expect(box.receive(line(1, .start(at: now)), now: now) == [])
        #expect(box.receive(line(2, 9, .start(at: now)), now: now) == [])
        #expect(box.receive(line(3, 9, .end(text: nil)), now: now) == [])
        #expect(box.inFlight == [voiceID(1)])
    }

    @Test func linesOfAVoiceThatStartedBeforeTheCursorAreIgnored() {
        let box = inbox(cursor: 10)
        #expect(box.receive(line(11, .audio(n: 4, data: audio())), now: now) == [])
        #expect(box.receive(line(12, .end(text: "x")), now: now) == [])
        #expect(box.cursor == 12)
    }

    @Test func voicesForAnotherMacAreRefused() {
        let audit = RemoteAudit(url: scratch().home.appendingPathComponent("audit.jsonl"))
        let box = inbox(audit: audit)
        #expect(box.receive(line(1, to: otherHub, .start(at: now)), now: now) == [])
        #expect(box.inFlight.isEmpty)
        #expect(audit.records().map(\.detail) == ["voiceAddress"])
    }

    @Test func aVoiceThatBreaksTheRulesIsDroppedAndRecorded() {
        let audit = RemoteAudit(url: scratch().home.appendingPathComponent("audit.jsonl"))
        var limits = VoiceInbox.Limits()
        limits.maxSeconds = 1
        let box = inbox(limits: limits, audit: audit)
        // Out of order.
        _ = box.receive(line(1, 1, .start(at: now)), now: now)
        #expect(box.receive(line(2, 1, .audio(n: 1, data: audio())), now: now) == [.ended(id: voiceID(1))])
        #expect(box.receive(line(3, 1, .audio(n: 0, data: audio())), now: now) == [], "refused for good")
        // A rate that changes.
        _ = box.receive(line(4, 2, .start(at: now)), now: now)
        _ = box.receive(line(5, 2, .audio(n: 0, data: audio(rate: 24_000))), now: now)
        #expect(box.receive(line(6, 2, .audio(n: 1, data: audio(rate: 16_000))), now: now) == [.ended(id: voiceID(2))])
        // Too long.
        _ = box.receive(line(7, 3, .start(at: now)), now: now)
        _ = box.receive(line(8, 3, .audio(n: 0, data: audio(frames: 20))), now: now)
        #expect(box.receive(line(9, 3, .audio(n: 1, data: audio(frames: 20))), now: now) == [.ended(id: voiceID(3))])
        // Too many at once.
        _ = box.receive(line(10, 4, .start(at: now)), now: now)
        _ = box.receive(line(11, 5, .start(at: now)), now: now)
        #expect(box.receive(line(12, 6, .start(at: now)), now: now) == [.ended(id: voiceID(6))])
        #expect(Set(audit.records().compactMap(\.detail)) == ["voiceOrder", "voiceRate", "voiceLength", "voiceBusy"])
        #expect(box.cursor == 9, "still before the two voices going")
    }

    @Test func aCutOffVoiceComesBackWholeFromItsStart() {
        let box = inbox()
        _ = box.receive(line(1, 1, .start(at: now)), now: now)
        _ = box.receive(line(2, 1, .end(text: nil)), now: now)
        _ = box.receive(line(3, 2, .start(at: now)), now: now)
        _ = box.receive(line(4, 2, .audio(n: 0, data: audio())), now: now)
        #expect(box.connectionEnded(now: now) == [.ended(id: voiceID(2))])
        #expect(box.cursor == 2)
        box.beginConnection()
        // The replay, from 3.
        #expect(box.receive(line(3, 2, .start(at: now)), now: now) == [.incoming(id: voiceID(2), since: now)])
        _ = box.receive(line(4, 2, .audio(n: 0, data: audio())), now: now)
        guard case .arrived? = box.receive(line(5, 2, .end(text: nil)), now: now).first else {
            Issue.record("no arrival"); return
        }
        #expect(box.cursor == 5)
    }

    @Test func aVoiceWithNoAudioOrACancelJustEnds() {
        let box = inbox()
        _ = box.receive(line(1, 1, .start(at: now)), now: now)
        #expect(box.receive(line(2, 1, .end(text: "said nothing")), now: now) == [.ended(id: voiceID(1))])
        _ = box.receive(line(3, 2, .start(at: now)), now: now)
        #expect(box.receive(line(4, 2, .cancel), now: now) == [.ended(id: voiceID(2))])
        #expect(box.cursor == 4)
    }

    @Test func aVoiceWhoseSenderWentQuietIsDropped() {
        let box = inbox()
        _ = box.receive(line(1, .start(at: now)), now: now)
        #expect(box.sweep(now: now.addingTimeInterval(60)) == [])
        #expect(box.sweep(now: now.addingTimeInterval(121)) == [.ended(id: voiceID(1))])
        #expect(box.cursor == 1)
    }
}

@Suite struct VoiceLibraryTests {
    private func record(_ n: Int, _ direction: VoiceRecord.Direction = .received, from peer: MachineRef = daily,
                        at: Date = now) -> VoiceRecord {
        VoiceRecord(id: voiceID(n), direction: direction, peer: peer, recordedAt: at, seconds: 2, text: "voice \(n)")
    }

    @Test func voicesAndTheirCursorSurviveARestart() throws {
        let paths = scratch()
        let library = VoiceLibrary(paths: paths)
        try library.add(record(1, at: now), audio: audio(), cursor: ("daily", 7))
        try library.add(record(2, at: now.addingTimeInterval(5)), audio: audio())
        let again = VoiceLibrary(paths: paths)
        #expect(again.voices.map(\.id) == [voiceID(2), voiceID(1)], "newest first")
        #expect(again.cursors == ["daily": 7])
        #expect(again.received(from: "daily") == [voiceID(1), voiceID(2)])
        #expect(try Data(contentsOf: again.audioURL(for: record(1))) == audio())
        for path in [paths.voiceLibrary.path, again.audioURL(for: record(1)).path] {
            #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o600)
        }
    }

    @Test func aRecordingHereMovesInFromItsPart() throws {
        let library = VoiceLibrary(paths: scratch())
        let sent = record(3, .sent, from: MachineRef(id: hub, label: "Mac Studio"))
        try FileManager.default.createDirectory(at: library.audioDir, withIntermediateDirectories: true)
        try audio().write(to: library.partURL(for: sent.id))
        try library.addRecorded(sent)
        #expect(FileManager.default.fileExists(atPath: library.audioURL(for: sent).path))
        #expect(!FileManager.default.fileExists(atPath: library.partURL(for: sent.id).path))
        #expect(library.voices == [sent])
    }

    @Test func deletingForgettingAndPurging() throws {
        let paths = scratch()
        let library = VoiceLibrary(paths: paths)
        let devbox = MachineRef(id: "devbox", label: "Devbox")
        try library.add(record(1), audio: audio(), cursor: ("daily", 3))
        try library.add(record(2, from: devbox), audio: audio(), cursor: ("devbox", 9))
        try library.add(record(3, .sent, from: MachineRef(id: hub, label: "Mac Studio")), audio: audio())

        try library.forget(machine: "devbox")
        #expect(library.cursors == ["daily": 3])
        #expect(library.voices.count == 3, "unpairing keeps the voices")

        try library.purge(machine: "daily")
        #expect(library.voices.map(\.id).sorted() == [voiceID(2), voiceID(3)])
        #expect(library.cursors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.audioURL(for: record(1)).path))

        try library.delete(voiceID(2))
        #expect(library.voices.map(\.id) == [voiceID(3)])
        try library.deleteAll()
        #expect(library.voices.isEmpty)
        #expect(VoiceLibrary(paths: paths).voices.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.audioURL(for: record(3)).path))
    }
}
