import AVFoundation

/// The voices that come with macOS, including downloaded Premium voices and Personal Voice. Offline.
final class MacVoice: SpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceID: String
    private let rate: Double

    init(voiceID: String, rate: Double) {
        self.voiceID = voiceID
        self.rate = rate
    }

    func audio(for text: String) async throws -> PCM {
        let utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) { utterance.voice = voice }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        let once = ResumeOnce<PCM>()
        let synthesizer = self.synthesizer
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                var parts: [AVAudioPCMBuffer] = []
                synthesizer.write(utterance) { buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength > 0, let copy = Self.join([pcm]) {
                        parts.append(copy)
                        return
                    }
                    // A zero-length buffer marks the end.
                    if let joined = Self.join(parts) {
                        once.resume(returning: PCM(buffer: joined))
                    } else {
                        once.resume(throwing: SpeechFailure(message: "The Mac voice produced no audio."))
                    }
                }
            }
        } onCancel: {
            synthesizer.stopSpeaking(at: .immediate)
            once.resume(throwing: CancellationError())
        }
    }

    /// One buffer holding all of `parts`, in the first part's format. Works for any PCM layout; also used to copy a
    /// buffer the synthesizer may reuse.
    private static func join(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let format = parts.first?.format else { return nil }
        let frames = parts.reduce(0) { $0 + $1.frameLength }
        guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let destination = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        var offset = 0
        for part in parts where part.format == format {
            let source = UnsafeMutableAudioBufferListPointer(part.mutableAudioBufferList)
            let bytes = Int(part.frameLength) * bytesPerFrame
            for (i, buffer) in source.enumerated() where i < destination.count {
                guard let from = buffer.mData, let to = destination[i].mData else { continue }
                (to + offset).copyMemory(from: from, byteCount: bytes)
            }
            offset += bytes
        }
        out.frameLength = AVAudioFrameCount(offset / bytesPerFrame)
        return out
    }
}

/// Resumes a continuation exactly once, whichever of the callback or a cancellation gets there first, and even if
/// one arrives before the continuation is set.
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var early: Result<T, Error>?
    private var done = false

    func set(_ c: CheckedContinuation<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        if let early {
            done = true
            c.resume(with: early)
        } else {
            continuation = c
        }
    }

    func resume(returning value: T) { finish(.success(value)) }
    func resume(throwing error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !done, early == nil else { return }
        if let c = continuation {
            continuation = nil
            done = true
            c.resume(with: result)
        } else {
            early = result
        }
    }
}
