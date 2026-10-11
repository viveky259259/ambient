import AVFoundation

/// Audio for one chunk. AVAudioPCMBuffer isn't Sendable; a buffer is handed from engine to player once and never
/// shared.
struct PCM: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    static func mono(_ samples: [Float], sampleRate: Int) throws -> PCM {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = buffer.floatChannelData?[0] else {
            throw SpeechFailure(message: "Couldn't prepare the audio.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        return PCM(buffer: buffer)
    }
}

/// A failure the user should read. `offerMacVoice` adds a "Use Mac voice" button.
struct SpeechFailure: LocalizedError {
    let message: String
    var offerMacVoice = false
    var errorDescription: String? { message }
}

/// Turns one chunk of text into audio. Calls for one engine never overlap: the pipeline asks for the next chunk only
/// after the previous one is ready.
protocol SpeechEngine: AnyObject {
    func audio(for text: String) async throws -> PCM
}
