import Foundation
import Testing
@testable import AmbientCore

@Suite struct OnlineSpeechTests {
    private func body(_ r: URLRequest?) throws -> [String: Any] {
        let data = try #require(r?.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func openAIRequest() throws {
        let r = OnlineSpeech.request(provider: .openAI, baseURL: "", key: "sk-1", model: "gpt-4o-mini-tts",
                                     voice: "alloy", text: "Hi", speed: 9)
        #expect(r?.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(r?.httpMethod == "POST")
        #expect(r?.timeoutInterval == 15)
        #expect(r?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let b = try body(r)
        #expect(b["input"] as? String == "Hi")
        #expect(b["response_format"] as? String == "pcm")
        #expect(b["speed"] as? Double == 4)
    }

    @Test func customServerWithoutKey() throws {
        let r = OnlineSpeech.request(provider: .custom, baseURL: " http://localhost:8880/v1/ ", key: "", model: "kokoro",
                                     voice: "af_heart", text: "Hi", speed: 1)
        #expect(r?.url?.absoluteString == "http://localhost:8880/v1/audio/speech")
        #expect(r?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(OnlineSpeech.request(provider: .custom, baseURL: "ftp://x", key: "", model: "m", voice: "v", text: "t", speed: 1) == nil)
        #expect(OnlineSpeech.request(provider: .custom, baseURL: "", key: "", model: "m", voice: "v", text: "t", speed: 1) == nil)
    }

    @Test func elevenLabsRequest() throws {
        let r = OnlineSpeech.request(provider: .elevenLabs, baseURL: "", key: "xi", model: "eleven_flash_v2_5",
                                     voice: "21m00Tcm4TlvDq8ikWAM", text: "Hi", speed: 2)
        #expect(r?.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM?output_format=pcm_24000")
        #expect(r?.value(forHTTPHeaderField: "xi-api-key") == "xi")
        let b = try body(r)
        #expect(b["text"] as? String == "Hi")
        #expect((b["voice_settings"] as? [String: Any])?["speed"] as? Double == 1.2)
        #expect(OnlineSpeech.request(provider: .elevenLabs, baseURL: "", key: "xi", model: "m", voice: "../x", text: "t", speed: 1) == nil)
    }

    @Test func pcm16ToFloat() {
        let data = Data([0x00, 0x00, 0x00, 0x40, 0x00, 0x80])  // 0, 16384, -32768
        #expect(OnlineSpeech.samples(pcm16: data) == [0, 0.5, -1])
        #expect(OnlineSpeech.samples(pcm16: Data([0x01])) == [])
    }

    @Test func failureMessages() {
        #expect(OnlineSpeech.failure(status: 401, body: Data(), provider: .openAI) == "OpenAI didn't accept the API key.")
        #expect(OnlineSpeech.failure(status: 429, body: Data(), provider: .elevenLabs)
                == "ElevenLabs is limiting requests. Try again in a minute.")
        let body = Data(#"{"error":{"message":"Input too long"}}"#.utf8)
        #expect(OnlineSpeech.failure(status: 400, body: body, provider: .openAI)
                == "OpenAI couldn't read it aloud (error 400). Input too long")
        #expect(OnlineSpeech.failure(status: 500, body: Data("<html>".utf8), provider: .custom)
                == "Your server couldn't read it aloud (error 500).")
    }

    @Test func providerDefaults() {
        #expect(OnlineProvider.openAI.needsKey && OnlineProvider.elevenLabs.needsKey && !OnlineProvider.custom.needsKey)
        #expect(SpeechEngineKind.allCases.map(\.displayName) == ["Mac voice", "Offline model", "Online model"])
    }
}
