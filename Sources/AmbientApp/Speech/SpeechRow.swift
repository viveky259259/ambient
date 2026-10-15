import SwiftUI

/// "Speaking" with a level meter, pause or continue, and stop; or why reading aloud failed.
struct SpeechRow: View {
    let state: SpeechState
    let level: Float
    let onStop: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onUseMacVoice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(failed ? Color.orange : Color.white)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            switch state {
            case .preparing, .speaking, .paused:
                LevelMeter(level: state == .speaking ? level : 0)
                SpeechControls(state: state, onStop: onStop, onPause: onPause, onResume: onResume)
            case .failed(_, let offerMacVoice) where offerMacVoice:
                Button("Use Mac voice", action: onUseMacVoice)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 40)
        .accessibilityElement(children: .contain)
    }

    private var failed: Bool {
        if case .failed = state { return true }
        return false
    }

    private var icon: String {
        if failed { return "exclamationmark.triangle.fill" }
        if case .hint = state { return "keyboard" }
        if state == .paused { return "speaker.fill" }
        return "speaker.wave.2.fill"
    }

    private var title: String {
        switch state {
        case .idle: ""
        case .preparing: "Getting ready…"
        case .speaking: "Speaking"
        case .paused: "Paused"
        case .failed(let message, _): message
        case .hint(let message): message
        }
    }
}

/// Pause or continue (once audio is playing), then stop. Shared by the island and the pet.
struct SpeechControls: View {
    let state: SpeechState
    let onStop: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if state == .speaking {
                control("pause.fill", "Pause speaking", onPause)
            } else if state == .paused {
                control("play.fill", "Continue speaking", onResume)
            }
            control("stop.fill", "Stop speaking", onStop)
        }
        .foregroundStyle(.white)
    }

    private func control(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Five bars that follow the voice's loudness.
struct LevelMeter: View {
    let level: Float

    private static let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: CGFloat(4 + 14 * min(1, level * Self.weights[i])))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
