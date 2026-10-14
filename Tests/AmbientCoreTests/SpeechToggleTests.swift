import Testing
@testable import AmbientCore

@Suite struct SpeechToggleTests {
    @Test func pressingAgainOnTheSameTextStops() {
        #expect(SpeechToggle.decide(active: true, spoken: "Hello.", last: "Hello.", hasEngine: true) == .stop)
    }

    @Test func pressingWithNothingSelectedWhileSpeakingStops() {
        #expect(SpeechToggle.decide(active: true, spoken: "", last: "Hello.", hasEngine: true) == .stop)
    }

    @Test func newTextWhileSpeakingRestarts() {
        #expect(SpeechToggle.decide(active: true, spoken: "Other.", last: "Hello.", hasEngine: true) == .speak)
    }

    @Test func nothingSelectedWhileIdle() {
        #expect(SpeechToggle.decide(active: false, spoken: "", last: nil, hasEngine: true) == .nothingSelected)
        #expect(SpeechToggle.decide(active: false, spoken: "", last: nil, hasEngine: false) == .nothingSelected)
    }

    @Test func firstUseAsksForAVoice() {
        #expect(SpeechToggle.decide(active: false, spoken: "Hello.", last: nil, hasEngine: false) == .choose)
    }

    @Test func sameTextAfterItFinishedSpeaksAgain() {
        #expect(SpeechToggle.decide(active: false, spoken: "Hello.", last: "Hello.", hasEngine: true) == .speak)
    }
}
