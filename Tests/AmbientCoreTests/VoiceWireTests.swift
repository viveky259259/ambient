import Foundation
import Testing
@testable import AmbientCore

@Suite struct VoiceWireTests {
    private func response(_ id: String, _ frames: [[Float]]) -> Data {
        var d = VoiceWire.line(VoiceWire.Header(id: id, sampleRate: 24_000))
        for f in frames { d.append(VoiceWire.frame(f)) }
        d.append(VoiceWire.end)
        return d
    }

    @Test func requestRoundTrip() throws {
        let r = VoiceWire.Request(id: "1", text: "Hello\nthere", voice: "af_heart", speed: 1.1)
        let line = VoiceWire.line(r)
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(VoiceWire.request(from: line.dropLast()) == r)
        #expect(VoiceWire.request(from: Data("nonsense".utf8)) == nil)
    }

    @Test func readsAWholeResponse() throws {
        var reader = VoiceWire.Reader()
        let events = try reader.feed(response("1", [[0.5, -0.25], [1]]))
        #expect(events == [.header(.init(id: "1", sampleRate: 24_000)), .samples([0.5, -0.25]), .samples([1]), .end])
    }

    @Test func readsByteByByte() throws {
        var reader = VoiceWire.Reader()
        var events: [VoiceWire.Event] = []
        for byte in response("7", [[0.1, 0.2, 0.3]]) { events += try reader.feed(Data([byte])) }
        #expect(events == [.header(.init(id: "7", sampleRate: 24_000)), .samples([0.1, 0.2, 0.3]), .end])
    }

    @Test func readsBackToBackResponses() throws {
        var reader = VoiceWire.Reader()
        let events = try reader.feed(response("1", [[1]]) + response("2", [[2]]))
        #expect(events.count == 6)
        #expect(events[3] == .header(.init(id: "2", sampleRate: 24_000)))
    }

    @Test func errorHeaderEndsTheResponse() throws {
        var reader = VoiceWire.Reader()
        let failed = VoiceWire.line(VoiceWire.Header(id: "1", error: "tooManyTokens"))
        let events = try reader.feed(failed + response("2", [[1]]))
        #expect(events.first == .header(.init(id: "1", error: "tooManyTokens")))
        #expect(events[1] == .header(.init(id: "2", sampleRate: 24_000)))
    }

    @Test func truncatedFrameWaits() throws {
        var reader = VoiceWire.Reader()
        let whole = response("1", [[1, 2, 3, 4]])
        let events = try reader.feed(whole.prefix(whole.count - 9))
        #expect(events == [.header(.init(id: "1", sampleRate: 24_000))])
    }

    @Test func oversizedFrameThrows() {
        var reader = VoiceWire.Reader()
        var data = VoiceWire.line(VoiceWire.Header(id: "1", sampleRate: 24_000))
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: VoiceWire.WireError.badFrame(0x7FFF_FFFF)) { try reader.feed(data) }
    }

    @Test func malformedHeaderThrows() {
        var reader = VoiceWire.Reader()
        #expect(throws: VoiceWire.WireError.malformedHeader) { try reader.feed(Data("dyld: Library not loaded\n".utf8)) }
    }
}
