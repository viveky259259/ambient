import AmbientCore
import SwiftUI

/// Draws a running notch effect over the scene's life: the black hole with its gravity sheet, dust and orbs, or
/// the sun with its orbits, belt and planets. The island's own menu is drawn by the island, in front of all this.
enum NotchEffectDrawing {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, engine: NotchEffectEngine, state: SceneState,
                     date: Date, motion: SceneMotion, showsLabels: Bool) {
        guard let sim = engine.simulation, sim.geometry.screen.x > 0 else { return }
        // The simulation works in the screen's points; a thumbnail or a scaled window draws it smaller.
        let k = size.width / sim.geometry.screen.x
        var ctx = ctx
        ctx.scaleBy(x: k, y: k)
        let look = Look(day: state.light.darkInk, unit: sim.geometry.unit)
        let inhabitants = Dictionary(state.inhabitants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let t = motion.reduce ? 0 : date.timeIntervalSinceReferenceDate
        switch sim.mode {
        case .blackHole:
            blackHole(&ctx, sim, engine: engine, inhabitants: inhabitants, look: look, t: t, date: date, motion: motion,
                      showsLabels: showsLabels)
        case .solar:
            solar(&ctx, sim, engine: engine, inhabitants: inhabitants, look: look, t: t, date: date, motion: motion,
                  showsLabels: showsLabels)
        }
    }

    /// Colours for the time of day: the light look by day, the dark look at dawn, dusk and night.
    struct Look {
        let day: Bool
        let unit: Double
        var grid: Color { day ? Color(red: 0.16, green: 0.24, blue: 0.47) : Color(red: 0.55, green: 0.63, blue: 1) }
        var dust: (Double, Double, Double) { day ? (0.16, 0.2, 0.31) : (1, 1, 1) }
        var ring: Color { day ? Color(red: 0.16, green: 0.24, blue: 0.47) : Color(red: 0.63, green: 0.7, blue: 1) }
        var belt: Color { day ? Color(red: 0.43, green: 0.37, blue: 0.31) : Color(red: 0.82, green: 0.78, blue: 0.75) }
        var ink: Color { day ? Color(white: 0.08) : .white }
        var waiting: Color { day ? Color(red: 0.66, green: 0.38, blue: 0) : Color(red: 0.96, green: 0.73, blue: 0.29) }
        var glow: Double { day ? 0.75 : 1 }
        var u: CGFloat { CGFloat(unit) }
    }

    // MARK: - Black hole

    private static func blackHole(_ ctx: inout GraphicsContext, _ sim: NotchSimulation, engine: NotchEffectEngine,
                                  inhabitants: [String: SceneInhabitant], look: Look, t: Double, date: Date,
                                  motion: SceneMotion, showsLabels: Bool) {
        let c = cg(sim.geometry.center), R = CGFloat(sim.radius), grow = sim.presence, u = look.u
        let screen = CGSize(width: sim.geometry.screen.x, height: sim.geometry.screen.y)

        // The gravity sheet: a grid sinking into a well at the hole, fading with distance, rippling with the
        // birth's wave. Only while the hole is there.
        if R > 0.5 {
            let notchR = CGFloat(sim.geometry.radius), wave = sim.waveRadius.map { CGFloat($0) }
            func warp(_ p: CGPoint) -> (CGPoint, CGFloat) {
                let dx = p.x - c.x, dy = p.y - c.y, r = max(1, hypot(dx, dy))
                var pull = CGFloat(grow) * notchR * 1.35 * notchR / (r + notchR * 0.35)
                pull = min(pull, max(0, r - notchR * 0.55))
                var ripple: CGFloat = 0
                if let wave {
                    let d = r - wave
                    ripple = 9 * u * exp(-(d * d) / (2 * pow(28 * u, 2))) * sin(d / (9 * u)) * CGFloat(1 - sim.sinceOpen / 1.6)
                }
                let k = (r - pull + ripple) / r
                return (CGPoint(x: c.x + dx * k, y: c.y + dy * k), pull / r)
            }
            let step = 34 * u, reach = screen.height * 0.9
            for pass in 0..<2 {
                let lines = Int((pass == 0 ? screen.height : screen.width) / step) + 1
                let samples = Int((pass == 0 ? screen.width : screen.height) / 8)
                for i in 0...lines {
                    var path = Path(), bend: CGFloat = 0
                    for j in 0...samples {
                        let p0 = pass == 0 ? CGPoint(x: CGFloat(j) * 8, y: CGFloat(i) * step)
                                           : CGPoint(x: CGFloat(i) * step, y: CGFloat(j) * 8)
                        let (p, b) = warp(p0)
                        bend = max(bend, b)
                        if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    // Lines far from the hole barely show: the sheet is only felt near the well.
                    let lineDistance = pass == 0 ? CGFloat(i) * step - c.y : abs(CGFloat(i) * step - c.x)
                    let near = min(1, max(0, 1 - lineDistance / reach))
                    let alpha = (0.05 + min(0.22, bend * 0.5)) * near * CGFloat(grow)
                    ctx.stroke(path, with: .color(look.grid.opacity(alpha)), lineWidth: 1)
                }
            }
        }

        // Dust: stretched along its fall by tidal force, reddened near the horizon.
        let (dr, dg, db) = look.dust
        for body in sim.bodies where !body.isAgent && !body.absorbed {
            let p = cg(body.position), dx = p.x - c.x, dy = p.y - c.y, r = max(1, hypot(dx, dy))
            let tidal = R > 1 ? min(14, pow(R * 2.2 / r, 3)) : 0
            let length = min(60, tidal * 2.5 + CGFloat(body.velocity.length) * 0.018)
            let heat = R > 1 ? min(1, max(0, R * 3 / r - 0.8)) : 0
            let color = Color(red: dr + (1 - dr) * heat, green: dg + (0.53 - dg) * heat, blue: db + (0.22 - db) * heat)
                .opacity(body.brightness * body.fade * sim.dustAlpha * (look.day ? 0.6 : 1))
            let size = CGFloat(0.5 + body.brightness) * u
            if length > 1.2 {
                var line = Path()
                line.move(to: CGPoint(x: p.x - dx / r * length / 2, y: p.y - dy / r * length / 2))
                line.addLine(to: CGPoint(x: p.x + dx / r * length / 2, y: p.y + dy / r * length / 2))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: max(0.6, size * (1 - 0.4 * heat)), lineCap: .round))
            } else {
                ctx.fillCircle(at: p, radius: size, color: color)
            }
        }

        // Agents, lifted off as light: an orb in the agent's colour with its mood glow, trailing its path.
        for body in sim.agents where !body.absorbed {
            guard let inhabitant = inhabitants[body.id] else { continue }
            let lift = sim.lift(body.id), p = cg(body.position)
            // Every agent's label rides with it, in the world's own style, so none blink out as the effect takes
            // over and hands back.
            if showsLabels { worldLabel(&ctx, inhabitant, at: p, home: body.home, screen: sim.geometry.screen, look: look) }
            guard lift > 0.01 else { continue }
            trail(&ctx, engine.trails[body.id], color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color,
                  width: 2 * u, alpha: 0.55 * lift)
            var orb = ctx
            orb.opacity = lift
            let level = max(0.35, glowLevel(inhabitant, date: date, motion: motion))
            orb.fillGlow(at: p, radius: 60 * u,
                         color: Palette.mood(inhabitant.mood, agent: inhabitant.agent).color.opacity(level * look.glow))
            orb.fillCircle(at: p, radius: 5 * u, color: .white)
            orb.fillCircle(at: p, radius: 2.4 * u, color: Palette.agent(inhabitant.agent).color)
        }

        // The hole itself, centred on the notch's bottom edge: only its lower half shows below the notch.
        if R > 0.5 {
            let g = CGFloat(grow), spin = t * 1.4, diskOut = R * 3.4
            // The accretion disk along the notch line, brighter on the side turning toward you.
            for i in 0..<70 {
                let f = CGFloat(i) / 69, x = c.x - diskOut + f * diskOut * 2, rr = abs(x - c.x)
                guard rr >= R * 1.02 else { continue }
                let heat = min(1, max(0, 1 - (rr - R) / (diskOut - R))), doppler: CGFloat = x < c.x ? 1 : 0.55
                let th = R * 0.075 * (0.4 + heat)
                ctx.fill(Path(CGRect(x: x, y: c.y - th, width: diskOut * 2 / 69 + 1, height: th * 2)),
                         with: .color(Color(red: 1, green: (170 + 70 * heat) / 255, blue: (90 + 120 * heat) / 255)
                            .opacity(0.85 * heat * doppler * g)))
            }
            for i in 0..<26 {
                let a = Double(i) / 26 * 2 * .pi + spin * (1.8 - Double(i % 5) * 0.2)
                let rr = R * (1.15 + CGFloat(i % 7) * 0.32)
                let x = c.x + CGFloat(cos(a)) * rr, y = c.y + CGFloat(sin(a)) * rr * 0.06
                if abs(x - c.x) < R * 1.02, y > c.y - 2 { continue }
                ctx.fill(Path(CGRect(x: x - 5 * u, y: y - 0.8 * u, width: 10 * u, height: 1.6 * u)),
                         with: .color(Color(red: 1, green: 0.93, blue: 0.78).opacity(0.55 * g * (cos(a) < 0 ? 1 : 0.5))))
            }
            // The far side of the disk, bent by the hole's gravity into arcs beneath it.
            for j in 0..<3 {
                var arc = Path()
                arc.addArc(center: c, radius: R * (1.12 + CGFloat(j) * 0.08), startAngle: .radians(0.05),
                           endAngle: .radians(.pi - 0.05), clockwise: false)
                ctx.stroke(arc, with: .color(Color(red: 1, green: (200 - 30 * Double(j)) / 255, blue: (140 - 30 * Double(j)) / 255)
                    .opacity((0.7 - 0.2 * Double(j)) * g)), style: StrokeStyle(lineWidth: (3.2 - CGFloat(j)) * u, lineCap: .round))
            }
            // The shadow, and the photon ring on its rim.
            ctx.fill(halfDisk(c, R * 1.06), with: .radialGradient(
                Gradient(stops: [.init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0), location: 0.9),
                                 .init(color: Color(red: 1, green: 0.94, blue: 0.82).opacity(0.95 * g), location: 0.95),
                                 .init(color: Color(red: 1, green: 0.78, blue: 0.55).opacity(0), location: 1)]),
                center: c, startRadius: 0, endRadius: R * 1.06))
            ctx.fill(halfDisk(c, R * 0.97), with: .color(.black))
        }

        // The flash as the notch collapses, the wave's crest, and the faint flash as the hole evaporates.
        if sim.birthFlash > 0 {
            let r = CGFloat(sim.geometry.notchWidth) * 1.1
            ctx.fillGlow(at: c, radius: r, color: Color(red: 1, green: 0.96, blue: 0.9).opacity(0.7 * sim.birthFlash))
        }
        if let wave = sim.waveRadius {
            var crest = Path()
            crest.addArc(center: c, radius: CGFloat(wave), startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
            ctx.stroke(crest, with: .color(look.grid.opacity(0.45 * (1 - sim.sinceOpen / 1.6))), lineWidth: 2.5 * u)
        }
        if sim.evaporation > 0 {
            ctx.fillGlow(at: c, radius: CGFloat(sim.geometry.notchWidth) * 0.8,
                         color: Color(red: 0.82, green: 0.88, blue: 1).opacity(0.6 * sim.evaporation))
        }
    }

    // MARK: - Solar System

    private static func solar(_ ctx: inout GraphicsContext, _ sim: NotchSimulation, engine: NotchEffectEngine,
                              inhabitants: [String: SceneInhabitant], look: Look, t: Double, date: Date,
                              motion: SceneMotion, showsLabels: Bool) {
        let geometry = sim.geometry, c = cg(geometry.center), light = sim.presence, u = look.u
        let s = SolarLayout.scale(screen: geometry.screen), e = SolarLayout.eccentricity, tilt = SolarLayout.tilt
        let screenHeight = CGFloat(geometry.screen.y)

        // Orbit rings: ellipses with the sun at a focus, their centre a·e below it.
        for a in Set(sim.agents.compactMap(\.orbit)).sorted() {
            let rx = CGFloat(a * (1 - e * e).squareRoot() * s), ry = CGFloat(a * s * tilt)
            let cy = c.y + CGFloat(a * e * s * tilt)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: cy - ry, width: rx * 2, height: ry * 2)),
                       with: .color(look.ring.opacity(0.2 * light)), lineWidth: 1)
        }
        // The asteroid belt.
        for body in sim.bodies where !body.isAgent {
            let depth = CGFloat(1 + 0.35 * sin(body.theta))
            ctx.fillCircle(at: cg(body.position), radius: CGFloat(0.5 + body.brightness) * u * depth,
                           color: look.belt.opacity(body.brightness * (0.6 + 0.4 * light) * sim.dustAlpha))
        }

        // The sun: its diameter is the notch line. Corona, slow flares, and the lit disk.
        if light > 0.01 {
            let R = CGFloat(sim.radius), l = light
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R * 4.2, y: c.y - R * 4.2, width: R * 8.4, height: R * 8.4)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red: 1, green: 0.84, blue: 0.55).opacity(0.75 * l), location: 0.19),
                        .init(color: Color(red: 1, green: 0.59, blue: 0.27).opacity(0.25 * l), location: 0.45),
                        .init(color: Color(red: 1, green: 0.47, blue: 0.16).opacity(0), location: 1)]),
                        center: c, startRadius: 0, endRadius: R * 4.2))
            for i in 0..<9 {
                let a = Double(i) / 9 * .pi + sin(t * 0.7 + Double(i)) * 0.15
                let length = R * CGFloat(1.25 + 0.25 * sin(t * 1.3 + Double(i) * 2.1))
                var flare = Path()
                flare.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * R, y: c.y + CGFloat(sin(a)) * R))
                flare.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * length, y: c.y + CGFloat(sin(a)) * length))
                ctx.stroke(flare, with: .color(Color(red: 1, green: 0.75, blue: 0.43).opacity(0.28 * l)),
                           style: StrokeStyle(lineWidth: 3 * u, lineCap: .round))
            }
            ctx.fill(halfDisk(c, R), with: .radialGradient(Gradient(stops: [
                .init(color: Color(red: 1, green: 0.99, blue: 0.92).opacity(l), location: 0),
                .init(color: Color(red: 1, green: 0.82, blue: 0.47).opacity(l), location: 0.7),
                .init(color: Color(red: 1, green: 0.59, blue: 0.24).opacity(l), location: 1)]),
                center: CGPoint(x: c.x, y: c.y - R * 0.2), startRadius: 0, endRadius: R))
        }

        // Planets, far ones first so near ones pass in front.
        let order = sim.agents.filter { !$0.absorbed }.sorted { depth($0) < depth($1) }
        for body in order {
            guard let inhabitant = inhabitants[body.id] else { continue }
            let p = cg(body.position)
            // Falling into the sun, a planet shrinks as it nears it.
            let near = body.orbit != nil ? 1 : min(1, CGFloat((body.position - geometry.center).length) / (screenHeight * 0.3))
            let d = CGFloat(body.orbit != nil ? 1 + (1 + 0.35 * sin(body.theta) - 1) * light : 1) * near
            if body.velocity.length > 8 {
                trail(&ctx, engine.trails[body.id], color: Palette.agent(inhabitant.agent).color, width: 2 * u, alpha: 0.45)
            }
            let toSun = CGPoint(x: c.x - p.x, y: c.y - p.y), length = max(1, hypot(toSun.x, toSun.y))
            let sunward = light > 0.05 ? CGPoint(x: toSun.x / length * CGFloat(light), y: toSun.y / length * CGFloat(light)) : nil
            // The world's own planet size, so nothing jumps when the world takes a planet back.
            let radius = SolarScene.planetRadius(inhabitant, u: screenHeight / 1000) * d
            SolarScene.planet(&ctx, inhabitant, at: p, radius: radius, sunward: sunward, day: look.day, date: date, motion: motion)
            // Labels once a planet is clear of the notch and not shrinking into the sun: centred under it in the rows,
            // beside it in orbit.
            // Planets falling into the sun go quietly, without labels.
            guard showsLabels, p.y > c.y + 8, near > 0.9, body.orbit != nil || light < 0.05 else { continue }
            if light < 0.5 || body.orbit == nil {
                label(&ctx, inhabitant, at: CGPoint(x: p.x, y: p.y + radius + 12 * u), anchor: .top, look: look)
            } else {
                label(&ctx, inhabitant, at: CGPoint(x: p.x + radius + 10 * u, y: p.y), anchor: .leading, look: look)
            }
        }
    }

    // MARK: - Pieces

    private static func depth(_ body: NotchSimulation.Body) -> Double { body.orbit != nil ? sin(body.theta) : 2 }

    private static func cg(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    /// The lower half of a disk: the half below the notch line.
    private static func halfDisk(_ c: CGPoint, _ r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: c.x + r, y: c.y))
        path.addArc(center: c, radius: r, startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
        path.closeSubpath()
        return path
    }

    private static func trail(_ ctx: inout GraphicsContext, _ points: [CGPoint]?, color: Color, width: CGFloat, alpha: Double) {
        guard let points, points.count > 2 else { return }
        for i in 1..<points.count {
            let f = Double(i) / Double(points.count)
            var segment = Path()
            segment.move(to: points[i - 1])
            segment.addLine(to: points[i])
            ctx.stroke(segment, with: .color(color.opacity(alpha * f)), lineWidth: width * CGFloat(f))
        }
    }

    /// A label exactly as the scene's text layer sets it beside an inhabitant: headline, place and detail, 22 pt to
    /// the side, on the left of inhabitants whose home is near the right edge, with the same halo.
    private static func worldLabel(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at p: CGPoint,
                                   home: Vec2, screen: Vec2, look: Look) {
        let u = min(1.6, CGFloat(screen.y) / 1000)
        let flipped = home.x / screen.x > 0.72
        var lines: [(Text, CGFloat)] = [
            (Text(inhabitant.headline).font(.system(size: 12.5 * u, weight: .semibold))
                .foregroundColor(inhabitant.mood == .waiting ? look.waiting : look.ink), 15 * u),
            (Text(inhabitant.place).font(.system(size: 12 * u)).foregroundColor(look.ink.opacity(0.75)), 14.4 * u),
        ]
        if let detail = inhabitant.detail {
            lines.append((Text(detail).font(.system(size: 11 * u, design: .monospaced)).foregroundColor(look.ink.opacity(0.6)), 13.2 * u))
        }
        var text = ctx
        text.addFilter(.shadow(color: look.day ? .white.opacity(0.45) : .black.opacity(0.5), radius: 6 * u))
        let total = lines.reduce(0) { $0 + $1.1 } + 2 * u * CGFloat(lines.count - 1)
        var y = p.y - total / 2
        let x = flipped ? p.x - 22 * u : p.x + 22 * u
        for (line, height) in lines {
            text.draw(line, at: CGPoint(x: x, y: y + height / 2), anchor: flipped ? .trailing : .leading)
            y += height + 2 * u
        }
    }

    /// A moving agent's label: its headline, in the ink for the time of day.
    private static func label(_ ctx: inout GraphicsContext, _ inhabitant: SceneInhabitant, at point: CGPoint,
                              anchor: UnitPoint, look: Look) {
        let text = Text(inhabitant.headline)
            .font(.system(size: 11.5 * look.u, weight: .semibold))
            .foregroundColor(inhabitant.mood == .waiting ? look.waiting : look.ink)
        ctx.draw(text, at: point, anchor: anchor)
    }
}
