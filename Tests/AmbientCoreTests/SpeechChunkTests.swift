import Foundation
import Testing
@testable import AmbientCore

@Suite struct SpeechChunkTests {
    @Test func sentencesPackUpToTheLimit() {
        #expect(SpeechText.chunks("First one. Second one! Third?", max: 20) == ["First one.", "Second one! Third?"])
        #expect(SpeechText.chunks("First one. Second one! Third?") == ["First one. Second one! Third?"])
    }

    @Test func decimalsDontEndSentences() {
        #expect(SpeechText.chunks("Version 1.5 is out. Next.", max: 20) == ["Version 1.5 is out.", "Next."])
    }

    @Test func newlinesSeparateSentences() {
        #expect(SpeechText.chunks("Summary.\nFixed it") == ["Summary. Fixed it"])
    }

    @Test func longSentencesSplitAtClauses() {
        let s = "alpha beta gamma delta, epsilon zeta eta theta, iota kappa"
        #expect(SpeechText.chunks(s, max: 30) == ["alpha beta gamma delta,", "epsilon zeta eta theta,", "iota kappa"])
    }

    @Test func longClausesSplitAtWords() {
        let s = Array(repeating: "word", count: 30).joined(separator: " ")
        let chunks = SpeechText.chunks(s, max: 50)
        #expect(chunks.allSatisfy { $0.count <= 50 && !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        #expect(chunks.joined(separator: " ") == s)
    }

    @Test func emptyTextHasNoChunks() {
        #expect(SpeechText.chunks("") == [])
        #expect(SpeechText.chunks("  \n ") == [])
    }

    @Test func cjkWithoutPunctuation() {
        let s = String(repeating: "漢字", count: 500)
        let chunks = SpeechText.chunks(s)
        #expect(chunks.map(\.count) == [300, 300, 300, 100])
        #expect(chunks.joined() == s)
    }

    @Test func emojiAreNeverSplit() {
        let s = String(repeating: "👩‍💻", count: 400)
        let chunks = SpeechText.chunks(s)
        #expect(chunks.allSatisfy { $0.count <= 300 && $0.allSatisfy { $0 == "👩‍💻" } })
        #expect(chunks.joined() == s)
    }

    @Test func hugeSelectionIsFast() {
        let s = String(repeating: "word ", count: 40_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = SpeechText.chunks(s) }
        #expect(elapsed < .seconds(2))
    }
}
