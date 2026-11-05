import Foundation

/// The sending Mac's outbox: the voice lines `follow` streams, each to the hub it's addressed to. The app is its only
/// writer. Each line is appended before `outbox.seq` names it, and `follow` reads only as far as `outbox.seq`, so it never
/// sees half a line. Safe from any thread.
///
/// `outbox.seq` is two lines: the newest `vseq`, which is all a shim from before 1.0.6 reads, then the epoch, the file's
/// length after that line and the generation, as `<epoch> <bytes> <generation>`.
public final class VoiceOutbox: @unchecked Sendable {
    public let dir: URL
    private let lock = NSLock()
    private var last: Int64
    /// Names this outbox for the hubs that follow it. A new one is made whenever `outbox.seq` names none: a new outbox, a
    /// lost seq file, or one from before epochs. So a hub whose cursor was for another outbox starts over, however far
    /// this one has grown.
    public private(set) var epoch: String
    /// The file's length after line `last`, which is where `follow` reads on from.
    private var bytes: Int64 = 0
    /// How many times `trim` has rewritten the file, moving every line. A `follow` that sees it change reads it all again.
    private var generation: Int64 = 0
    /// `last` when this outbox was opened: a voice that starts after it is this process's own.
    private var opened: Int64
    /// This process put the live marker there.
    private var live = false

    public var file: URL { dir.appendingPathComponent("outbox.jsonl") }
    var seqFile: URL { dir.appendingPathComponent("outbox.seq") }
    /// There while someone records here, so `follow` checks five times a second instead of once.
    var liveFile: URL { dir.appendingPathComponent("outbox.live") }

    public init(dir: URL) {
        self.dir = dir
        last = 0
        opened = 0
        epoch = ""
        let saved = readSeq()
        last = saved.last
        opened = last
        if let place = saved.place {
            epoch = place.epoch
            generation = place.generation
        } else {
            epoch = Self.newEpoch()
        }
    }

    /// Appends one line and returns its `vseq`.
    @discardableResult
    public func append(to hub: String, voice: String, _ part: VoiceLine.Part) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        try prepare()
        let line = VoiceLine(vseq: last + 1, to: hub, voice: voice, part: part)
        try write(line.encoded() + Data([UInt8(ascii: "\n")]))
        last += 1
        try saveSeq()
        return last
    }

    public func setLive(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        live = on
        if on {
            try? prepare()
            FileManager.default.createFile(atPath: liveFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        } else {
            try? FileManager.default.removeItem(at: liveFile)
        }
    }

    /// For launch: ends voices a crash left open, keeps the last `maxAge` of voices and at most `maxBytes`, and clears a
    /// stale live marker. Voices go whole; `vseq` never changes. It may run while a voice is recorded, off the main
    /// thread: one started since this outbox was opened stays as it is, with its marker, as `expire` leaves it.
    public func tidy(now: Date = Date(), maxAge: TimeInterval = 86_400, maxBytes: Int = 40 << 20) {
        lock.lock(); defer { lock.unlock() }
        if !live { try? FileManager.default.removeItem(at: liveFile) }
        trim(now: now, maxAge: maxAge, maxBytes: maxBytes, endingOpen: true)
    }

    /// While Ambient runs: keeps the last `maxAge` of voices and at most `maxBytes`, as `tidy` does, but a voice that's
    /// still open is being recorded, so it stays as it is.
    public func expire(now: Date = Date(), maxAge: TimeInterval = 86_400, maxBytes: Int = 40 << 20) {
        lock.lock(); defer { lock.unlock() }
        trim(now: now, maxAge: maxAge, maxBytes: maxBytes, endingOpen: false)
    }

    /// Only with `lock` held.
    private func trim(now: Date, maxAge: TimeInterval, maxBytes: Int, endingOpen: Bool) {
        guard let data = try? Data(contentsOf: file) else { return }

        struct Voice { var to: String; var first: Int64; var start: Date?; var open = true; var bytes = 0 }
        var voices: [String: Voice] = [:]
        var order: [String] = []
        var kept: [(voice: String, line: Data)] = []
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard case let .voice(v)? = try? RemoteLineDecoder.decode(line) else { continue }
            if voices[v.voice] == nil {
                voices[v.voice] = Voice(to: v.to, first: v.vseq)
                order.append(v.voice)
            }
            switch v.part {
            case let .start(at): voices[v.voice]?.start = at
            case .end, .cancel: voices[v.voice]?.open = false
            default: break
            }
            voices[v.voice]?.bytes += line.count + 1
            kept.append((v.voice, line))
        }

        // An open voice is being recorded, except, ending them, one a crash left: it started before this outbox opened.
        let recording = Set(order.filter { id in
            guard let voice = voices[id], voice.open else { return false }
            return !endingOpen || voice.first > opened
        })
        var dropped = Set(order.filter {
            !recording.contains($0) && (voices[$0]?.start ?? .distantPast) < now.addingTimeInterval(-maxAge)
        })
        var total = order.filter { !dropped.contains($0) }.reduce(0) { $0 + (voices[$1]?.bytes ?? 0) }
        for id in order where total > maxBytes && !dropped.contains(id) && !recording.contains(id) {
            dropped.insert(id)
            total -= voices[id]?.bytes ?? 0
        }
        let open = endingOpen ? order.filter { voices[$0]?.open == true && !dropped.contains($0) && !recording.contains($0) } : []

        var rewritten = Data()
        for entry in kept where !dropped.contains(entry.voice) {
            rewritten.append(entry.line)
            rewritten.append(UInt8(ascii: "\n"))
        }
        // Replaced in one step, so `follow` reads the old file or the new one. The folder is the user's alone.
        bytes = Int64(data.count)
        if rewritten.count != data.count, (try? rewritten.write(to: file, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            bytes = Int64(rewritten.count)
            generation += 1
        }
        for id in open {
            guard let to = voices[id]?.to else { continue }
            let line = VoiceLine(vseq: last + 1, to: to, voice: id, part: .cancel)
            guard (try? write(line.encoded() + Data([UInt8(ascii: "\n")]))) != nil else { break }
            last += 1
        }
        try? saveSeq()
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func write(_ line: Data) throws {
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw CocoaError(.fileWriteOutOfSpace) }
        // Appending leaves the offset at the end of the file, whatever was there before.
        bytes = Int64(lseek(fd, 0, SEEK_CUR))
    }

    private func saveSeq() throws {
        try Data("\(last)\n\(epoch) \(bytes) \(generation)\n".utf8).write(to: seqFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seqFile.path)
    }

    /// The saved `vseq`, or the outbox's last line's when the seq file is lost, and the epoch and generation when the
    /// file has them. One from before epochs has only the `vseq`.
    private func readSeq() -> (last: Int64, place: (epoch: String, generation: Int64)?) {
        if let text = try? String(contentsOf: seqFile, encoding: .utf8) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if let n = Int64(lines[0].trimmingCharacters(in: .whitespaces)), n >= 0 {
                let words = lines.count > 1 ? lines[1].split(separator: " ") : []
                guard words.count == 3, Self.isEpoch(String(words[0])), Int64(words[1]) != nil,
                      let generation = Int64(words[2]) else { return (n, nil) }
                return (n, (String(words[0]), generation))
            }
        }
        guard let data = try? Data(contentsOf: file) else { return (0, nil) }
        let last = data.split(separator: UInt8(ascii: "\n")).compactMap { raw -> Int64? in
            guard case let .voice(v)? = try? RemoteLineDecoder.decode(Data(raw)) else { return nil }
            return v.vseq
        }.max() ?? 0
        return (last, nil)
    }

    /// 16 lowercase hex digits, as the spool's epoch is.
    static func isEpoch(_ s: String) -> Bool {
        s.range(of: #"\A[0-9a-f]{16}\z"#, options: .regularExpression) != nil
    }

    static func newEpoch() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
