import Foundation

/// AAC in ADTS frames: each frame carries its own 7-byte header, so a voice can be cut into chunks at any frame and every
/// chunk checked on its own, and the chunks joined are a playable `.aac` file.
public enum ADTS {
    /// What a run of frames holds.
    public struct Frames: Equatable, Sendable {
        public let count: Int
        public let sampleRate: Int

        /// Each AAC-LC frame is 1024 samples.
        public var seconds: Double { Double(count * 1024) / Double(sampleRate) }
    }

    static let sampleRates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000]
    /// The rates a voice may use: what a Mac's microphone gives, or what it's resampled to for speech.
    static let allowedRates: Set<Int> = [48_000, 44_100, 32_000, 24_000, 22_050, 16_000]
    static let headerBytes = 7

    /// One AAC-LC mono packet with its header in front, or nil when `sampleRate` isn't allowed or the packet is too long
    /// for a frame.
    public static func frame(_ packet: Data, sampleRate: Int) -> Data? {
        guard allowedRates.contains(sampleRate), let index = sampleRates.firstIndex(of: sampleRate),
              !packet.isEmpty else { return nil }
        let length = packet.count + headerBytes
        guard length < 1 << 13 else { return nil }
        let profile = 1, channels = 1
        var header = Data(count: headerBytes)
        header[0] = 0xFF
        header[1] = 0xF1 // MPEG-4, layer 0, no CRC
        header[2] = UInt8(profile << 6 | index << 2 | channels >> 2)
        header[3] = UInt8((channels & 3) << 6 | (length >> 11) & 3)
        header[4] = UInt8((length >> 3) & 0xFF)
        header[5] = UInt8((length & 7) << 5 | 0x1F) // buffer fullness 0x7FF: variable bit rate
        header[6] = 0xFC // the rest of the fullness, and one raw data block
        return header + packet
    }

    /// The frames in `data` when it's nothing but well-formed AAC-LC mono frames at one allowed rate, end to end; nil for
    /// anything else, including a partial frame at the end.
    public static func frames(in data: Data) -> Frames? {
        let bytes = [UInt8](data)
        var at = 0, count = 0
        var rate: Int?
        while at < bytes.count {
            guard bytes.count - at >= headerBytes else { return nil }
            let b = bytes[at..<(at + headerBytes)].map(Int.init)
            // Sync word, either MPEG id, layer 0 and no CRC.
            guard b[0] == 0xFF, b[1] == 0xF1 || b[1] == 0xF9 else { return nil }
            guard b[2] >> 6 == 1 else { return nil } // AAC-LC
            let index = (b[2] >> 2) & 0xF
            guard index < sampleRates.count, allowedRates.contains(sampleRates[index]) else { return nil }
            guard rate == nil || rate == sampleRates[index] else { return nil }
            rate = sampleRates[index]
            guard (b[2] & 1) << 2 | b[3] >> 6 == 1 else { return nil } // mono
            let length = (b[3] & 3) << 11 | b[4] << 3 | b[5] >> 5
            guard b[6] & 3 == 0, length > headerBytes, length <= bytes.count - at else { return nil }
            at += length
            count += 1
        }
        guard let rate, count > 0 else { return nil }
        return Frames(count: count, sampleRate: rate)
    }
}
