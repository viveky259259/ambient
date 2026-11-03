import Foundation

/// One voice, sent or received, as the library keeps it.
public struct VoiceRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Direction: String, Codable, Sendable { case sent, received }

    public let id: String
    public let direction: Direction
    /// The other Mac: the machine it came from, or the hub it went to.
    public var peer: MachineRef
    public let recordedAt: Date
    public var seconds: Double
    /// Nil when this Mac couldn't transcribe it.
    public var text: String?

    public init(id: String, direction: Direction, peer: MachineRef, recordedAt: Date, seconds: Double, text: String?) {
        self.id = id
        self.direction = direction
        self.peer = peer
        self.recordedAt = recordedAt
        self.seconds = seconds
        self.text = text
    }

    /// The audio's file name in the library's `audio` folder.
    public var audioFile: String { "\(id).aac" }
}

/// Every voice this Mac sent or received, kept until the user deletes it: `library.json` for what each one is and how far
/// each machine's voices have been received, `audio/<id>.aac` for the sound. A cursor is saved with the voice that moves
/// it, or after it, never before, so a hub killed at any point loses no voice; one it gets again is already known. Not
/// thread-safe: one owner.
public final class VoiceLibrary {
    private struct Envelope: Codable {
        var version = 1
        var voices: [VoiceRecord]
        var cursors: [String: Int64]
    }

    public let url: URL
    public let audioDir: URL
    /// Newest first.
    public private(set) var voices: [VoiceRecord] = []
    /// The `vseq` each machine's voices have been received up to.
    public private(set) var cursors: [String: Int64] = [:]
    /// `library.json` is there, but this version can't read it.
    private var unreadable = false

    public init(paths: AmbientPaths) {
        url = paths.voiceLibrary
        audioDir = paths.voiceAudio
        reload()
    }

    /// Reads the file again. A missing one is an empty library. So is one this version can't read, which may be a newer
    /// version's or damaged: the first save moves it aside, to `library.unreadable-<time>.json`, rather than replace it.
    public func reload() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let envelope = try? JSONDecoder.voice.decode(Envelope.self, from: data), envelope.version == 1 else {
            unreadable = true
            return
        }
        unreadable = false
        voices = envelope.voices.filter { VoiceLine.isID($0.id) }.sorted { $0.recordedAt > $1.recordedAt }
        cursors = envelope.cursors
    }

    public func audioURL(for record: VoiceRecord) -> URL {
        audioDir.appendingPathComponent(record.audioFile)
    }

    /// Where a voice being recorded here collects its audio until it's added.
    public func partURL(for id: String) -> URL {
        audioDir.appendingPathComponent("\(id).aac.part")
    }

    public func record(_ id: String) -> VoiceRecord? {
        voices.first { $0.id == id }
    }

    /// The voices already received from `machine`, so a replay doesn't keep one twice.
    public func received(from machine: String) -> Set<String> {
        Set(voices.filter { $0.direction == .received && $0.peer.id == machine }.map(\.id))
    }

    /// Adds a voice with its audio. `cursor`, when given, is saved in the same write.
    public func add(_ record: VoiceRecord, audio: Data, cursor: (machine: String, vseq: Int64)? = nil) throws {
        try prepare()
        let file = audioURL(for: record)
        try audio.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try insert(record, cursor: cursor)
    }

    /// Adds a voice recorded here, whose audio is already at `partURL(for:)`.
    public func addRecorded(_ record: VoiceRecord) throws {
        try prepare()
        let part = partURL(for: record.id), file = audioURL(for: record)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: part, to: file)
        try insert(record, cursor: nil)
    }

    public func setCursor(_ vseq: Int64, machine: String) throws {
        guard cursors[machine] != vseq else { return }
        cursors[machine] = vseq
        try save()
    }

    public func delete(_ id: String) throws {
        guard let record = record(id) else { return }
        voices.removeAll { $0.id == id }
        try save()
        try? FileManager.default.removeItem(at: audioURL(for: record))
    }

    public func deleteAll() throws {
        let gone = voices
        voices = []
        try save()
        for record in gone { try? FileManager.default.removeItem(at: audioURL(for: record)) }
    }

    /// Unpairing: the machine's voices stay, but where it got to goes, as its sessions' cursor does.
    public func forget(machine: String) throws {
        guard cursors[machine] != nil else { return }
        cursors[machine] = nil
        try save()
    }

    /// Purging: every voice received from the machine goes too.
    public func purge(machine: String) throws {
        let gone = voices.filter { $0.direction == .received && $0.peer.id == machine }
        guard !gone.isEmpty || cursors[machine] != nil else { return }
        voices.removeAll { $0.direction == .received && $0.peer.id == machine }
        cursors[machine] = nil
        try save()
        for record in gone { try? FileManager.default.removeItem(at: audioURL(for: record)) }
    }

    /// Partial recordings a crash left behind.
    public func removeParts() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: audioDir.path) else { return }
        for name in names where name.hasSuffix(".aac.part") {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(name))
        }
    }

    private func insert(_ record: VoiceRecord, cursor: (machine: String, vseq: Int64)?) throws {
        voices.removeAll { $0.id == record.id }
        voices.append(record)
        voices.sort { $0.recordedAt > $1.recordedAt }
        if let cursor { cursors[cursor.machine] = cursor.vseq }
        try save()
    }

    private func prepare() throws {
        for dir in [url.deletingLastPathComponent(), audioDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }

    private func save() throws {
        try prepare()
        if unreadable {
            try setAside()
            unreadable = false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Envelope(voices: voices, cursors: cursors)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Moves the unreadable file to a name of its own, next to it. One set aside before stays as it is.
    private func setAside() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let dir = url.deletingLastPathComponent(), stamp = Int(Date().timeIntervalSince1970)
        var aside = dir.appendingPathComponent("library.unreadable-\(stamp).json")
        var n = 1
        while FileManager.default.fileExists(atPath: aside.path) {
            aside = dir.appendingPathComponent("library.unreadable-\(stamp)-\(n).json")
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: aside)
    }
}

private extension JSONDecoder {
    static var voice: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
