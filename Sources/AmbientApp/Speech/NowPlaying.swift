import AppKit
import Combine
import MediaPlayer

/// Makes reading aloud answer the play/pause controls macOS routes to whatever is "now playing": the keyboard's ⏯
/// key, AirPods and other headphones (tap, squeeze, or taking one out), and Control Center. Ambient claims Now
/// Playing only while it's reading or paused, and gives it back when it stops, so ⏯ goes to Music or Spotify again.
final class NowPlaying {
    private let speech: SpeechController
    private var cancellable: AnyCancellable?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var claimed = false

    init(speech: SpeechController) {
        self.speech = speech
    }

    func start() {
        cancellable = speech.$state
            .removeDuplicates()
            .sink { [weak self] state in DispatchQueue.main.async { self?.update(state) } }
    }

    private func update(_ state: SpeechState) {
        switch state {
        case .preparing, .speaking, .paused:
            claim()
            let center = MPNowPlayingInfoCenter.default()
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: "Reading your selection",
                MPMediaItemPropertyArtist: "Ambient",
                MPNowPlayingInfoPropertyPlaybackRate: state == .paused ? 0.0 : 1.0,
            ]
            center.playbackState = state == .paused ? .paused : .playing
        case .idle, .failed, .hint:
            release()
        }
    }

    private func claim() {
        guard !claimed else { return }
        claimed = true
        let commands = MPRemoteCommandCenter.shared()
        add(commands.togglePlayPauseCommand) { [weak self] in
            guard let speech = self?.speech else { return }
            if speech.state == .paused { speech.resume(from: "media key") } else { speech.pause(from: "media key") }
        }
        add(commands.playCommand) { [weak self] in self?.speech.resume(from: "media play") }
        add(commands.pauseCommand) { [weak self] in self?.speech.pause(from: "media pause") }
        add(commands.stopCommand) { [weak self] in self?.speech.stop() }
    }

    private func release() {
        guard claimed else { return }
        claimed = false
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets = []
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private func add(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
        command.isEnabled = true
        let target = command.addTarget { _ in
            DispatchQueue.main.async(execute: action)
            return .success
        }
        targets.append((command, target))
    }
}
