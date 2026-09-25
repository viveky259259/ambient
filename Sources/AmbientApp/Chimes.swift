import AmbientCore
import AppKit

/// Soft two-note chimes, synthesized once at launch: rising for done, a double tap for
/// "needs you", falling for an error.
final class Chimes {
    private struct Note {
        let frequency: Double
        let start: Double
        let decay: Double
    }

    private var sounds: [Mood: NSSound] = [:]

    init() {
        sounds[.done] = Self.sound([Note(frequency: 659.25, start: 0, decay: 0.38), Note(frequency: 987.77, start: 0.11, decay: 0.5)])
        sounds[.waiting] = Self.sound([Note(frequency: 880, start: 0, decay: 0.16), Note(frequency: 880, start: 0.17, decay: 0.26)])
        sounds[.error] = Self.sound([Note(frequency: 587.33, start: 0, decay: 0.3), Note(frequency: 440, start: 0.14, decay: 0.42)],
                                    warmth: 0.5)
    }

    func play(_ mood: Mood, volume: Double) {
        guard let sound = sounds[mood], volume > 0 else { return }
        sound.stop()
        sound.volume = Float(min(1, max(0, volume)))
        sound.play()
    }

    private static func sound(_ notes: [Note], warmth: Double = 0.3) -> NSSound? {
        NSSound(data: wav(notes, warmth: warmth))
    }

    /// 16-bit mono PCM WAV of decaying sine partials.
    private static func wav(_ notes: [Note], warmth: Double) -> Data {
        let rate = 44_100.0
        let length = (notes.map { $0.start + $0.decay * 6 }.max() ?? 1)
        let count = Int(length * rate)
        var samples = [Double](repeating: 0, count: count)
        for note in notes {
            let first = Int(note.start * rate)
            for i in first..<count {
                let t = Double(i - first) / rate
                let attack = min(1, t / 0.004)
                let env = attack * exp(-t / note.decay)
                let w = 2 * Double.pi * note.frequency * t
                samples[i] += env * (sin(w) + warmth * sin(2 * w) * exp(-t / (note.decay * 0.5)) + 0.08 * sin(3 * w))
            }
        }
        let peak = samples.map(abs).max() ?? 1
        let scale = 0.55 / max(peak, 0.0001)

        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for s in samples { append(Int16(max(-32_767, min(32_767, s * scale * 32_767)))) }
        return data
    }
}
