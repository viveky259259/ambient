import AmbientCore
import Foundation

/// OpenAI, ElevenLabs or an OpenAI-compatible server. The text of each chunk is sent to that service.
final class OnlineVoice: SpeechEngine {
    private let provider: OnlineProvider
    private let baseURL: String
    private let model: String
    private let voice: String
    private let speed: Double
    private var key: String?

    init(provider: OnlineProvider, baseURL: String, model: String, voice: String, speed: Double) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.voice = voice
        self.speed = speed
    }

    static func make(prefs: Preferences) -> OnlineVoice {
        OnlineVoice(provider: prefs.provider, baseURL: prefs.onlineBaseURL, model: prefs.onlineModel,
                    voice: prefs.onlineVoice, speed: prefs.speechRate)
    }

    func audio(for text: String) async throws -> PCM {
        // Read here, off the main thread: if the Keychain asks the user first, the island and menu bar keep working.
        let key = self.key ?? KeychainStore.key(for: provider) ?? ""
        self.key = key
        if provider.needsKey, key.isEmpty {
            throw SpeechFailure(message: "Add your \(provider.displayName) API key in Settings › Voice.", offerMacVoice: true)
        }
        guard let request = OnlineSpeech.request(provider: provider, baseURL: baseURL, key: key, model: model,
                                                 voice: voice, text: text, speed: speed) else {
            throw SpeechFailure(message: "Check the online voice's settings in Settings › Voice.", offerMacVoice: true)
        }
        let name = provider.displayName
        // "Your server" opens a sentence; mid-sentence it's "your server".
        let inSentence = provider == .custom ? "your server" : name
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                throw SpeechFailure(message: "You're offline, so \(inSentence) can't be reached.", offerMacVoice: true)
            case .timedOut:
                throw SpeechFailure(message: "\(name) took too long to answer.", offerMacVoice: true)
            default:
                throw SpeechFailure(message: "Couldn't reach \(inSentence): \(error.localizedDescription)", offerMacVoice: true)
            }
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SpeechFailure(message: OnlineSpeech.failure(status: status, body: data, provider: provider),
                                offerMacVoice: true)
        }
        return try PCM.mono(OnlineSpeech.samples(pcm16: data), sampleRate: OnlineSpeech.sampleRate)
    }
}
