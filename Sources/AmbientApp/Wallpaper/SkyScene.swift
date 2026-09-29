import AmbientCore
import SwiftUI

/// Every session is a star. Finished turns gather into a constellation across the sky; the Milky Way comes out at night.
struct SkyScene: SceneRenderer {
    /// Three staggered columns, so labels (which run right, or left in the last column) don't collide.
    /// Best spots first: new sessions take the first free one.
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.61, y: 0.42), CGPoint(x: 0.36, y: 0.48), CGPoint(x: 0.89, y: 0.48), CGPoint(x: 0.57, y: 0.54),
        CGPoint(x: 0.32, y: 0.36), CGPoint(x: 0.92, y: 0.36), CGPoint(x: 0.58, y: 0.30), CGPoint(x: 0.33, y: 0.60),
        CGPoint(x: 0.60, y: 0.66), CGPoint(x: 0.91, y: 0.60), CGPoint(x: 0.37, y: 0.70), CGPoint(x: 0.88, y: 0.24),
    ]
    /// Clear of the lock screen's clock (top center) and password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.44, y: 0.44), CGPoint(x: 0.16, y: 0.48), CGPoint(x: 0.92, y: 0.50), CGPoint(x: 0.41, y: 0.56),
        CGPoint(x: 0.12, y: 0.36), CGPoint(x: 0.88, y: 0.38), CGPoint(x: 0.40, y: 0.32), CGPoint(x: 0.13, y: 0.60),
        CGPoint(x: 0.43, y: 0.68), CGPoint(x: 0.89, y: 0.62), CGPoint(x: 0.15, y: 0.72), CGPoint(x: 0.91, y: 0.74),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    /// The clock and the labels sit on sky; the story and timeline sit on the hills, which stay dark.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool {
        region != .footer && light.darkInk
    }

    private struct Look {
        let top, middle, horizon, glow, hills, near: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#03050F"), middle: RGB(hex: "#0B1030"), horizon: RGB(hex: "#1A1E48"),
                 glow: RGB(hex: "#2A2F6A"), hills: RGB(hex: "#0A0B1C"), near: RGB(hex: "#05060F"))
        case .dawn:
            Look(top: RGB(hex: "#1D2352"), middle: RGB(hex: "#5B4A7E"), horizon: RGB(hex: "#E7A88A"),
                 glow: RGB(hex: "#F4C29B"), hills: RGB(hex: "#2A2748"), near: RGB(hex: "#15142A"))
        case .day:
            Look(top: RGB(hex: "#2F6FC8"), middle: RGB(hex: "#5C9BE3"), horizon: RGB(hex: "#B8DDF7"),
                 glow: RGB(hex: "#FFFFFF"), hills: RGB(hex: "#4A6E8F"), near: RGB(hex: "#2F4B63"))
        case .dusk:
            Look(top: RGB(hex: "#060A1D"), middle: RGB(hex: "#46336A"), horizon: RGB(hex: "#EEA56F"),
                 glow: RGB(hex: "#C06F5D"), hills: RGB(hex: "#161634"), near: RGB(hex: "#0A0A1A"))
        }
    }

    /// How much of the night sky shows: all of it at night, some at dusk and dawn, none by day.
    private static func starlight(_ phase: DayPhase) -> Double {
        switch phase {
        case .night: 1
        case .dusk: 0.55
        case .dawn: 0.3
        case .day: 0
        }
    }

    // MARK: - Scenery

    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState) {
        let light = state.light
        let u = size.height / 1000
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.45, mix(\.middle)), (0.82, mix(\.horizon)), (1, mix(\.horizon))])
        ctx.fillGlow(at: CGPoint(x: size.width * 0.3, y: size.height * 0.84), radius: 520 * u,
                     color: mix(\.glow).opacity(0.35))

        let stars = light.amount(Self.starlight)
        let night = light.amount { $0 == .night ? 1 : 0 }
        if night > 0.01 { milkyWay(&ctx, size: size, strength: night) }
        if stars > 0.01 {
            var rng = SceneRandom(seed: 7)
            for _ in 0..<180 {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.72)
                let radius = CGFloat(0.5 + rng.next() * 1.1) * max(u, 0.6)
                let brightness = 0.45 + rng.next() * 0.4
                ctx.fillCircle(at: p, radius: radius, color: .white.opacity(stars * brightness))
            }
        }

        // The day's constellation, but for the newest star, which the life layer draws as it arrives.
        let marks = Array(state.marks.dropLast())
        if !marks.isEmpty {
            let visibility = max(0.4, stars)
            let points = marks.indices.map { Self.markPoint($0, size: size) } + [Self.markPoint(marks.count, size: size)]
            var line = Path()
            line.addLines(points)
            ctx.stroke(line, with: .color(.white.opacity(0.16 * visibility)), lineWidth: max(0.6, 1.2 * u))
            for (mark, p) in zip(marks, points) {
                ctx.fillCircle(at: p, radius: 3 * max(u, 0.5), color: Self.markColor(mark).opacity(0.75 * visibility))
            }
        }

        ctx.fill(hills(size, far: true), with: .color(mix(\.hills)))
        ctx.fill(hills(size, far: false), with: .color(mix(\.near)))
    }

    private func milkyWay(_ ctx: inout GraphicsContext, size: CGSize, strength: Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: size.height * 0.04))
            var rng = SceneRandom(seed: 42)
            for i in 0..<14 {
                let f = Double(i) / 13
                let x = size.width * CGFloat(0.15 + 0.8 * f)
                let y = size.height * CGFloat(0.6 - 0.5 * f + (rng.next() - 0.5) * 0.06)
                let w = size.width * CGFloat(0.10 + rng.next() * 0.08)
                let h = size.height * CGFloat(0.05 + rng.next() * 0.04)
                layer.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)),
                           with: .color(Color(red: 0.75, green: 0.78, blue: 1).opacity(0.10 * strength)))
            }
        }
    }

    /// Where the day's `index`th finished turn sits: along an arc across the top of the sky, above the
    /// inhabitants and right of the clock, oldest first. It grows across the sky as the day goes on.
    private static func markPoint(_ index: Int, size: CGSize) -> CGPoint {
        var rng = SceneRandom(seed: UInt64(index) &+ 99)
        let f = Double(index) / Double(DayLog.maxMarks - 1)
        return CGPoint(x: size.width * CGFloat(0.30 + 0.65 * f),
                       y: size.height * CGFloat(0.24 - 0.18 * f + (rng.next() - 0.5) * 0.05))
    }

    private static func markColor(_ mark: DayMark) -> Color {
        (mark.outcome == .failed ? Palette.error : Palette.agent(mark.agent)).color
    }

    private func hills(_ size: CGSize, far: Bool) -> Path {
        let w = size.width, h = size.height
        var p = Path()
        if far {
            p.move(to: CGPoint(x: 0, y: h * 0.80))
            p.addCurve(to: CGPoint(x: w * 0.375, y: h * 0.76), control1: CGPoint(x: w * 0.14, y: h * 0.745),
                       control2: CGPoint(x: w * 0.25, y: h * 0.78))
            p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.745), control1: CGPoint(x: w * 0.5, y: h * 0.74),
                       control2: CGPoint(x: w * 0.6, y: h * 0.705))
            p.addCurve(to: CGPoint(x: w, y: h * 0.74), control1: CGPoint(x: w * 0.85, y: h * 0.785),
                       control2: CGPoint(x: w * 0.93, y: h * 0.79))
        } else {
            p.move(to: CGPoint(x: 0, y: h * 0.87))
            p.addCurve(to: CGPoint(x: w * 0.45, y: h * 0.84), control1: CGPoint(x: w * 0.16, y: h * 0.83),
                       control2: CGPoint(x: w * 0.3, y: h * 0.86))
            p.addCurve(to: CGPoint(x: w, y: h * 0.855), control1: CGPoint(x: w * 0.65, y: h * 0.81),
                       control2: CGPoint(x: w * 0.85, y: h * 0.875))
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }

    // MARK: - Life

    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let u = size.height / 1000
        let stars = state.light.amount(Self.starlight)
        if stars > 0.01, !motion.still { twinkles(&ctx, size: size, strength: stars, u: u, date: date) }
        newestMark(&ctx, size: size, state: state, date: date, visibility: max(0.4, stars), u: u)
        for inhabitant in state.inhabitants {
            star(&ctx, inhabitant, at: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, date: date, motion: motion)
        }
    }

    /// A few stars that twinkle over the still ones.
    private func twinkles(_ ctx: inout GraphicsContext, size: CGSize, strength: Double, u: CGFloat, date: Date) {
        let t = date.timeIntervalSinceReferenceDate
        var rng = SceneRandom(seed: 13)
        for _ in 0..<28 {
            let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.62)
            let speed = 0.4 + rng.next(), offset = rng.next() * 6.3
            let twinkle = 0.5 + 0.5 * sin(t * speed + offset)
            ctx.fillCircle(at: p, radius: 1.3 * max(u, 0.6), color: .white.opacity(strength * twinkle * 0.9))
        }
    }

    /// The newest star of the constellation: it streaks in when a turn finishes, then holds its place.
    private func newestMark(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date,
                            visibility: Double, u: CGFloat) {
        guard let last = state.marks.last else { return }
        let p = Self.markPoint(state.marks.count - 1, size: size)
        ctx.fillCircle(at: p, radius: 3 * max(u, 0.5), color: Self.markColor(last).opacity(0.75 * visibility))
        guard let f = arrivalProgress(of: state.marks, at: date) else { return }
        let left = CGFloat(1 - f)
        let head = CGPoint(x: p.x + 220 * u * left, y: p.y + 140 * u * left)
        var streak = Path()
        streak.move(to: head)
        streak.addLine(to: CGPoint(x: head.x + 60 * u, y: head.y + 38 * u))
        ctx.stroke(streak, with: .color(.white.opacity(0.8 * (1 - f))), lineWidth: 2 * u)
        ctx.fillCircle(at: head, radius: 3 * u, color: .white.opacity(1 - f / 2))
    }

    private func star(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at p: CGPoint, u: CGFloat,
                      date: Date, motion: SceneMotion) {
        let body = Palette.agent(inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        ctx.fillGlow(at: p, radius: CGFloat(80 + 40 * inhabitant.busyness) * u,
                     color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level))
        ctx.fillCircle(at: p, radius: 7 * u, color: .white.opacity(inhabitant.mood == .idle ? 0.5 : 0.95))
        ctx.fillCircle(at: p, radius: 3.5 * u, color: body)
        guard inhabitant.mood == .working else { return }
        // Sparks circle a working star, more as its turn does more.
        let sparks = 1 + Int(inhabitant.busyness * 4)
        let turn = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate * 1.4
        for k in 0..<sparks {
            let angle = turn + Double(k) * 2 * .pi / Double(sparks)
            let spark = CGPoint(x: p.x + CGFloat(cos(angle)) * 26 * u, y: p.y + CGFloat(sin(angle)) * 26 * u)
            ctx.fillCircle(at: spark, radius: 2.2 * u, color: body.opacity(0.9))
        }
    }
}
