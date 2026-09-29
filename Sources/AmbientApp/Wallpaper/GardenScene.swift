import AmbientCore
import SwiftUI

/// Every session is a plant, and its spot is the plant's head. A working plant grows taller as its turn does more;
/// one that needs you holds up a glowing bud, a finished one blooms, a failed one droops. Finished turns leave
/// small flowers in the bed. Fireflies come out at night.
struct GardenScene: SceneRenderer {
    /// Three staggered columns, best spots first.
    private static let deskSpots: [CGPoint] = [
        CGPoint(x: 0.58, y: 0.50), CGPoint(x: 0.26, y: 0.54), CGPoint(x: 0.88, y: 0.56), CGPoint(x: 0.56, y: 0.62),
        CGPoint(x: 0.28, y: 0.66), CGPoint(x: 0.86, y: 0.68), CGPoint(x: 0.60, y: 0.74), CGPoint(x: 0.24, y: 0.42),
        CGPoint(x: 0.74, y: 0.44), CGPoint(x: 0.92, y: 0.44), CGPoint(x: 0.42, y: 0.72), CGPoint(x: 0.44, y: 0.40),
    ]
    /// Clear of the lock screen's clock (top center) and password field (bottom center).
    private static let lockSpots: [CGPoint] = [
        CGPoint(x: 0.48, y: 0.52), CGPoint(x: 0.16, y: 0.46), CGPoint(x: 0.88, y: 0.46), CGPoint(x: 0.46, y: 0.40),
        CGPoint(x: 0.14, y: 0.58), CGPoint(x: 0.86, y: 0.58), CGPoint(x: 0.50, y: 0.64), CGPoint(x: 0.18, y: 0.70),
        CGPoint(x: 0.30, y: 0.36), CGPoint(x: 0.70, y: 0.36), CGPoint(x: 0.92, y: 0.70), CGPoint(x: 0.34, y: 0.62),
    ]

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let spots = surface == .desk ? Self.deskSpots : Self.lockSpots
        return spots[((slot % spots.count) + spots.count) % spots.count]
    }

    /// The clock and the labels sit on sky and hills; the story and timeline sit on the dark ground.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool {
        region != .footer && light.darkInk
    }

    private struct Look {
        let top, middle, horizon, hills, groundTop, groundBottom: RGB
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night:
            Look(top: RGB(hex: "#050817"), middle: RGB(hex: "#10163A"), horizon: RGB(hex: "#1C2250"),
                 hills: RGB(hex: "#14142C"), groundTop: RGB(hex: "#0D1614"), groundBottom: RGB(hex: "#050807"))
        case .dawn:
            Look(top: RGB(hex: "#2A2F5E"), middle: RGB(hex: "#7A5C88"), horizon: RGB(hex: "#EAB18C"),
                 hills: RGB(hex: "#3A3358"), groundTop: RGB(hex: "#24302C"), groundBottom: RGB(hex: "#0E1512"))
        case .day:
            Look(top: RGB(hex: "#4E97E0"), middle: RGB(hex: "#86C0EE"), horizon: RGB(hex: "#CFEAF8"),
                 hills: RGB(hex: "#5F8A6A"), groundTop: RGB(hex: "#3D6B43"), groundBottom: RGB(hex: "#1F3A24"))
        case .dusk:
            Look(top: RGB(hex: "#0D1331"), middle: RGB(hex: "#352D62"), horizon: RGB(hex: "#F0AE78"),
                 hills: RGB(hex: "#2A2446"), groundTop: RGB(hex: "#1B2A2A"), groundBottom: RGB(hex: "#070D0C"))
        }
    }

    private static func fireflies(_ phase: DayPhase) -> Double {
        switch phase {
        case .night: 1
        case .dusk: 0.6
        case .dawn: 0.1
        case .day: 0
        }
    }

    /// Where the day's `index`th finished turn blooms: two rows of twenty in the bed, oldest first.
    private static func bedPoint(_ index: Int, size: CGSize) -> CGPoint {
        let row = index / 20, column = index % 20
        return CGPoint(x: size.width * CGFloat(0.10 + Double(column) * 0.016 + Double(row) * 0.008),
                       y: size.height * CGFloat(0.885 + Double(row) * 0.022))
    }

    // MARK: - Scenery

    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState) {
        let light = state.light
        let u = size.height / 1000
        let w = size.width, h = size.height
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }

        ctx.fillVertical(CGRect(origin: .zero, size: size),
                         [(0, mix(\.top)), (0.34, mix(\.middle)), (0.6, mix(\.horizon)), (1, mix(\.horizon))])

        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: h * 0.61))
        hills.addCurve(to: CGPoint(x: w * 0.40, y: h * 0.57), control1: CGPoint(x: w * 0.12, y: h * 0.56),
                       control2: CGPoint(x: w * 0.26, y: h * 0.59))
        hills.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.575), control1: CGPoint(x: w * 0.55, y: h * 0.55),
                       control2: CGPoint(x: w * 0.66, y: h * 0.54))
        hills.addCurve(to: CGPoint(x: w, y: h * 0.57), control1: CGPoint(x: w * 0.88, y: h * 0.60),
                       control2: CGPoint(x: w * 0.95, y: h * 0.59))
        hills.addLine(to: CGPoint(x: w, y: h))
        hills.addLine(to: CGPoint(x: 0, y: h))
        hills.closeSubpath()
        ctx.fill(hills, with: .color(mix(\.hills)))

        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.66))
        ground.addCurve(to: CGPoint(x: w, y: h * 0.65), control1: CGPoint(x: w * 0.3, y: h * 0.64),
                        control2: CGPoint(x: w * 0.7, y: h * 0.655))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        ctx.fill(ground, with: .linearGradient(Gradient(colors: [mix(\.groundTop), mix(\.groundBottom)]),
                                               startPoint: CGPoint(x: 0, y: h * 0.65), endPoint: CGPoint(x: 0, y: h)))

        var rng = SceneRandom(seed: 3)
        for _ in 0..<60 {
            let x = w * CGFloat(rng.next())
            let base = h * CGFloat(0.93 + rng.next() * 0.07)
            let height = CGFloat(30 + rng.next() * 40) * u
            let lean = CGFloat(rng.next() - 0.5) * 20 * u
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: base))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: base - height), control: CGPoint(x: x + lean / 3, y: base - height / 2))
            ctx.stroke(blade, with: .color(mix(\.groundBottom)), style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round))
        }

        // Flowers from today's turns, but for the newest, which the life layer opens.
        for (i, mark) in state.marks.dropLast().enumerated() {
            flower(&ctx, mark, at: Self.bedPoint(i, size: size), u: u, grow: 1)
        }
    }

    private func flower(_ ctx: inout GraphicsContext, _ mark: DayMark, at p: CGPoint, u: CGFloat, grow: CGFloat) {
        let r = 5 * max(u, 0.5) * grow
        if mark.outcome == .failed {
            ctx.fillCircle(at: CGPoint(x: p.x, y: p.y + 2 * u), radius: r * 0.8, color: Palette.error.color.opacity(0.7))
        } else {
            ctx.fillCircle(at: p, radius: r, color: Palette.agent(mark.agent).color)
            ctx.fillCircle(at: p, radius: r * 0.4, color: Color(red: 1, green: 0.91, blue: 0.66))
        }
    }

    // MARK: - Life

    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let u = size.height / 1000
        if let last = state.marks.last {
            let grow = arrivalProgress(of: state.marks, at: date).map { CGFloat($0) } ?? 1
            flower(&ctx, last, at: Self.bedPoint(state.marks.count - 1, size: size), u: u, grow: grow)
        }
        for inhabitant in state.inhabitants {
            plant(&ctx, inhabitant, head: scenePoint(spot(inhabitant.slot, surface: state.surface), in: size),
                  size: size, u: u, date: date, motion: motion)
        }
        let glow = state.light.amount(Self.fireflies)
        if glow > 0.01 { fireflies(&ctx, size: size, amount: glow, u: u, date: date, motion: motion) }
    }

    private func plant(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, head spot: CGPoint, size: CGSize,
                       u: CGFloat, date: Date, motion: SceneMotion) {
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        let body = Palette.agent(inhabitant.agent).color
        let glow = Palette.mood(inhabitant.mood, agent: inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        let stemColor = Color(red: 0.07, green: 0.19, blue: 0.16)

        // A working plant grows toward its spot as its turn does more.
        let growth = inhabitant.mood == .working ? CGFloat(1 - inhabitant.busyness) * 0.08 : 0
        var head = CGPoint(x: spot.x, y: spot.y + size.height * growth)
        head.x += CGFloat(sin(t * 0.8 + Double(inhabitant.slot))) * 3 * u
        let base = CGPoint(x: spot.x + 8 * u, y: size.height * 1.02)
        let rise = base.y - head.y
        let droops = inhabitant.mood == .error
        let tip = droops ? CGPoint(x: head.x + 18 * u, y: head.y + 22 * u) : head

        var stem = Path()
        stem.move(to: base)
        stem.addCurve(to: tip, control1: CGPoint(x: base.x - 10 * u, y: base.y - rise * 0.4),
                      control2: droops ? CGPoint(x: head.x - 6 * u, y: head.y - 26 * u)
                                       : CGPoint(x: head.x + 6 * u, y: head.y + rise * 0.3))
        ctx.stroke(stem, with: .color(stemColor), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
        leaf(&ctx, at: CGPoint(x: base.x - 4 * u, y: base.y - rise * 0.45), side: 1, u: u, color: stemColor)
        leaf(&ctx, at: CGPoint(x: base.x - 6 * u, y: base.y - rise * 0.7), side: -1, u: u, color: stemColor)

        switch inhabitant.mood {
        case .idle:
            ctx.fillCircle(at: tip, radius: 6 * u, color: body.opacity(0.45))
        case .working:
            ctx.fillGlow(at: tip, radius: CGFloat(60 + 30 * inhabitant.busyness) * u, color: glow.opacity(level))
            ctx.fillCircle(at: tip, radius: 6 * u, color: .white.opacity(0.9))
            ctx.fillCircle(at: tip, radius: 3 * u, color: body)
        case .waiting:
            ctx.fillGlow(at: tip, radius: 95 * u, color: glow.opacity(level))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 12 * u, y: tip.y - 18 * u, width: 24 * u, height: 36 * u)), with: .color(body))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 6 * u, y: tip.y - 14 * u, width: 12 * u, height: 20 * u)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.64).opacity(0.8)))
        case .done:
            ctx.fillGlow(at: tip, radius: 75 * u, color: glow.opacity(level))
            for k in 0..<5 {
                let angle = Double(k) * 2 * .pi / 5 - .pi / 2
                ctx.fillCircle(at: CGPoint(x: tip.x + CGFloat(cos(angle)) * 16 * u, y: tip.y + CGFloat(sin(angle)) * 16 * u),
                               radius: 11 * u, color: body)
            }
            ctx.fillCircle(at: tip, radius: 7 * u, color: Color(red: 1, green: 0.91, blue: 0.66))
        case .error:
            ctx.fillGlow(at: tip, radius: 60 * u, color: glow.opacity(level))
            ctx.fillCircle(at: tip, radius: 8 * u, color: body.opacity(0.8))
        }
    }

    private func leaf(_ ctx: inout GraphicsContext, at p: CGPoint, side: CGFloat, u: CGFloat, color: Color) {
        var leaf = Path()
        leaf.move(to: p)
        leaf.addQuadCurve(to: CGPoint(x: p.x + side * 44 * u, y: p.y - 36 * u), control: CGPoint(x: p.x + side * 38 * u, y: p.y - 6 * u))
        leaf.addQuadCurve(to: p, control: CGPoint(x: p.x + side * 10 * u, y: p.y - 34 * u))
        ctx.fill(leaf, with: .color(color.opacity(0.9)))
    }

    private func fireflies(_ ctx: inout GraphicsContext, size: CGSize, amount: Double, u: CGFloat, date: Date, motion: SceneMotion) {
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        let warm = Color(red: 1, green: 0.91, blue: 0.54)
        var rng = SceneRandom(seed: 11)
        for _ in 0..<16 {
            let x = rng.next(), y = 0.62 + rng.next() * 0.3, speed = 0.2 + rng.next() * 0.3, phase = rng.next() * 6.3
            let dx = CGFloat(sin(t * speed + phase)) * 18 * u
            let dy = CGFloat(cos(t * speed * 1.3 + phase)) * 14 * u
            let p = CGPoint(x: size.width * CGFloat(x) + dx, y: size.height * CGFloat(y) + dy)
            let flicker = motion.still ? 0.8 : 0.35 + 0.65 * max(0, sin(t * 1.7 + phase * 3))
            ctx.fillGlow(at: p, radius: 14 * u, color: warm.opacity(amount * flicker * 0.8))
            ctx.fillCircle(at: p, radius: 2.4 * u, color: Color(red: 1, green: 0.95, blue: 0.7).opacity(amount * flicker))
        }
    }
}
