import AmbientCore
import AppKit
import SwiftUI

/// An Ambient banner as macOS shows it, for each moment that notifies, with its chime.
struct NotificationPreview: View {
    let enabled: Bool
    let chimesOn: Bool
    let onPlay: (Mood) -> Void
    @State private var mood: Mood = .waiting

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            PreviewStage(enabled: enabled, alignment: .topTrailing) {
                BannerMock(mood: mood)
                    .padding(Theme.Space.sm)
                    .id(mood)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mood)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of an Ambient notification")
            HStack(spacing: Theme.Space.xs) {
                Picker("Moment", selection: $mood) {
                    Text("Needs you").tag(Mood.waiting)
                    Text("Done").tag(Mood.done)
                    Text("Error").tag(Mood.error)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Button { onPlay(mood) } label: { Label("Play Chime", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.pill)
            }
            .onChange(of: mood) { if chimesOn { onPlay(mood) } }
        }
    }
}

private struct BannerMock: View {
    let mood: Mood

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Claude · Terminal").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(copy.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
        .glassPanel(radius: 18)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// The same words `Notifier` posts.
    private var copy: (title: String, body: String) {
        switch mood {
        case .done: ("api-server is done", "All 42 tests pass. Ready for review.")
        case .error: ("api-server stopped with an error", "Rate limited — retry in 2 minutes")
        default: ("api-server needs your permission", "Bash: rm -rf build")
        }
    }
}
