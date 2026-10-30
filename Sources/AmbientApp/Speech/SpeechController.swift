import AmbientCore
import AppKit
import Combine
import os

enum SpeechState: Equatable {
    case idle
    case preparing
    case speaking
    /// Held partway by the pause button; continue carries on from the same spot.
    case paused
    case failed(String, offerMacVoice: Bool)
    /// A tip, such as which shortcut reads a selection.
    case hint(String)
}

/// Reads selected text aloud: one job at a time, the shortcut toggles it, and failures are shown rather than
/// papered over with another engine. Its state is touched only on the main thread: the job hops back to it to
/// publish, which is what makes the unchecked Sendable sound.
final class SpeechController: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: SpeechState = .idle {
        didSet { if state != oldValue { log.notice("speech: \(String(describing: self.state), privacy: .public)") } }
    }
    @Published private(set) var level: Float = 0
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "speech")

    /// Builds the engine for a kind. Set by the app delegate, which owns the pack folder and the Keychain.
    var makeEngine: (SpeechEngineKind) throws -> SpeechEngine = { _ in throw SpeechFailure(message: "No voice is set up.") }
    /// Shows the voice chooser the first time; calls back with true once a voice is chosen.
    var chooseEngine: (@escaping (Bool) -> Void) -> Void = { $0(false) }

    private let prefs: Preferences
    private let player = SpeechPlayer()
    private var job: Task<Void, Never>?
    private var jobID = 0
    private var lastText: String?
    private var clearFailure: DispatchWorkItem?

    static let sample = "Hi. This is the voice Ambient will use to read your agents' replies."

    init(prefs: Preferences) {
        self.prefs = prefs
        player.onLevel = { [weak self] in self?.level = $0 }
    }

    /// Reading, about to, or paused partway: the shortcut on the same text stops it, new text replaces it.
    var isActive: Bool { state == .preparing || state == .speaking || state == .paused }

    func pause(from source: String) {
        log.notice("speech: pause from \(source, privacy: .public)")
        guard state == .speaking else { return }
        player.pause()
        state = .paused
    }

    func resume(from source: String) {
        log.notice("speech: continue from \(source, privacy: .public)")
        guard state == .paused else { return }
        player.resume()
        state = .speaking
    }

    /// The shortcut or the Services item. Reads `text`; stops instead when it's empty or already being read.
    func toggle(_ text: String?) {
        let spoken = SpeechText.spoken(text ?? "", readCode: prefs.speechReadsCode)
        let kind = prefs.speechEngineKind
        switch SpeechToggle.decide(active: isActive, spoken: spoken, last: lastText, hasEngine: kind != nil) {
        case .stop:
            stop()
        case .nothingSelected:
            NSSound(named: "Tink")?.play()
            fail("Select some text first")
        case .choose:
            chooseEngine { [weak self] chosen in if chosen { self?.toggle(text) } }
        case .speak:
            if let kind { start(spoken, kind: kind) }
        }
    }

    /// Reads a sample with `kind` without saving it as the choice.
    func preview(_ kind: SpeechEngineKind) {
        start(Self.sample, kind: kind)
    }

    func stop() {
        cancelJob()
        state = .idle
    }

    func useMacVoice() {
        prefs.speechEngine = SpeechEngineKind.mac.rawValue
        stop()
    }

    func fail(_ message: String, offerMacVoice: Bool = false) {
        show(.failed(message, offerMacVoice: offerMacVoice), for: offerMacVoice ? 10 : 5)
    }

    /// A one-time tip in the island, for a few seconds; only when nothing is being read.
    func hint(_ message: String) {
        guard state == .idle else { return }
        show(.hint(message), for: 7)
    }

    /// Shows a failure or hint, then goes back to idle unless something else has happened since.
    private func show(_ shown: SpeechState, for seconds: TimeInterval) {
        state = shown
        clearFailure?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == shown else { return }
            self.state = .idle
        }
        clearFailure = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func start(_ text: String, kind: SpeechEngineKind) {
        cancelJob()
        let engine: SpeechEngine
        do {
            engine = try makeEngine(kind)
        } catch {
            report(error)
            return
        }
        jobID += 1
        let id = jobID
        lastText = text
        state = .preparing
        player.begin(id)
        let chunks = SpeechText.chunks(text)
        let player = self.player
        // The controller lives as long as the app, so the job holds it strongly.
        job = Task { [self] in
            do {
                try await SpeechPipeline.run(chunks, synthesize: { try await engine.audio(for: $0) }, play: { pcm in
                    await MainActor.run {
                        if self.jobID == id, self.state == .preparing { self.state = .speaking }
                    }
                    await player.play(pcm, job: id)
                })
                await MainActor.run { self.finish(id, error: nil) }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self.finish(id, error: error) }
            }
        }
    }

    private func finish(_ id: Int, error: Error?) {
        guard id == jobID else { return }
        job = nil
        lastText = nil
        player.stop()
        if let error { report(error) } else { state = .idle }
    }

    private func report(_ error: Error) {
        if let failure = error as? SpeechFailure {
            fail(failure.message, offerMacVoice: failure.offerMacVoice)
        } else {
            fail(error.localizedDescription)
        }
    }

    private func cancelJob() {
        job?.cancel()
        job = nil
        lastText = nil
        player.stop()
    }
}
