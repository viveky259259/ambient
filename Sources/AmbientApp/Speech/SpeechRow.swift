import SwiftUI

/// "Speaking" with a level meter and a stop button, or why reading aloud failed.
struct SpeechRow: View {
    let state: SpeechState
    let level: Float
    let onStop: () -> Void
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
            case .preparing, .speaking:
                LevelMeter(level: state == .speaking ? level : 0)
                Button(action: onStop) {
                    Image(systemName: "stop.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Stop speaking")
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

    private var icon: String { failed ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill" }

    private var title: String {
        switch state {
        case .idle: ""
        case .preparing: "Getting ready…"
        case .speaking: "Speaking"
        case .failed(let message, _): message
        }
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
