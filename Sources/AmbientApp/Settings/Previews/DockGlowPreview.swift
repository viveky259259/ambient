import AmbientCore
import AppKit
import SwiftUI

/// A small Dock that glows like the real one: the state's color, breathing at its pace,
/// scaled by the intensity slider.
struct DockGlowPreview: View {
    let enabled: Bool
    let intensity: Double
    @State private var mood: Mood = .working
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            PreviewStage(enabled: enabled, alignment: .bottom) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !enabled)) { context in
                    ZStack(alignment: .bottom) {
                        glow(at: context.date)
                        MiniDock().padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the Dock glow")
            Picker("State", selection: $mood) {
                Text("Working").tag(Mood.working)
                Text("Needs you").tag(Mood.waiting)
                Text("Done").tag(Mood.done)
                Text("Error").tag(Mood.error)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
        }
    }

    @ViewBuilder private func glow(at date: Date) -> some View {
        if let style = GlowStyle.for(mood: mood, agent: .claude) {
            Ellipse()
                .fill(style.color.color)
                .frame(width: 330, height: 70)
                .blur(radius: 24)
                .opacity(level(style, at: date) * intensity)
                .offset(y: 30)
        }
    }

    /// Where the breath is: between the style's low and high, or steady.
    private func level(_ style: GlowStyle, at date: Date) -> Double {
        guard let period = style.period, !reduceMotion else { return (style.low + style.high) / 2 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return style.low + (style.high - style.low) * (0.5 - 0.5 * cos(phase * 2 * .pi))
    }
}

/// A Dock with a few familiar-looking tiles and Ambient at the end.
private struct MiniDock: View {
    private static let symbols = ["folder.fill", "safari.fill", "terminal.fill", "message.fill", "music.note", "gearshape.fill"]
    private static let colors: [Color] = [.blue, .cyan, .black, .green, .pink, .gray]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Self.symbols.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Self.colors[i].gradient)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: Self.symbols[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white))
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassPanel(radius: 16)
    }
}
