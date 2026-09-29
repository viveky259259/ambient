import AmbientCore
import SwiftUI

/// Every session is a planet. While the island is closed they stand in rows across the sky, one row up to four and
/// two beyond. When it opens, the notch becomes the sun and up to six planets orbit it: that part is drawn by the
/// notch effect, which uses this world's planet.
struct SolarScene: SceneRenderer {
    var labelsBelow: Bool { true }

    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint {
        let slots = SolarLayout.rowSlots(count: SceneState.maxInhabitants(for: .solar))
        let p = slots[((slot % slots.count) + slots.count) % slots.count]
        return CGPoint(x: p.x, y: p.y)
    }

    /// Planets stand in rows in the order of their spots, so the rows stay centred however many there are.
    func spot(for inhabitant: SceneInhabitant, in state: SceneState) -> CGPoint {
        let ordered = state.inhabitants.sorted { $0.slot < $1.slot }
        let index = ordered.firstIndex { $0.id == inhabitant.id } ?? 0
        let p = SolarLayout.rowSlots(count: ordered.count)[index]
        return CGPoint(x: p.x, y: p.y)
    }

    /// No land or water here: all text sits on sky, dark by day.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool { light.darkInk }

    private struct Look {
        let top, middle, bottom: RGB
        let starlight: Double
    }

    private static func look(_ phase: DayPhase) -> Look {
        switch phase {
        case .night: Look(top: RGB(hex: "#03040C"), middle: RGB(hex: "#080C22"), bottom: RGB(hex: "#0D1230"), starlight: 1)
        case .dawn: Look(top: RGB(hex: "#1E2150"), middle: RGB(hex: "#4B3F76"), bottom: RGB(hex: "#C98C86"), starlight: 0.4)
        case .day: Look(top: RGB(hex: "#CFE0F5"), middle: RGB(hex: "#E6EEF9"), bottom: RGB(hex: "#F6F8FC"), starlight: 0)
        case .dusk: Look(top: RGB(hex: "#070A1E"), middle: RGB(hex: "#2A2A5C"), bottom: RGB(hex: "#8C4F6E"), starlight: 0.6)
        }
    }

    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState) {
        let light = state.light
        func mix(_ pick: (Look) -> RGB) -> Color { light.color { pick(Self.look($0)) }.color }
        ctx.fillVertical(CGRect(origin: .zero, size: size), [(0, mix(\.top)), (0.6, mix(\.middle)), (1, mix(\.bottom))])
        // Stars at night; by day, faint dark dust instead.
        let stars = light.amount { Self.look($0).starlight }, day = light.darkInk
        var rng = SceneRandom(seed: 21)
        for _ in 0..<220 {
            let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
            let radius = CGFloat(0.4 + rng.next() * 1.1) * max(size.height / 1000, 0.6)
            let a = 0.2 + rng.next() * 0.6
            let color = day ? Color(red: 0.16, green: 0.2, blue: 0.31).opacity(a * 0.3) : Color.white.opacity(a * stars)
            ctx.fillCircle(at: p, radius: radius, color: color)
        }
    }

    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion) {
        let u = size.height / 1000
        for inhabitant in state.inhabitants {
            let lift = motion.lifted[inhabitant.id] ?? 0
            guard lift < 0.99 else { continue }
            var faded = ctx
            faded.opacity = 1 - lift
            Self.planet(&faded, inhabitant, at: scenePoint(spot(for: inhabitant, in: state), in: size),
                        radius: Self.planetRadius(inhabitant, u: u), sunward: nil, day: state.light.darkInk,
                        date: date, motion: motion)
        }
    }

    static func planetRadius(_ inhabitant: SceneInhabitant, u: CGFloat) -> CGFloat {
        CGFloat(10 + 8 * inhabitant.busyness) * u
    }

    /// A planet: a globe in its agent's colour, lit from `sunward` (a unit direction toward the sun) while it shines,
    /// in its mood's glow, with a moon circling while it works.
    static func planet(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at p: CGPoint, radius: CGFloat,
                       sunward: CGPoint?, day: Bool, date: Date, motion: SceneMotion) {
        guard radius > 0.3 else { return }
        let body = Palette.agent(inhabitant.agent).color
        let level = glowLevel(inhabitant, date: date, motion: motion)
        ctx.fillGlow(at: p, radius: radius * 6,
                     color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level * (day ? 0.75 : 1)))
        let lightFrom = sunward ?? CGPoint(x: -0.4, y: -0.6)
        let shade = day ? Color(red: 0.23, green: 0.25, blue: 0.3) : Color(red: 0.02, green: 0.02, blue: 0.04)
        let gradient = Gradient(stops: [.init(color: .white, location: 0), .init(color: body, location: 0.35),
                                        .init(color: shade, location: 1)])
        let highlight = CGPoint(x: p.x + lightFrom.x * radius * 0.45, y: p.y + lightFrom.y * radius * 0.45)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(gradient, center: highlight, startRadius: radius * 0.1, endRadius: radius))
        guard inhabitant.mood == .working else { return }
        let t = motion.still || motion.reduce ? 0 : date.timeIntervalSinceReferenceDate * 2.4
        ctx.fillCircle(at: CGPoint(x: p.x + CGFloat(cos(t)) * radius * 2.2, y: p.y + CGFloat(sin(t)) * radius * 0.9),
                       radius: max(1.2, radius * 0.22), color: Color(red: 0.8, green: 0.93, blue: 0.9))
    }
}
