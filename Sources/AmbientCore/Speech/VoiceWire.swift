import Foundation

/// How Ambient and the `ambient-voice` helper talk over the helper's stdin and stdout.
///
/// Request: one JSON line. Response: a JSON header line, then frames of a little-endian `UInt32` byte count followed
/// by that many bytes of little-endian float32 mono PCM, ending with a zero-length frame. A header with `error` has
/// no frames.
public enum VoiceWire {
    public struct Request: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        public var voice: String
        public var speed: Double

        public init(id: String, text: String, voice: String, speed: Double) {
            self.id = id
            self.text = text
            self.voice = voice
            self.speed = speed
        }
    }

    public struct Header: Codable, Equatable, Sendable {
        public var id: String
        public var sampleRate: Int?
        public var error: String?

        public init(id: String, sampleRate: Int? = nil, error: String? = nil) {
            self.id = id
            self.sampleRate = sampleRate
            self.error = error
        }
    }

    public enum Event: Equatable, Sendable {
        case header(Header)
        case samples([Float])
        case end
    }

    public enum WireError: Error, Equatable {
        case malformedHeader
        case badFrame(Int)
    }

    /// 16 MB: about three minutes of audio, far more than one chunk produces.
    public static let maxFrameBytes = 16 << 20
    public static let end = Data(count: 4)

    public static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }

    public static func request(from line: Data) -> Request? {
        try? JSONDecoder().decode(Request.self, from: line)
    }

    public static func frame(_ samples: [Float]) -> Data {
        var data = Data()
        withUnsafeBytes(of: UInt32(samples.count * 4).littleEndian) { data.append(contentsOf: $0) }
        for s in samples {
            withUnsafeBytes(of: s.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Reads a stream of responses. Feed it bytes as they arrive; it returns whatever events are complete.
    public struct Reader: Sendable {
        private var buffer = Data()
        private var inFrames = false

        public init() {}

        public mutating func feed(_ data: Data) throws -> [Event] {
            buffer.append(data)
            var events: [Event] = []
            while true {
                if !inFrames {
                    guard let newline = buffer.firstIndex(of: 0x0A) else { break }
                    let line = buffer[buffer.startIndex..<newline]
                    guard let header = try? JSONDecoder().decode(Header.self, from: line) else {
                        throw WireError.malformedHeader
                    }
                    consume(newline - buffer.startIndex + 1)
                    events.append(.header(header))
                    inFrames = header.error == nil
                } else {
                    guard buffer.count >= 4 else { break }
                    let n = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
                    guard n <= VoiceWire.maxFrameBytes, n % 4 == 0 else { throw WireError.badFrame(n) }
                    if n == 0 {
                        consume(4)
                        events.append(.end)
                        inFrames = false
                        continue
                    }
                    guard buffer.count >= 4 + n else { break }
                    let samples = buffer.dropFirst(4).prefix(n).withUnsafeBytes { raw in
                        (0..<n / 4).map {
                            Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
                        }
                    }
                    consume(4 + n)
                    events.append(.samples(samples))
                }
            }
            return events
        }

        /// Drops `count` bytes and rebases, so indices start at zero again.
        private mutating func consume(_ count: Int) {
            buffer = Data(buffer.dropFirst(count))
        }
    }
}
