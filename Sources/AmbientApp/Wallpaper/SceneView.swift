import AmbientCore
import SwiftUI

/// A living wallpaper: one world, its inhabitants, and the text set into it.
struct SceneView: View {
    let state: SceneState
    /// False on displays other than the main one, and for thumbnails.
    var showsText = true
    /// False draws one still frame: while covered, in Low Power Mode, for thumbnails and for the lock-screen fallback image.
    var animated = true
    var reduceMotion = false

    var body: some View {
        let renderer = SceneRenderers.renderer(for: state.kind)
        if animated {
            TimelineView(.animation(minimumInterval: Self.frameInterval(state), paused: false)) { context in
                frame(renderer, date: context.date, motion: SceneMotion(reduce: reduceMotion, still: false))
            }
        } else {
            frame(renderer, date: state.now, motion: SceneMotion(reduce: reduceMotion, still: true))
        }
    }

    /// 30 frames a second while something moves; about one a second when everything rests.
    static func frameInterval(_ state: SceneState) -> Double {
        let moving = state.inhabitants.contains { $0.mood != .idle } || arrivalProgress(of: state.marks, at: Date()) != nil
        return moving ? 1.0 / 30 : 1
    }

    private func frame(_ renderer: any SceneRenderer, date: Date, motion: SceneMotion) -> some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    renderer.draw(&ctx, size: size, state: state, date: date, motion: motion)
                }
                if showsText {
                    SceneTextLayer(state: state, renderer: renderer, size: geo.size)
                }
            }
        }
    }
}

/// The words set into a scene: the clock and your day top-left, a label beside each inhabitant,
/// the day's story bottom-left and the latest moments bottom-right. Sizes follow the display.
struct SceneTextLayer: View {
    let state: SceneState
    let renderer: any SceneRenderer
    let size: CGSize

    /// 1 on a display 1000 points tall.
    private var u: CGFloat { min(1.6, size.height / 1000) }

    private func dark(_ region: SceneTextRegion) -> Bool { renderer.darkInk(region, light: state.light) }
    private func ink(_ region: SceneTextRegion) -> Color { dark(region) ? Color(white: 0.1) : .white }
    private func halo(_ region: SceneTextRegion) -> Color { dark(region) ? .white.opacity(0.45) : .black.opacity(0.5) }

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                header
                    .padding(.leading, size.width * 0.06)
                    .padding(.top, size.height * 0.10)
                    .foregroundStyle(ink(.header))
                    .shadow(color: halo(.header), radius: 6 * u)
            }
            .overlay(alignment: .bottomLeading) {
                story
                    .padding(.leading, size.width * 0.06)
                    .padding(.bottom, size.height * 0.05)
                    .foregroundStyle(ink(.footer))
                    .shadow(color: halo(.footer), radius: 6 * u)
            }
            .overlay(alignment: .bottomTrailing) {
                timeline
                    .padding(.trailing, size.width * 0.04)
                    .padding(.bottom, size.height * 0.045)
                    .foregroundStyle(ink(.footer))
                    .shadow(color: halo(.footer), radius: 6 * u)
            }
            .overlay {
                labels
                    .foregroundStyle(ink(.labels))
                    .shadow(color: halo(.labels), radius: 6 * u)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            if let clock = state.clock {
                Text(clock).font(.system(size: 54 * u, weight: .ultraLight)).monospacedDigit()
            }
            if let date = state.date {
                Text(date).font(.system(size: 14 * u)).opacity(0.85)
            }
            if let next = state.nextEvent {
                HStack(spacing: 6 * u) {
                    RoundedRectangle(cornerRadius: 2 * u)
                        .fill(Color(red: 1, green: 0.42, blue: 0.42))
                        .frame(width: 8 * u, height: 8 * u)
                    Text(next)
                }
                .font(.system(size: 12.5 * u))
                .opacity(0.85)
                .padding(.top, 4 * u)
            }
        }
    }

    private var labels: some View {
        ZStack {
            ForEach(state.inhabitants) { inhabitant in
                let spot = renderer.spot(inhabitant.slot, surface: state.surface)
                // Near the right edge, the label sits to the left of its inhabitant.
                let flipped = spot.x > 0.72
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: flipped ? .trailing : .leading) {
                        label(inhabitant, flipped: flipped)
                            .fixedSize()
                            .padding(flipped ? .trailing : .leading, 22 * u)
                    }
                    .position(x: spot.x * size.width, y: spot.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func label(_ inhabitant: SceneInhabitant, flipped: Bool) -> some View {
        VStack(alignment: flipped ? .trailing : .leading, spacing: 2 * u) {
            Text(inhabitant.headline)
                .font(.system(size: 12.5 * u, weight: .semibold))
                .foregroundStyle(inhabitant.mood == .waiting ? waitingInk : ink(.labels))
            Text(inhabitant.place).font(.system(size: 12 * u)).opacity(0.75)
            if let detail = inhabitant.detail {
                Text(detail).font(.system(size: 11 * u, design: .monospaced)).opacity(0.6)
            }
        }
        .multilineTextAlignment(flipped ? .trailing : .leading)
    }

    /// "Today   3h 40m of agent time  ·  612 tools  ·  …", numbers in semibold.
    /// Needs-you amber, deepened where the ink is dark so it reads on bright sky.
    private var waitingInk: Color { dark(.labels) ? Color(red: 0.62, green: 0.36, blue: 0) : Palette.waiting.color }

    private var story: some View {
        HStack(spacing: 0) {
            if state.story.isEmpty {
                Text("A quiet day so far")
            } else {
                Text("Today   ")
                ForEach(Array(state.story.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Text("  ·  ") }
                    Text(item.value).fontWeight(.semibold)
                    Text(" " + item.label)
                }
            }
            if state.overflow > 0 {
                Text("   ·   +\(state.overflow) more " + (state.overflow == 1 ? "session" : "sessions") + " now")
            }
        }
        .font(.system(size: 12 * u))
        .opacity(0.85)
        .fixedSize()
    }

    private var timeline: some View {
        VStack(alignment: .trailing, spacing: 3 * u) {
            ForEach(Array(state.timeline.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8 * u) {
                    Text(line.time).font(.system(size: 10.5 * u, design: .monospaced)).opacity(0.75)
                    Text(line.text).font(.system(size: 10.5 * u))
                }
            }
        }
        .opacity(0.65)
    }
}
