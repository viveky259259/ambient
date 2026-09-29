import AmbientCore
import SwiftUI

/// Every session is a boat, and its spot is the lantern at the top of its mast. Working boats sail with a wake,
/// one that needs you swings an amber lantern, and finished turns moor along the pier. A lighthouse sweeps the
/// water at night.
struct HarborScene: SceneRenderer {
    /// Two columns of lanterns on the water, below the bright horizon and clear of the pier; best spots first.
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.47, y: 0.67), CGPoint(x: 0.14, y: 0.71), CGPoint(x: 0.45, y: 0.81), CGPoint(x: 0.12, y: 0.64),
        CGPoint(x: 0.48, y: 0.74), CGPoint(x: 0.13, y: 0.78), CGPoint(x: 0.16, y: 0.85), CGPoint(x: 0.62, y: 0.60),
        CGPoint(x: 0.80, y: 0.76), CGPoint(x: 0.30, y: 0.60), CGPoint(x: 0.88, y: 0.66), CGPoint(x: 0.66, y: 0.86),
    ]
    /// Clear of the lock screen's password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.46, y: 0.67), CGPoint(x: 0.12, y: 0.71), CGPoint(x: 0.88, y: 0.76), CGPoint(x: 0.44, y: 0.60),
        CGPoint(x: 0.14, y: 0.64), CGPoint(x: 0.90, y: 0.85), CGPoint(x: 0.10, y: 0.78), CGPoint(x: 0.12, y: 0.85),
        CGPoint(x: 0.66, y: 0.62), CGPoint(x: 0.30, y: 0.60), CGPoint(x: 0.86, y: 0.66), CGPoint(x: 0.70, y: 0.88),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    /// The clock sits on sky; the labels, story and timeline sit on the water, which stays dark enough for light text.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool {
        region == .header && light.darkInk
    }

    private struct Look {
        let top, middle, horizon, seaTop, seaBottom, sun, shore: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#03050F"), middle: RGB(hex: "#0C1330"), horizon: RGB(hex: "#1C2350"),
                 seaTop: RGB(hex: "#141A38"), seaBottom: RGB(hex: "#05070F"), sun: RGB(hex: "#C8D2FF"), shore: RGB(hex: "#0B0C1C"))
        case .dawn:
            Look(top: RGB(hex: "#25306A"), middle: RGB(hex: "#6B5A8C"), horizon: RGB(hex: "#F0B48E"),
                 seaTop: RGB(hex: "#6B5F86"), seaBottom: RGB(hex: "#1A1C36"), sun: RGB(hex: "#FFD9A8"), shore: RGB(hex: "#2A2745"))
        case .day:
            Look(top: RGB(hex: "#3A7FD6"), middle: RGB(hex: "#6AAAE8"), horizon: RGB(hex: "#C2E3F8"),
                 seaTop: RGB(hex: "#3F86C4"), seaBottom: RGB(hex: "#1D4E7A"), sun: RGB(hex: "#FFF4D6"), shore: RGB(hex: "#3F6A55"))
        case .dusk:
            Look(top: RGB(hex: "#0C1230"), middle: RGB(hex: "#2A2A5C"), horizon: RGB(hex: "#F19A60"),
                 seaTop: RGB(hex: "#4A3558"), seaBottom: RGB(hex: "#080A17"), sun: RGB(hex: "#FFD39A"), shore: RGB(hex: "#231A36"))
        }
    }

    /// A dark silhouette by day; at dusk, dawn and night it catches a little of the horizon's light so it shows on dark water.
    private static func hull(_ light: DayLight) -> Color {
        let shore = light.color { look($0).shore }.mixed(with: RGB(r: 0, g: 0, b: 0), 0.45)
        let horizon = light.color { look($0).horizon }
        return shore.mixed(with: horizon, light.amount { $0 == .day ? 0 : 0.35 }).color
    }

    /// Where the day's `index`th finished turn is moored: two rows of twenty along the pier, oldest first.
    private static func mooring(_ index: Int, size: CGSize) -> CGPoint {
        let row = index / 20, column = index % 20
        return CGPoint(x: size.width * CGFloat(0.735 + Double(column) * 0.0135),
                       y: size.height * CGFloat(row == 0 ? 0.69 : 0.645))
    }

    private static func lamp(_ size: CGSize, u: CGFloat) -> CGPoint {
        CGPoint(x: size.width * 0.05, y: size.height * 0.585 - 38 * u)
    }

    // MARK: - Scenery

    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState) {
        let light = state.light
        let u = size.height / 1000
        let w = size.width, h = size.height
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.3, mix(\.middle)), (0.6, mix(\.horizon)), (1, mix(\.horizon))])

        // The sun low at dawn and dusk and high by day, clear of the clock; the moon at night.
        let sun = CGPoint(x: w * CGFloat(light.amount { $0 == .night ? 0.78 : ($0 == .day ? 0.70 : 0.29) }),
                          y: h * CGFloat(light.amount { $0 == .day ? 0.16 : ($0 == .night ? 0.16 : 0.6) }))
        let sunRadius = CGFloat(light.amount { $0 == .night ? 22 : ($0 == .day ? 38 : 60) }) * u
        ctx.fillGlow(at: sun, radius: sunRadius * 4, color: mix(\.sun).opacity(light.amount { $0 == .day ? 0.35 : 0.8 }))
        ctx.fillCircle(at: sun, radius: sunRadius, color: mix(\.sun))

        // The sea hides the lower half of a setting sun.
        ctx.fillVertical(CGRect(x: 0, y: h * 0.6, width: w, height: h * 0.4),
                         [(0, mix(\.seaTop)), (0.35, mix(\.seaBottom)), (1, mix(\.seaBottom))])
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 18 * u))
            layer.fill(Path(ellipseIn: CGRect(x: sun.x - 36 * u, y: h * 0.6, width: 72 * u, height: h * 0.22)),
                       with: .color(mix(\.sun).opacity(0.25)))
        }

        var shore = Path()
        shore.move(to: CGPoint(x: 0, y: h * 0.6))
        shore.addCurve(to: CGPoint(x: w * 0.19, y: h * 0.6), control1: CGPoint(x: w * 0.06, y: h * 0.583),
                       control2: CGPoint(x: w * 0.13, y: h * 0.59))
        shore.closeSubpath()
        shore.move(to: CGPoint(x: w * 0.74, y: h * 0.6))
        shore.addCurve(to: CGPoint(x: w, y: h * 0.585), control1: CGPoint(x: w * 0.82, y: h * 0.57),
                       control2: CGPoint(x: w * 0.92, y: h * 0.572))
        shore.addLine(to: CGPoint(x: w, y: h * 0.6))
        shore.closeSubpath()
        ctx.fill(shore, with: .color(mix(\.shore)))

        // The lighthouse; its beam is life.
        let lamp = Self.lamp(size, u: u)
        ctx.fill(Path(CGRect(x: lamp.x - 5 * u, y: lamp.y, width: 10 * u, height: 38 * u)), with: .color(mix(\.shore)))

        // Boats moored today, but for the newest, which the life layer brings in.
        let hull = Self.hull(light)
        for (i, mark) in state.marks.dropLast().enumerated() {
            moored(&ctx, mark, at: Self.mooring(i, size: size), u: u, hull: hull)
        }

        ctx.fill(Path(CGRect(x: w * 0.72, y: h * 0.66, width: w * 0.28, height: 10 * u)), with: .color(mix(\.shore)))
        for k in 0..<5 {
            let x = w * CGFloat(0.73 + Double(k) * 0.065)
            ctx.fill(Path(CGRect(x: x, y: h * 0.66, width: 6 * u, height: 50 * u)), with: .color(mix(\.shore)))
        }
    }

    private func moored(_ ctx: inout GraphicsContext, _ mark: DayMark, at p: CGPoint, u: CGFloat, hull: Color) {
        ctx.fill(hullPath(deck: p, scale: 0.28 * u), with: .color(hull))
        let color = mark.outcome == .failed ? Palette.error : Palette.agent(mark.agent)
        ctx.fillCircle(at: CGPoint(x: p.x, y: p.y - 8 * u), radius: 2.5 * u, color: color.color)
    }

    private func hullPath(deck: CGPoint, scale s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: deck.x - 60 * s, y: deck.y))
        p.addLine(to: CGPoint(x: deck.x + 60 * s, y: deck.y))
        p.addLine(to: CGPoint(x: deck.x + 43 * s, y: deck.y + 26 * s))
        p.addLine(to: CGPoint(x: deck.x - 43 * s, y: deck.y + 26 * s))
        p.closeSubpath()
        return p
    }

    // MARK: - Life

    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let u = size.height / 1000
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        let hull = Self.hull(state.light)
        waves(&ctx, size: size, u: u, t: t)
        let night = state.light.amount { $0 == .night ? 1 : 0 }
        if night > 0.01 { beam(&ctx, size: size, u: u, t: t, night: night) }

        // The newest moored boat glides in to its place.
        if let last = state.marks.last {
            var p = Self.mooring(state.marks.count - 1, size: size)
            if let f = arrivalProgress(of: state.marks, at: date) { p.x -= 160 * u * CGFloat(1 - f) }
            moored(&ctx, last, at: p, u: u, hull: hull)
        }

        for inhabitant in state.inhabitants {
            boat(&ctx, inhabitant, lantern: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                 u: u, t: t, date: date, motion: motion, hull: hull)
        }
    }

    private func waves(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, t: TimeInterval) {
        var rng = SceneRandom(seed: 5)
        for _ in 0..<10 {
            let x = rng.next() * 0.9, y = 0.63 + rng.next() * 0.3, length = 0.04 + rng.next() * 0.06, phase = rng.next() * 6.3
            let drift = sin(t * 0.25 + phase) * 0.008
            var line = Path()
            line.move(to: CGPoint(x: size.width * CGFloat(x + drift), y: size.height * CGFloat(y)))
            line.addLine(to: CGPoint(x: size.width * CGFloat(x + drift + length), y: size.height * CGFloat(y)))
            ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 1.6 * u)
        }
    }

    private func beam(_ ctx: inout GraphicsContext, size: CGSize, u: CGFloat, t: TimeInterval, night: Double) {
        let lamp = Self.lamp(size, u: u)
        let beamColor = Color(red: 1, green: 0.93, blue: 0.7)
        let angle = t == 0 ? 0.25 : sin(t * 0.35) * 0.35 + 0.2
        let reach = size.width * 0.55
        var beam = Path()
        beam.move(to: lamp)
        beam.addLine(to: CGPoint(x: lamp.x + reach * CGFloat(cos(angle - 0.05)), y: lamp.y + reach * CGFloat(sin(angle - 0.05))))
        beam.addLine(to: CGPoint(x: lamp.x + reach * CGFloat(cos(angle + 0.05)), y: lamp.y + reach * CGFloat(sin(angle + 0.05))))
        beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(Gradient(colors: [beamColor.opacity(0.28 * night), beamColor.opacity(0)]),
                                             startPoint: lamp, endPoint: CGPoint(x: lamp.x + reach, y: lamp.y)))
        ctx.fillGlow(at: lamp, radius: 26 * u, color: beamColor.opacity(night))
    }

    private func boat(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, lantern spot: CGPoint, u: CGFloat,
                      t: TimeInterval, date: Date, motion: SceneMotion, hull: Color) {
        let s = 0.55 * u
        let deck = CGPoint(x: spot.x, y: spot.y + 134 * s)
        let body = Palette.agent(inhabitant.agent).color
        let glow = Palette.mood(inhabitant.mood, agent: inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)

        if inhabitant.mood == .working {
            // A wake that lengthens as the turn does more.
            let length = CGFloat(60 + 160 * inhabitant.busyness) * u
            for (k, offset) in [CGFloat(0), 12].enumerated() {
                var wake = Path()
                wake.move(to: CGPoint(x: deck.x - 60 * s, y: deck.y + (14 + offset) * s))
                wake.addLine(to: CGPoint(x: deck.x - 60 * s - length, y: deck.y + (20 + offset) * s))
                ctx.stroke(wake, with: .color(.white.opacity(k == 0 ? 0.35 : 0.2)),
                           style: StrokeStyle(lineWidth: 2 * u, dash: [10 * u, 10 * u], dashPhase: CGFloat(-t * 18)))
            }
        }
        ctx.fill(hullPath(deck: deck, scale: s), with: .color(hull))
        var stripe = Path()
        stripe.move(to: CGPoint(x: deck.x - 58 * s, y: deck.y + 3 * s))
        stripe.addLine(to: CGPoint(x: deck.x + 58 * s, y: deck.y + 3 * s))
        ctx.stroke(stripe, with: .color(body), lineWidth: 3 * s)
        var mast = Path()
        mast.move(to: deck)
        mast.addLine(to: CGPoint(x: deck.x, y: spot.y + 4 * s))
        ctx.stroke(mast, with: .color(hull), lineWidth: 3 * s)
        if inhabitant.mood == .working {
            var sail = Path()
            sail.move(to: CGPoint(x: deck.x + 4 * s, y: spot.y + 10 * s))
            sail.addLine(to: CGPoint(x: deck.x + 58 * s, y: deck.y - 6 * s))
            sail.addLine(to: CGPoint(x: deck.x + 4 * s, y: deck.y - 6 * s))
            sail.closeSubpath()
            ctx.fill(sail, with: .color(hull.opacity(0.85)))
        }

        // The lantern: swings when it needs you, fires a flare when it failed, dark when idle.
        var lamp = spot
        if inhabitant.mood == .waiting { lamp.x += CGFloat(sin(t * 2.2)) * 5 * u }
        guard inhabitant.mood != .idle else {
            ctx.fillCircle(at: lamp, radius: 3 * u, color: .white.opacity(0.35))
            return
        }
        ctx.fillGlow(at: lamp, radius: 80 * u, color: glow.opacity(level))
        ctx.fillCircle(at: lamp, radius: 4.5 * u, color: .white.opacity(0.95))
        if inhabitant.mood == .error, t != 0 {
            let rise = t.truncatingRemainder(dividingBy: 2) / 2
            let flare = CGPoint(x: lamp.x, y: lamp.y - CGFloat(rise) * 90 * u)
            ctx.fillGlow(at: flare, radius: 30 * u, color: Palette.error.color.opacity(1 - rise))
        }
    }
}
