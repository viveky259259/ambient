import Foundation

/// The sending Mac's outbox: the voice lines `follow` streams, each to the hub it's addressed to. The app is its only
/// writer. Each line is appended before `outbox.seq` names it, and `follow` reads only as far as `outbox.seq`, so it never
/// sees half a line. Safe from any thread.
public final class VoiceOutbox: @unchecked Sendable {
    public let dir: URL
    private let lock = NSLock()
    private var last: Int64

    public var file: URL { dir.appendingPathComponent("outbox.jsonl") }
    var seqFile: URL { dir.appendingPathComponent("outbox.seq") }
    /// There while someone records here, so `follow` checks five times a second instead of once.
    var liveFile: URL { dir.appendingPathComponent("outbox.live") }

    public init(dir: URL) {
        self.dir = dir
        last = 0
        last = readSeq()
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
        if on {
            try? prepare()
            FileManager.default.createFile(atPath: liveFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        } else {
            try? FileManager.default.removeItem(at: liveFile)
        }
    }

    /// For launch: ends voices a crash left open, keeps the last `maxAge` of voices and at most `maxBytes`, and clears a
    /// stale live marker. Voices go whole; `vseq` never changes.
    public func tidy(now: Date = Date(), maxAge: TimeInterval = 86_400, maxBytes: Int = 40 << 20) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: liveFile)
        guard let data = try? Data(contentsOf: file) else { return }

        struct Voice { var to: String; var start: Date?; var open = true; var bytes = 0 }
        var voices: [String: Voice] = [:]
        var order: [String] = []
        var kept: [(voice: String, line: Data)] = []
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            let line = Data(raw)
            guard case let .voice(v)? = try? RemoteLineDecoder.decode(line) else { continue }
            if voices[v.voice] == nil {
                voices[v.voice] = Voice(to: v.to)
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

        var dropped = Set(order.filter { (voices[$0]?.start ?? .distantPast) < now.addingTimeInterval(-maxAge) })
        var total = order.filter { !dropped.contains($0) }.reduce(0) { $0 + (voices[$1]?.bytes ?? 0) }
        for id in order where total > maxBytes && !dropped.contains(id) {
            dropped.insert(id)
            total -= voices[id]?.bytes ?? 0
        }
        let open = order.filter { voices[$0]?.open == true && !dropped.contains($0) }

        var rewritten = Data()
        for entry in kept where !dropped.contains(entry.voice) {
            rewritten.append(entry.line)
            rewritten.append(UInt8(ascii: "\n"))
        }
        // Replaced in one step, so `follow` reads the old file or the new one. The folder is the user's alone.
        if rewritten.count != data.count, (try? rewritten.write(to: file, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
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
    }

    private func saveSeq() throws {
        try Data("\(last)\n".utf8).write(to: seqFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seqFile.path)
    }

    /// The saved `vseq`, or the outbox's last line's when the seq file is lost.
    private func readSeq() -> Int64 {
        if let text = try? String(contentsOf: seqFile, encoding: .utf8),
           let n = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)), n >= 0 {
            return n
        }
        guard let data = try? Data(contentsOf: file) else { return 0 }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { raw -> Int64? in
            guard case let .voice(v)? = try? RemoteLineDecoder.decode(Data(raw)) else { return nil }
            return v.vseq
        }.max() ?? 0
    }
}
