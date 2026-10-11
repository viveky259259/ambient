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
    /// Set on the main thread between jobs, read when a job starts.
    var voice: String
    var speed: Double

    static let idleTimeout: TimeInterval = 300

    init(helper: URL, pack: URL, log: URL, voice: String, speed: Double) {
        self.helper = helper
        self.pack = pack
        self.log = log
        self.voice = voice
        self.speed = speed
    }

    /// Results of a cancelled request are simply dropped by the pipeline, so the helper isn't interrupted.
    func audio(for text: String) async throws -> PCM {
        let voice = self.voice, speed = self.speed
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                c.resume(with: Result { try self.synthesize(text, voice: voice, speed: speed) })
            }
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
