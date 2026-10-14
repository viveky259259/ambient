import AmbientCore
import Foundation

/// The offline Kokoro model, in the `ambient-voice` helper. One helper process serves every request in turn and is
/// kept alive between selections so the model loads once; it's ended after 5 idle minutes. Its state lives on its
/// own serial queue, which is what makes the unchecked Sendable sound.
final class KokoroVoice: SpeechEngine, @unchecked Sendable {
    private let helper: URL
    private let pack: URL
    private let log: URL
    private let queue = DispatchQueue(label: "com.viveky259259.Ambient.kokoro")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var idle: DispatchWorkItem?
    private var nextID = 0
    /// Owned by `queue`, like the rest of the state; changed through `configure`.
    private var voice: String
    private var speed: Double

    static let idleTimeout: TimeInterval = 300
    /// A chunk that takes longer than this means the helper is stuck; it's killed so the pipe closes.
    static let requestTimeout: TimeInterval = 30

    init(helper: URL, pack: URL, log: URL, voice: String, speed: Double) {
        self.helper = helper
        self.pack = pack
        self.log = log
        self.voice = voice
        self.speed = speed
    }

    /// Results of a cancelled request are simply dropped by the pipeline, so the helper isn't interrupted.
    func audio(for text: String) async throws -> PCM {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                c.resume(with: Result { try self.synthesize(text, voice: self.voice, speed: self.speed) })
            }
        }
    }

    /// Applies to requests made after it, since it's queued behind any already waiting.
    func configure(voice: String, speed: Double) {
        queue.async {
            self.voice = voice
            self.speed = speed
        }
    }

    func shutDown() {
        queue.async { self.stopProcess() }
    }

    private func synthesize(_ text: String, voice: String, speed: Double) throws -> PCM {
        idle?.cancel()
        defer { scheduleIdleExit() }
        try startIfNeeded()
        guard let input, let output else { throw stopped() }
        nextID += 1
        let id = String(nextID)
        do {
            try input.write(contentsOf: VoiceWire.line(VoiceWire.Request(id: id, text: text, voice: voice, speed: speed)))
        } catch {
            stopProcess()
            throw stopped()
        }
        // A hung helper never closes its pipe, so the read below would block this queue forever. Killing it closes
        // the pipe, the read returns end-of-file, and the user gets "Offline voice stopped".
        let running = process
        let watchdog = DispatchWorkItem {
            if let running, running.isRunning { kill(running.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.requestTimeout, execute: watchdog)
        defer { watchdog.cancel() }
        var reader = VoiceWire.Reader()
        var samples: [Float] = []
        var sampleRate = 24_000
        while true {
            let data = output.availableData
            if data.isEmpty {
                stopProcess()
                throw stopped()
            }
            let events: [VoiceWire.Event]
            do {
                events = try reader.feed(data)
            } catch {
                stopProcess()
                throw stopped()
            }
            for event in events {
                switch event {
                case .header(let header):
                    if let error = header.error {
                        throw SpeechFailure(message: "The offline voice couldn't read that (\(error)).", offerMacVoice: true)
                    }
                    guard header.id == id else {
                        stopProcess()
                        throw stopped()
                    }
                    sampleRate = header.sampleRate ?? sampleRate
                case .samples(let s):
                    samples += s
                case .end:
                    return try PCM.mono(samples, sampleRate: sampleRate)
                }
            }
        }
    }

    private func startIfNeeded() throws {
        if let process, process.isRunning { return }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw SpeechFailure(message: "The offline voice isn't installed. Download it in Settings › Voice.",
                                offerMacVoice: true)
        }
        let p = Process()
        p.executableURL = helper
        p.arguments = [pack.path]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        FileManager.default.createFile(atPath: log.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: log)) ?? FileHandle.nullDevice
        do { try p.run() } catch { throw stopped() }
        process = p
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }

    private func stopProcess() {
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
        output = nil
    }

    private func scheduleIdleExit() {
        let work = DispatchWorkItem { [weak self] in self?.stopProcess() }
        idle = work
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    private func stopped() -> SpeechFailure {
        SpeechFailure(message: "Offline voice stopped", offerMacVoice: true)
    }
}
