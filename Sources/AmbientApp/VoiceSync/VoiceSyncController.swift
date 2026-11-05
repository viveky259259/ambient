import AmbientCore
import AppKit
import AVFoundation
import Combine
import Speech
import SystemConfiguration
import os

/// Voice sync on this Mac, both ways. Sending: the shortcut starts a voice for the chosen Mac and the next press sends
/// it, streamed through the outbox as it's recorded. Receiving: each link hands over what arrives, which the notch shows
/// and the library keeps. Main thread only.
final class VoiceSyncController: ObservableObject {
    struct Outgoing: Equatable {
        enum Stage: Equatable {
            case recording
            /// Stopped, and waiting a moment for the last words.
            case sending
            /// Being thrown away.
            case cancelling
        }

        let id: String
        let destination: VoiceDestination
        let startedAt: Date
        var text = ""
        var stage = Stage.recording
        /// Why a chunk didn't make it into the outbox, after which the other Mac can't have the voice whole.
        var lost: String?

        var sending: Bool { stage == .sending }
    }

    struct Incoming: Equatable, Identifiable {
        let id: String
        let from: MachineRef
        let since: Date
    }

    struct Arrival: Equatable {
        let record: VoiceRecord
        let until: Date
    }

    enum Copied: Equatable {
        case text(String)
        case audio(String)
    }

    @Published private(set) var outgoing: Outgoing?
    @Published private(set) var level: Float = 0
    @Published private(set) var incoming: [Incoming] = []
    @Published private(set) var arrival: Arrival?
    @Published private(set) var notice: String?
    @Published private(set) var voices: [VoiceRecord] = []
    @Published private(set) var destinations: [VoiceDestination] = []
    @Published private(set) var playing: String?
    @Published private(set) var copied: Copied?

    /// This Mac as other Macs see it.
    let hub: VoiceHub
    /// Where a recording stops by itself.
    static let maxSeconds: TimeInterval = 600

    private let paths: AmbientPaths
    private let prefs: Preferences
    private let library: VoiceLibrary
    private let outbox: VoiceOutbox
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "voice-sync")
    private var recorder: VoiceRecorder?
    private var part: FileHandle?
    private var textSent = ""
    private var textTimer: Timer?
    private var limitTimer: Timer?
    private var arrivalTimer: Timer?
    private var noticeWork: DispatchWorkItem?
    private var copiedWork: DispatchWorkItem?
    private var refreshTimer: Timer?
    private var expireTimer: Timer?
    /// Machines whose cursor stays where it is until Ambient starts again, because a voice from them couldn't be kept.
    /// The link then starts from there, and the voice comes again.
    private var held: Set<String> = []
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?

    init(paths: AmbientPaths, prefs: Preferences) {
        self.paths = paths
        self.prefs = prefs
        library = VoiceLibrary(paths: paths)
        outbox = VoiceOutbox(dir: paths.voiceOutbox)
        hub = VoiceHub.load(paths, name: Self.computerName())
    }

    func start() {
        // Tidying reads the whole outbox, up to 40 MB, so the launch doesn't wait for it. A voice started meanwhile is
        // left as it is.
        let outbox = self.outbox
        DispatchQueue.global(qos: .utility).async { outbox.tidy() }
        library.removeParts()
        voices = library.voices
        refreshDestinations()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshDestinations() }
        refreshTimer?.tolerance = 1
        // A Mac that stays away while this one stays open still doesn't get a voice after a day.
        expireTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            guard let self, self.outgoing == nil else { return }
            let outbox = self.outbox
            DispatchQueue.global(qos: .utility).async { outbox.expire() }
        }
        expireTimer?.tolerance = 300
    }

    /// Quitting mid-recording: the receiving Mac stops waiting for it. A voice already sent, still waiting for its last
    /// words, goes now with the words so far, and both Macs keep it.
    func quit() {
        guard let outgoing else { return }
        guard outgoing.sending, outgoing.lost == nil else {
            _ = try? outbox.append(to: outgoing.destination.id, voice: outgoing.id, .cancel)
            outbox.setLive(false)
            return
        }
        let text = outgoing.text.isEmpty ? nil : VoiceLine.cap(outgoing.text)
        _ = try? outbox.append(to: outgoing.destination.id, voice: outgoing.id, .end(text: text))
        outbox.setLive(false)
        try? part?.close()
        part = nil
        self.outgoing = nil
        let audio = (try? Data(contentsOf: library.partURL(for: outgoing.id))) ?? Data()
        if let seconds = ADTS.frames(in: audio)?.seconds, seconds > 0 { keep(outgoing, seconds: seconds, text: text) }
    }

    // MARK: - Sending

    /// The Mac voices go to: the one chosen in Settings, or the one that followed this Mac most recently.
    var destination: VoiceDestination? {
        destinations.first { $0.id == prefs.voiceSyncDestination } ?? destinations.first
    }

    func choose(_ destination: VoiceDestination) {
        prefs.voiceSyncDestination = destination.id
        objectWillChange.send()
    }

    func refreshDestinations() {
        let found = VoiceDestination.load(from: paths.voiceHubsSeen).filter { $0.id != hub.id }
        if found != destinations { destinations = found }
    }

    /// The shortcut: start a voice, or send the one being recorded.
    func toggle() {
        if outgoing != nil { send() } else { record(to: nil) }
    }

    func record(to chosen: VoiceDestination?) {
        guard outgoing == nil else { return }
        refreshDestinations()
        guard let destination = chosen ?? destination else {
            // Paired, but by a Mac whose Ambient doesn't ask for voices yet.
            let paired = FileManager.default.fileExists(atPath: paths.userHome.appendingPathComponent(".ambient/bin/ambient-remote").path)
            show(paired ? "The Mac that follows this one doesn't take voices yet. Update Ambient there, then pair this Mac again."
                        : "No Mac receives voices from this one yet. Pair it from the other Mac's Settings › Remote.")
            return
        }
        Self.askForMicrophone { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.show("Ambient can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
                return
            }
            Self.askForSpeech { transcribe in self.begin(for: destination, transcribe: transcribe) }
        }
    }

    private func begin(for destination: VoiceDestination, transcribe: Bool) {
        guard outgoing == nil else { return }
        let id = VoiceHub.randomID()
        let partURL = library.partURL(for: id)
        do {
            try FileManager.default.createDirectory(at: library.audioDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: partURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw VoiceRecorderError(message: "Couldn't save the recording.")
            }
            part = try FileHandle(forWritingTo: partURL)
            outbox.setLive(true)
            try outbox.append(to: destination.id, voice: id, .start(at: Date()))
        } catch {
            fail(error, cleaning: id)
            return
        }

        let recorder = VoiceRecorder()
        let outbox = self.outbox, part = self.part, log = self.log
        recorder.onChunk = { [weak self] n, data in
            do {
                try outbox.append(to: destination.id, voice: id, .audio(n: n, data: data))
            } catch {
                log.error("Couldn't add to the outbox: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self?.lose(id, error) }
            }
            try? part?.write(contentsOf: data)
        }
        recorder.onText = { [weak self] text in self?.outgoing?.text = text }
        recorder.onLevel = { [weak self] level in self?.level = level }
        recorder.onInterrupted = { [weak self] in self?.end(note: "The microphone changed, so the voice stopped there.") }
        do {
            try recorder.start(transcribe: transcribe)
        } catch {
            _ = try? outbox.append(to: destination.id, voice: id, .cancel)
            fail(error, cleaning: id)
            return
        }
        self.recorder = recorder
        textSent = ""
        outgoing = Outgoing(id: id, destination: destination, startedAt: Date())
        notice = nil
        // The transcript goes out at most twice a second; each line carries all of it.
        textTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.sendText() }
        limitTimer = Timer.scheduledTimer(withTimeInterval: Self.maxSeconds, repeats: false) { [weak self] _ in self?.send() }
        if !transcribe { log.notice("Recording without a transcript: on-device recognition isn't available or allowed.") }
    }

    private func sendText() {
        guard let outgoing, outgoing.text != textSent else { return }
        textSent = outgoing.text
        _ = try? outbox.append(to: outgoing.destination.id, voice: outgoing.id, .text(VoiceLine.cap(outgoing.text)))
    }

    /// Stops recording and sends the end, with the final transcript.
    func send() { end(note: nil) }

    /// `send()`, with `note` saying why when it wasn't the user.
    private func end(note: String?) {
        guard var current = outgoing, current.stage == .recording, let recorder else { return }
        current.stage = .sending
        outgoing = current
        stopTimers()
        let id = current.id
        recorder.finish { [weak self] text, seconds in
            // Quitting may have sent it already. What it is now says whether a chunk was lost meanwhile.
            guard let self, let current = self.outgoing, current.id == id else { return }
            let destination = current.destination
            let final = text.map(VoiceLine.cap)
            // A chunk is missing, so the other Mac would refuse it: it's called off there instead.
            _ = try? self.outbox.append(to: destination.id, voice: current.id, current.lost == nil ? .end(text: final) : .cancel)
            self.outbox.setLive(false)
            try? self.part?.close()
            self.part = nil
            self.recorder = nil
            self.outgoing = nil
            self.level = 0
            if let lost = current.lost {
                try? FileManager.default.removeItem(at: self.library.partURL(for: current.id))
                self.show("The voice couldn't be sent. \(lost)")
                return
            }
            guard seconds > 0 else {
                try? FileManager.default.removeItem(at: self.library.partURL(for: current.id))
                self.show("Nothing was recorded. Check the microphone in System Settings › Sound.")
                return
            }
            self.keep(current, seconds: seconds, text: final)
            let online = self.destinations.first { $0.id == destination.id }?.isOnline() ?? false
            let sent = online ? "Sent to \(destination.label)" : "\(destination.label) gets it when it's back"
            self.show(note.map { "\($0) \(sent)." } ?? sent, for: note == nil ? 3 : 6)
        }
    }

    /// Adds a voice sent from here to the library, from its part.
    private func keep(_ sent: Outgoing, seconds: Double, text: String?) {
        let destination = sent.destination
        let record = VoiceRecord(id: sent.id, direction: .sent, peer: MachineRef(id: destination.id, label: destination.label),
                                 recordedAt: sent.startedAt, seconds: seconds, text: text)
        do {
            try library.addRecorded(record)
        } catch {
            log.error("Couldn't keep the sent voice: \(error.localizedDescription, privacy: .public)")
        }
        voices = library.voices
        refreshDestinations()
    }

    /// Throws the voice away. Once it's sending, it's too late: the end is on its way.
    func cancel() {
        guard var current = outgoing, current.stage == .recording, let recorder else { return }
        current.stage = .cancelling
        outgoing = current
        stopTimers()
        let id = current.id
        recorder.cancel { [weak self] in
            guard let self, let current = self.outgoing, current.id == id else { return }
            _ = try? self.outbox.append(to: current.destination.id, voice: current.id, .cancel)
            self.outbox.setLive(false)
            try? self.part?.close()
            self.part = nil
            try? FileManager.default.removeItem(at: self.library.partURL(for: current.id))
            self.recorder = nil
            self.outgoing = nil
            self.level = 0
            if let lost = current.lost { self.show("The voice couldn't be sent. \(lost)") }
        }
    }

    /// A chunk didn't make it into the outbox, so the other Mac can't have the voice whole: it stops here and is called
    /// off there. One already sending is called off when its last words are in.
    private func lose(_ id: String, _ error: Error) {
        guard var current = outgoing, current.id == id, current.lost == nil else { return }
        current.lost = error.localizedDescription
        outgoing = current
        if current.stage == .recording { cancel() }
    }

    private func stopTimers() {
        textTimer?.invalidate()
        textTimer = nil
        limitTimer?.invalidate()
        limitTimer = nil
    }

    private func fail(_ error: Error, cleaning id: String) {
        outbox.setLive(false)
        try? part?.close()
        part = nil
        try? FileManager.default.removeItem(at: library.partURL(for: id))
        show((error as? VoiceRecorderError)?.message ?? error.localizedDescription)
    }

    // MARK: - Receiving

    /// The cursor and the voices already kept, for a new link to `machine`.
    func cursor(for machine: String) -> Int64 { library.cursors[machine] ?? 0 }
    func received(from machine: String) -> Set<String> { library.received(from: machine) }

    /// What a link heard. The cursor is saved after the voices it covers, so a crash in between only repeats a voice the
    /// library already has, which the next link skips. A voice that couldn't be kept holds the cursor before it.
    func receive(_ events: [VoiceInboxEvent], cursor: Int64, from machine: MachineRef) {
        for event in events {
            switch event {
            case let .incoming(id, since):
                if !incoming.contains(where: { $0.id == id }) { incoming.append(Incoming(id: id, from: machine, since: since)) }
            case .progress:
                break
            case let .arrived(voice):
                incoming.removeAll { $0.id == voice.id }
                do {
                    try library.add(voice.record, audio: voice.audio)
                    show(arrival: voice.record)
                } catch {
                    held.insert(machine.id)
                    log.error("Couldn't keep a voice from \(machine.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            case let .ended(id):
                incoming.removeAll { $0.id == id }
            }
        }
        if !held.contains(machine.id) { try? library.setCursor(cursor, machine: machine.id) }
        voices = library.voices
    }

    private func show(arrival record: VoiceRecord) {
        let seconds = TimeInterval(max(5, prefs.voiceSyncCopySeconds))
        arrival = Arrival(record: record, until: Date().addingTimeInterval(seconds))
        arrivalTimer?.invalidate()
        arrivalTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.dismissArrival() }
    }

    func dismissArrival() {
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        arrival = nil
    }

    /// Unpaired: its voices stay, where it got to goes.
    func forget(machine id: String) {
        held.remove(id)
        try? library.forget(machine: id)
        incoming.removeAll { $0.from.id == id }
    }

    /// Purged: everything it sent goes too.
    func purge(machine id: String) {
        held.remove(id)
        try? library.purge(machine: id)
        incoming.removeAll { $0.from.id == id }
        if arrival?.record.peer.id == id { dismissArrival() }
        voices = library.voices
    }

    // MARK: - The library

    func copyText(_ record: VoiceRecord) {
        guard let text = record.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(.text(record.id))
    }

    /// Puts the voice on the clipboard as an `.m4a` file named for where and when it's from, which apps take as an
    /// attachment. The `.aac` the library keeps if converting fails.
    func copyAudio(_ record: VoiceRecord) {
        let source = library.audioURL(for: record)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Ambient Voices", isDirectory: true)
        let name = Self.fileName(for: record)
        let target = folder.appendingPathComponent(name + ".m4a")
        var file = source
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try Self.exportM4A(from: source, to: target)
            file = target
        } catch {
            log.error("Couldn't make an m4a: \(error.localizedDescription, privacy: .public)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file as NSURL])
        flash(.audio(record.id))
    }

    func togglePlay(_ record: VoiceRecord) {
        if playing == record.id {
            stopPlaying()
            return
        }
        stopPlaying()
        do {
            let player = try AVAudioPlayer(contentsOf: library.audioURL(for: record))
            let delegate = PlayerDelegate { [weak self] in self?.stopPlaying() }
            player.delegate = delegate
            player.play()
            self.player = player
            playerDelegate = delegate
            playing = record.id
        } catch {
            show("Couldn't play it: \(error.localizedDescription)")
        }
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        playerDelegate = nil
        playing = nil
    }

    func delete(_ record: VoiceRecord) {
        if playing == record.id { stopPlaying() }
        if arrival?.record.id == record.id { dismissArrival() }
        try? library.delete(record.id)
        voices = library.voices
    }

    func deleteAll() {
        stopPlaying()
        dismissArrival()
        try? library.deleteAll()
        voices = library.voices
    }

    func audioURL(for record: VoiceRecord) -> URL { library.audioURL(for: record) }

    // MARK: - Notes

    private func show(_ message: String, for seconds: TimeInterval = 6) {
        notice = message
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self?.notice == message else { return }
            self?.notice = nil
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func flash(_ what: Copied) {
        copied = what
        copiedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in if self?.copied == what { self?.copied = nil } }
        copiedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - System

    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac"
    }

    static var microphoneAllowed: Bool? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: nil
        default: false
        }
    }

    static var speechAllowed: Bool? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: true
        case .notDetermined: nil
        default: false
        }
    }

    static func askForMicrophone(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    /// Transcription is on only when it's allowed and runs on this Mac. Without it, the voice goes as audio alone.
    static func askForSpeech(_ done: @escaping (Bool) -> Void) {
        guard VoiceRecorder.recognizer() != nil else { return done(false) }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: done(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in DispatchQueue.main.async { done(status == .authorized) } }
        default: done(false)
        }
    }

    static func fileName(for record: VoiceRecord) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH.mm"
        let peer = record.peer.label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return record.direction == .received ? "Voice from \(peer), \(f.string(from: record.recordedAt))"
                                             : "Voice to \(peer), \(f.string(from: record.recordedAt))"
    }

    /// The library's ADTS as an `.m4a`, which more apps accept.
    static func exportM4A(from source: URL, to target: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: input.fileFormat.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
        let output = try AVAudioFile(forWriting: target, settings: settings, commonFormat: input.processingFormat.commonFormat,
                                     interleaved: input.processingFormat.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8_192) else { return }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let finished: () -> Void

    init(finished: @escaping () -> Void) {
        self.finished = finished
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async(execute: finished)
    }
}
