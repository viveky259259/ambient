import AVFoundation

/// One audio engine for every voice: converts each chunk to 24 kHz mono and plays chunks back to back. Used from the
/// main thread, like the rest of the app. A job token guards against a stopped job's audio sneaking in after a new
/// one starts: scheduling happens on the main thread, where `stop()` runs, so it sees the token `stop()` cleared.
/// Everything but `play`'s wait runs on the main thread, which is what makes the unchecked Sendable sound.
final class SpeechPlayer: @unchecked Sendable {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var job = 0
    private var paused = false
    private var lastLevelAt = Date.distantPast
    /// Loudness 0...1, about 15 times a second while playing, on the main thread.
    var onLevel: (Float) -> Void = { _ in }

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.format)
    }

    func begin(_ job: Int) {
        stop()
        self.job = job
    }

    /// Returns when the chunk has played, or right away if it belongs to a stopped job. Callable from any thread.
    func play(_ pcm: PCM, job: Int) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                // An empty buffer may never report that it played, so it's skipped rather than scheduled.
                guard job == self.job, pcm.buffer.frameLength > 0, let buffer = self.convert(pcm.buffer),
                      buffer.frameLength > 0, self.startEngine() else {
                    c.resume()
                    return
                }
                // While paused, the chunk is queued behind the paused one rather than starting the player.
                if !self.node.isPlaying, !self.paused { self.node.play() }
                // Called when the buffer has played, and also when the player is stopped.
                self.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in c.resume() }
            }
        }
    }

    /// Stops sound now. A waiting `play` returns.
    /// Holds the voice where it is; scheduled audio waits, and `resume()` carries on from the same spot.
    func pause() {
        paused = true
        node.pause()
        onLevel(0)
    }

    func resume() {
        paused = false
        node.play()
    }

    func stop() {
        job = 0
        paused = false
        node.stop()
        if engine.isRunning {
            engine.mainMixerNode.removeTap(onBus: 0)
            engine.stop()
        }
        onLevel(0)
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            let level = Self.level(buffer)
            DispatchQueue.main.async { self?.publish(level) }
        }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func publish(_ level: Float) {
        let now = Date()
        guard job != 0, !paused, now.timeIntervalSince(lastLevelAt) > 1.0 / 15 else { return }
        lastLevelAt = now
        onLevel(level)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == Self.format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: Self.format) else { return nil }
        let ratio = Self.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    private static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 4)
    }
}
