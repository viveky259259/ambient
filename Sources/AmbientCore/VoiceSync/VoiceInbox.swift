import Foundation

/// A finished voice from another Mac, ready for the library.
public struct VoiceArrival: Equatable, Sendable {
    public let id: String
    public let machine: MachineRef
    public let recordedAt: Date
    public let seconds: Double
    public let text: String?
    /// ADTS frames, end to end: a playable `.aac` file.
    public let audio: Data

    public var record: VoiceRecord {
        VoiceRecord(id: id, direction: .received, peer: machine, recordedAt: recordedAt, seconds: seconds, text: text)
    }
}

/// How far a machine's voices have been received: up to `vseq` of the outbox named by `epoch`. The epoch is nil until
/// a shim reports one; a shim from before 1.0.6 never does.
public struct VoiceCursor: Equatable, Sendable {
    public var vseq: Int64
    public var epoch: String?

    public init(vseq: Int64 = 0, epoch: String? = nil) {
        self.vseq = vseq
        self.epoch = epoch
    }
}

/// What the receiving Mac shows as voices come in.
public enum VoiceInboxEvent: Equatable, Sendable {
    /// Someone started recording for this Mac. `since` is this Mac's clock.
    case incoming(id: String, since: Date)
    case progress(id: String, seconds: Double, text: String?)
    case arrived(VoiceArrival)
    /// Cancelled, refused, or cut off by the link. Stop showing it.
    case ended(id: String)
}

/// Puts one machine's voices together from their lines, as `RemoteIngest` does for events: no I/O beyond the audit log.
/// It decides what's a duplicate, what's too much and how far the stream can safely resume from. Not thread-safe: the
/// link owns it.
public final class VoiceInbox {
    public struct Limits: Sendable {
        /// Ten minutes, which is where the sender stops, and a little room.
        public var maxSeconds: Double = 610
        public var maxBytes = 4 << 20
        /// Voices a machine may have going at once.
        public var maxInFlight = 2
        /// A voice that hears nothing for this long on a live link has lost its sender.
        public var silence: TimeInterval = 120

        public init() {}
    }

    private struct Pending {
        let start: Int64
        let recordedAt: Date
        var nextChunk = 0
        var audio = Data()
        var frames = 0
        var rate: Int?
        var text: String?
        var heardAt: Date

        var seconds: Double { rate.map { Double(frames * 1024) / Double($0) } ?? 0 }
    }

    public let machine: MachineRef
    public let hub: String
    public let limits: Limits
    /// Where a reconnect resumes: never past the start of a voice still coming in, so a cut-off voice is replayed whole.
    public private(set) var cursor: Int64
    /// The outbox `cursor` counts in.
    public private(set) var epoch: String?
    private var seen: Int64
    private var pending: [String: Pending] = [:]
    /// Finished, cancelled or refused: never assembled again.
    private var done: Set<String>
    private var throttle: RemoteAuditThrottle

    public init(machine: MachineRef, hub: String, cursor: VoiceCursor, known: Set<String> = [], limits: Limits = Limits(),
                audit: RemoteAudit? = nil) {
        self.machine = machine
        self.hub = hub
        self.limits = limits
        self.cursor = max(0, cursor.vseq)
        epoch = cursor.epoch
        seen = self.cursor
        done = known
        throttle = RemoteAuditThrottle(audit: audit)
    }

    /// A new connection replays from `cursor`.
    public func beginConnection() {
        seen = cursor
        pending = [:]
    }

    /// The connection is gone: what was coming in is cut off, and comes back whole with the replay.
    public func connectionEnded(now: Date) -> [VoiceInboxEvent] {
        throttle.flush(now: now)
        let cut = pending.keys.sorted().map { VoiceInboxEvent.ended(id: $0) }
        pending = [:]
        seen = cursor
        return cut
    }

    /// What to save to resume from.
    public var saved: VoiceCursor { VoiceCursor(vseq: cursor, epoch: epoch) }

    /// The machine said hello: `head` is the newest line in its outbox, and `epoch` names the outbox when its shim says.
    /// Returns true when the cursor was for another outbox, and so starts over: the outbox is behind the cursor, or it
    /// has an epoch that isn't the cursor's. A cursor with no epoch takes the first one it's given.
    public func linked(head: Int64, epoch: String?) -> Bool {
        let replaced = cursor > head || (epoch != nil && self.epoch != nil && epoch != self.epoch)
        if replaced {
            cursor = 0
            seen = 0
            pending = [:]
            self.epoch = epoch
        } else if let epoch {
            self.epoch = epoch
        }
        return replaced
    }

    public func receive(_ line: VoiceLine, now: Date) -> [VoiceInboxEvent] {
        guard line.to == hub else {
            throttle.record(.rejected, machine: machine.id, detail: "voiceAddress", now: now)
            return []
        }
        guard line.vseq > seen else { return [] }
        seen = line.vseq
        defer { advance() }
        guard !done.contains(line.voice) else { return [] }
        let id = line.voice

        if case let .start(at) = line.part {
            guard pending[id] == nil else { return refuse(id, "voiceRestart", now: now) }
            guard pending.count < limits.maxInFlight else { return refuse(id, "voiceBusy", now: now) }
            pending[id] = Pending(start: line.vseq, recordedAt: min(at, now), heardAt: now)
            return [.incoming(id: id, since: now)]
        }
        // A voice that started before the cursor: it was saved, or cut off and will replay from its start.
        guard var voice = pending[id] else { return [] }
        voice.heardAt = now
        switch line.part {
        case .start:
            return []
        case let .audio(n, data):
            guard n == voice.nextChunk else { return refuse(id, "voiceOrder", now: now) }
            guard let frames = ADTS.frames(in: data) else { return refuse(id, "voiceAudio", now: now) }
            guard voice.rate == nil || voice.rate == frames.sampleRate else { return refuse(id, "voiceRate", now: now) }
            voice.nextChunk += 1
            voice.rate = frames.sampleRate
            voice.frames += frames.count
            voice.audio.append(data)
            guard voice.audio.count <= limits.maxBytes else { return refuse(id, "voiceSize", now: now) }
            guard voice.seconds <= limits.maxSeconds else { return refuse(id, "voiceLength", now: now) }
            pending[id] = voice
            return [.progress(id: id, seconds: voice.seconds, text: voice.text)]
        case let .text(text):
            voice.text = text
            pending[id] = voice
            return [.progress(id: id, seconds: voice.seconds, text: text)]
        case let .end(text):
            pending[id] = nil
            done.insert(id)
            guard !voice.audio.isEmpty else { return [.ended(id: id)] }
            // An end whose words were all stripped falls back to the transcript so far, as one without words does.
            let final = (text.flatMap { $0.isEmpty ? nil : $0 } ?? voice.text).flatMap { $0.isEmpty ? nil : $0 }
            return [.arrived(VoiceArrival(id: id, machine: machine, recordedAt: voice.recordedAt, seconds: voice.seconds,
                                          text: final, audio: voice.audio))]
        case .cancel:
            pending[id] = nil
            done.insert(id)
            return [.ended(id: id)]
        }
    }

    /// Drops voices whose sender went quiet on a live link. Its next launch cancels them anyway.
    public func sweep(now: Date) -> [VoiceInboxEvent] {
        let quiet = pending.filter { now.timeIntervalSince($0.value.heardAt) > limits.silence }.keys.sorted()
        guard !quiet.isEmpty else { return [] }
        for id in quiet {
            pending[id] = nil
            done.insert(id)
            throttle.record(.rejected, machine: machine.id, detail: "voiceSilent", now: now)
        }
        advance()
        return quiet.map { .ended(id: $0) }
    }

    /// In flight, by id.
    public var inFlight: Set<String> { Set(pending.keys) }

    private func refuse(_ id: String, _ code: String, now: Date) -> [VoiceInboxEvent] {
        pending[id] = nil
        done.insert(id)
        throttle.record(.rejected, machine: machine.id, detail: code, now: now)
        return [.ended(id: id)]
    }

    private func advance() {
        cursor = pending.values.map { $0.start - 1 }.min() ?? seen
    }
}
