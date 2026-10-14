import Foundation

/// The three ways Ambient can read aloud.
public enum SpeechEngineKind: String, CaseIterable, Sendable {
    case mac, kokoro, online

    public var displayName: String {
        switch self {
        case .mac: "Mac voice"
        case .kokoro: "Offline model"
        case .online: "Online model"
        }
    }
}

public enum OnlineProvider: String, CaseIterable, Sendable {
    case openAI, elevenLabs, custom

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        case .custom: "Your server"
        }
    }

    public var defaultVoice: String {
        switch self {
        case .openAI: "alloy"
        case .elevenLabs: "21m00Tcm4TlvDq8ikWAM"
        case .custom: "af_heart"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini-tts"
        case .elevenLabs: "eleven_flash_v2_5"
        case .custom: "kokoro"
        }
    }

    /// A local OpenAI-compatible server usually takes no key.
    public var needsKey: Bool { self != .custom }
}

/// Requests to online text-to-speech services. Every provider answers with 24 kHz 16-bit mono PCM.
public enum OnlineSpeech {
    public static let sampleRate = 24_000

    /// Nil when the settings can't make a valid request (a bad server URL or voice id).
    public static func request(provider: OnlineProvider, baseURL: String, key: String, model: String,
                               voice: String, text: String, speed: Double) -> URLRequest? {
        var request: URLRequest
        let body: [String: Any]
        switch provider {
        case .openAI, .custom:
            let base = provider == .openAI ? "https://api.openai.com/v1" : baseURL.trimmingCharacters(in: .whitespaces)
            guard !base.isEmpty,
                  let url = URL(string: base.hasSuffix("/") ? base + "audio/speech" : base + "/audio/speech"),
                  let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
            request = URLRequest(url: url)
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            body = ["model": model, "input": text, "voice": voice, "response_format": "pcm",
                    "speed": min(4, max(0.25, speed))]
        case .elevenLabs:
            guard voice.range(of: "^[A-Za-z0-9]{1,64}$", options: .regularExpression) != nil,
                  let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=pcm_24000")
            else { return nil }
            request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            body = ["text": text, "model_id": model, "voice_settings": ["speed": min(1.2, max(0.7, speed))]]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// 16-bit little-endian PCM as floats in -1...1. A trailing odd byte is ignored.
    public static func samples(pcm16 data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            (0..<raw.count / 2).map {
                Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self))) / 32_768
            }
        }
    }

    /// What to tell the user when a provider answers with an error.
    public static func failure(status: Int, body: Data, provider: OnlineProvider) -> String {
        let name = provider.displayName
        switch status {
        case 401, 403: return "\(name) didn't accept the API key."
        case 429: return "\(name) is limiting requests. Try again in a minute."
        default:
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let detail = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? ((json?["detail"] as? [String: Any])?["message"] as? String)
                ?? (json?["detail"] as? String)
            let base = "\(name) couldn't read it aloud (error \(status))."
            return detail.map { base + " " + Trim.truncate($0, max: 120) } ?? base
        }
    }
}
