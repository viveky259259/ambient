@testable import AmbientApp
@testable import AmbientCore
import AVFoundation
import Foundation
import Testing

private struct Boom: Error, Equatable {}

@Suite struct ResumeOnceTests {
    @Test func resumesWithAValueSetLater() async throws {
        let once = ResumeOnce<Int>()
        let value = try await withCheckedThrowingContinuation { c in
            once.set(c)
            DispatchQueue.global().async { once.resume(returning: 7) }
        }
        #expect(value == 7)
    }

    @Test func aResultThatArrivesBeforeTheContinuationIsKept() async throws {
        let once = ResumeOnce<String>()
        once.resume(returning: "early")
        let value = try await withCheckedThrowingContinuation { once.set($0) }
        #expect(value == "early")
    }

    @Test func onlyTheFirstOutcomeCounts() async throws {
        let once = ResumeOnce<Int>()
        let value = try await withCheckedThrowingContinuation { c in
            once.set(c)
            once.resume(returning: 1)
            once.resume(returning: 2)
            once.resume(throwing: Boom())
        }
        #expect(value == 1)
    }

    @Test func anEarlyErrorIsThrown() async {
        let once = ResumeOnce<Int>()
        once.resume(throwing: Boom())
        once.resume(returning: 3)
        await #expect(throws: Boom.self) { try await withCheckedThrowingContinuation { once.set($0) } }
    }

    @Test func racingResumesNeverDoubleResume() async throws {
        for _ in 0..<50 {
            let once = ResumeOnce<Int>()
            let value = try await withCheckedThrowingContinuation { c in
                DispatchQueue.concurrentPerform(iterations: 8) { i in
                    if i == 4 { once.set(c) } else { once.resume(returning: i) }
                }
            }
            #expect((0..<8).contains(value))
        }
    }
}

@Suite struct PCMTests {
    @Test func monoBufferHoldsTheSamples() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1]
        let pcm = try PCM.mono(samples, sampleRate: 24_000)
        #expect(pcm.buffer.format.channelCount == 1)
        #expect(pcm.buffer.format.sampleRate == 24_000)
        #expect(pcm.buffer.frameLength == 4)
        let channel = try #require(pcm.buffer.floatChannelData?[0])
        #expect((0..<4).map { channel[$0] } == samples)
    }

    @Test func emptyAudioIsAnEmptyBuffer() throws {
        let pcm = try PCM.mono([], sampleRate: 22_050)
        #expect(pcm.buffer.frameLength == 0)
        #expect(pcm.buffer.frameCapacity >= 1)
    }

    @Test func failuresReadAsTheirMessage() {
        let f = SpeechFailure(message: "No voice.", offerMacVoice: true)
        #expect(f.localizedDescription == "No voice.")
        #expect(f.offerMacVoice)
        #expect(!SpeechFailure(message: "x").offerMacVoice)
    }
}

@MainActor @Suite struct EngineReadinessTests {
    @Test func macVoiceIsAlwaysReady() throws {
        let box = try AppSandbox()
        let pack = VoicePackInstaller(paths: box.paths)
        #expect(EngineSection.ready(.mac, prefs: box.preferences(), voicePack: pack, apiKey: ""))
    }

    @Test func offlineVoiceNeedsItsPackInstalled() throws {
        let box = try AppSandbox()
        let pack = VoicePackInstaller(paths: box.paths)
        #expect(pack.status != .installed)
        #expect(!EngineSection.ready(.kokoro, prefs: box.preferences(), voicePack: pack, apiKey: ""))
    }

    @Test func onlineVoiceNeedsAKeyWhenTheProviderDoes() throws {
        let box = try AppSandbox()
        let prefs = box.preferences()
        let pack = VoicePackInstaller(paths: box.paths)
        prefs.onlineProvider = OnlineProvider.openAI.rawValue
        #expect(!EngineSection.ready(.online, prefs: prefs, voicePack: pack, apiKey: ""))
        #expect(EngineSection.ready(.online, prefs: prefs, voicePack: pack, apiKey: "sk-test"))
        prefs.onlineProvider = OnlineProvider.custom.rawValue
        #expect(EngineSection.ready(.online, prefs: prefs, voicePack: pack, apiKey: "") == !OnlineProvider.custom.needsKey)
    }

    @Test func voicePackLivesUnderTheAmbientHome() throws {
        let box = try AppSandbox()
        let pack = VoicePackInstaller(paths: box.paths)
        #expect(pack.folder.path.hasPrefix(box.paths.voice.path))
        #expect(pack.helper.path.hasPrefix(pack.folder.path))
        #expect(pack.downloadSize.hasPrefix("≈") && pack.downloadSize.hasSuffix(" MB"))
        switch pack.status {
        case .notInstalled, .unavailable, .unsupported: break
        default: Issue.record("unexpected status \(pack.status) for an empty home")
        }
    }
}

@Suite struct SpeechStateTests {
    @Test func statesCompareByTheirContent() {
        #expect(SpeechState.failed("x", offerMacVoice: true) == .failed("x", offerMacVoice: true))
        #expect(SpeechState.failed("x", offerMacVoice: true) != .failed("x", offerMacVoice: false))
        #expect(SpeechState.hint("a") != .hint("b"))
        #expect(SpeechState.idle != .paused)
    }
}
