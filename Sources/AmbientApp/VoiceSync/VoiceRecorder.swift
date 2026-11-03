import AmbientCore
import AVFoundation
import Speech

struct VoiceRecorderError: Error {
    let message: String
}

/// Records one voice from the microphone three ways at once: AAC in ADTS frames, cut into chunks of about half a second
/// for the outbox; the transcript, on this Mac only; and a level for the meter. Chunks come in order on the recorder's own
/// queue; text and level on the main thread.
final class VoiceRecorder: @unchecked Sendable {
    static let sampleRate = 24_000.0
    /// 12 AAC frames of 1024 samples: about half a second.
    static let framesPerChunk = 12

    var onChunk: (Int, Data) -> Void = { _, _ in }
    var onText: (String) -> Void = { _ in }
    var onLevel: (Float) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.voice-sync", qos: .userInitiated)
    private let mono: AVAudioFormat
    private let aac: AVAudioFormat

    // Only on `queue`.
    private var resampler: AVAudioConverter?
    private var encoder: AVAudioConverter?
    private var pending = Data()
    private var pendingFrames = 0
    private var chunk = 0
    private var frames = 0
    private var stopped = false

    // Only on the main thread.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript: String?
    private var transcribed: (() -> Void)?

    init() {
        mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)!
        aac = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.sampleRate,
                                       AVNumberOfChannelsKey: 1])!
    }

    /// The recognizer for the user's language, when it can run on this Mac. Never one that needs a server.
    static func recognizer() -> SFSpeechRecognizer? {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else { return nil }
        return recognizer
    }

    func start(transcribe: Bool) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceRecorderError(message: "There's no microphone to record with.")
        }
        guard let resampler = AVAudioConverter(from: format, to: mono), let encoder = AVAudioConverter(from: mono, to: aac) else {
            throw VoiceRecorderError(message: "This Mac can't record in AAC.")
        }
        resampler.downmix = true
        encoder.bitRate = 32_000
        queue.sync {
            self.resampler = resampler
            self.encoder = encoder
        }

        if transcribe, let recognizer = Self.recognizer() {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            if #available(macOS 13.0, *) { request.addsPunctuation = true }
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async { self?.recognized(result, error: error) }
            }
        }

        let request = self.request
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            request?.append(buffer)
            guard let self, let copy = Self.copy(buffer) else { return }
            let level = Self.level(buffer)
            DispatchQueue.main.async { self.onLevel(level) }
            self.queue.async { self.encode(copy) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            task?.cancel()
            throw VoiceRecorderError(message: "The microphone didn't start: \(error.localizedDescription)")
        }
    }

    /// Stops, then calls back once the last chunk is out and the transcript is final, or after two seconds of waiting for
    /// it: with the transcript, if there is one, and the length in seconds.
    func finish(_ done: @escaping (String?, Double) -> Void) {
        stopEngine()
        request?.endAudio()
        queue.async { [self] in
            compress(nil, end: true)
            let seconds = Double(frames * 1024) / Self.sampleRate
            DispatchQueue.main.async { [self] in
                var delivered = false
                let deliver = { [self] in
                    guard !delivered else { return }
                    delivered = true
                    transcribed = nil
                    done(transcript.flatMap { $0.isEmpty ? nil : $0 }, seconds)
                }
                guard task != nil else { return deliver() }
                transcribed = deliver
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                    task?.cancel()
                    task = nil
                    deliver()
                }
            }
        }
    }

    /// Stops and throws away what wasn't sent; calls back once nothing more will come.
    func cancel(_ done: @escaping () -> Void) {
        stopEngine()
        transcribed = nil
        task?.cancel()
        task = nil
        request = nil
        queue.async { [self] in
            stopped = true
            pending = Data()
            DispatchQueue.main.async(execute: done)
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func recognized(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            transcript = text
            onText(text)
        }
        guard result?.isFinal == true || error != nil else { return }
        task = nil
        transcribed?()
    }

    // MARK: - Encoding, on `queue`

    private func encode(_ buffer: AVAudioPCMBuffer) {
        guard !stopped, let resampler else { return }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        resampler.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }
        compress(out, end: false)
    }

    /// Encodes `pcm`, or with `end` flushes what the encoder holds, and sends a chunk once there's enough for one.
    private func compress(_ pcm: AVAudioPCMBuffer?, end: Bool) {
        guard !stopped, let encoder else { return }
        var fed = pcm == nil
        while true {
            let out = AVAudioCompressedBuffer(format: aac, packetCapacity: 16,
                                              maximumPacketSize: max(encoder.maximumOutputPacketSize, 2_048))
            var error: NSError?
            let status = encoder.convert(to: out, error: &error) { _, input in
                if !fed, let pcm {
                    fed = true
                    input.pointee = .haveData
                    return pcm
                }
                input.pointee = end ? .endOfStream : .noDataNow
                return nil
            }
            collect(out)
            if error != nil || status != .haveData { break }
        }
        if pendingFrames >= Self.framesPerChunk || (end && pendingFrames > 0) {
            onChunk(chunk, pending)
            chunk += 1
            pending = Data()
            pendingFrames = 0
        }
    }

    private func collect(_ out: AVAudioCompressedBuffer) {
        guard let descriptions = out.packetDescriptions else { return }
        let bytes = out.data.assumingMemoryBound(to: UInt8.self)
        for i in 0..<Int(out.packetCount) {
            let d = descriptions[i]
            guard d.mDataByteSize > 0,
                  let frame = ADTS.frame(Data(bytes: bytes + Int(d.mStartOffset), count: Int(d.mDataByteSize)),
                                         sampleRate: Int(Self.sampleRate)) else { continue }
            pending.append(frame)
            pendingFrames += 1
            frames += 1
        }
    }

    // MARK: - Buffers

    /// The tap's buffer belongs to the engine once the tap returns, so encoding works on a copy.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<min(from.count, to.count) {
            guard let source = from[i].mData, let target = to[i].mData else { return nil }
            memcpy(target, source, Int(min(from[i].mDataByteSize, to[i].mDataByteSize)))
        }
        return copy
    }

    private static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 6)
    }
}
