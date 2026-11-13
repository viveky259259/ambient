import Testing
@testable import AmbientCore

@Suite struct TranscriptJoinerTests {
    private func joined(_ results: [(String, Bool)]) -> String {
        var joiner = TranscriptJoiner()
        for (text, ended) in results { joiner.add(text, ended: ended) }
        return joiner.text
    }

    private func joined(_ results: [String]) -> String { joined(results.map { ($0, false) }) }

    @Test func aStretchThatGrowsIsKeptOnce() {
        #expect(joined(["I", "I want", "I want to go", "I want to go home."]) == "I want to go home.")
    }

    /// What Daily's outbox showed: the transcript so far grew to 88, 122 and 185 characters and fell back each time,
    /// and the voice arrived as its last 7.
    @Test func eachPauseStartsAStretchThatIsKeptAfterTheLast() {
        let text = joined([
            "So the first thing", "So the first thing we need is a build", "So the first thing we need is a build for Daily.",
            "And", "And then we test it", "And then we test it on both Macs.",
            "Okay", "Okay ship it.",
        ])
        #expect(text == "So the first thing we need is a build for Daily. And then we test it on both Macs. Okay ship it.")
    }

    @Test func aRevisionReplacesWhatItRevises() {
        #expect(joined(["hello how are you doing", "Hello, how're you doing?"]) == "Hello, how're you doing?")
        #expect(joined(["I want to go to the sto", "I want to go to the store"]) == "I want to go to the store")
    }

    @Test func aStretchTheRecognizerEndsIsKept() {
        let text = joined([("Hello there", false), ("Hello there.", true), ("I", false), ("I think so.", false)])
        #expect(text == "Hello there. I think so.")
    }

    /// Some recognizers mark every result of a stretch as ended. The stretch is still kept once.
    @Test func endingEveryResultDoesNotRepeatTheStretch() {
        let text = joined([("I", true), ("I want", true), ("I want to go.", true), ("Then", true), ("Then home.", true)])
        #expect(text == "I want to go. Then home.")
    }

    @Test func anEndedStretchSentAgainIsNotKeptTwice() {
        #expect(joined([("All done.", true), ("All done.", true)]) == "All done.")
        #expect(joined([("All done.", true), ("All done.", false)]) == "All done.")
    }

    @Test func aStretchThatBeginsLikeTheEndedOneIsStillANewOne() {
        let text = joined([("So the build passed.", true), ("So", false), ("So now we ship.", false)])
        #expect(text == "So the build passed. So now we ship.")
    }

    @Test func aShortStretchWithAnotherFirstWordIsANewOne() {
        #expect(joined(["Yes", "No"]) == "Yes No")
    }

    @Test func blankResultsChangeNothing() {
        #expect(joined(["", "  ", "Hi there", ""]) == "Hi there")
        #expect(TranscriptJoiner().text.isEmpty)
    }

    @Test func stretchesInOtherScriptsAreKeptToo() {
        #expect(joined(["नमस्ते दोस्तों आज हम", "नमस्ते दोस्तों आज हम बिल्ड करेंगे।", "फिर", "फिर टेस्ट।"])
            == "नमस्ते दोस्तों आज हम बिल्ड करेंगे। फिर टेस्ट।")
    }
}
