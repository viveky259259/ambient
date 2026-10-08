import AmbientCore
import SwiftUI

/// The pet: pixel art that flips between two frames to act out its pose, and plays a reaction when asked.
/// Between reactions it redraws only a few times a second.
struct PetFigure: View {
    let species: PetSpecies
    let pose: PetPose
    let tint: RGB
    /// Prompts waiting; from two, the pet holds up their count instead of a "!".
    var waiting = 1
    let reaction: PetReaction
    let reactionCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // With Reduce Motion the pet holds one frame, so the timeline doesn't tick at all.
        TimelineView(.animation(minimumInterval: Self.interval(pose), paused: reduceMotion)) { ctx in
            let frame = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / Self.interval(pose)) % 2
            PixelPet(species: species, pose: pose, frame: frame, tint: tint, waiting: waiting)
                .offset(y: pose == .waiting && frame == 1 ? -PetViewModel.pixel : 0)
        }
        .keyframeAnimator(initialValue: Motion(), trigger: reactionCount) { content, m in
            content
                .shadow(color: tint.color.opacity(0.55 * m.glow), radius: 6)
                .scaleEffect(x: m.stretch, y: 2 - m.stretch, anchor: .bottom)
                .rotationEffect(.degrees(m.spin), anchor: UnitPoint(x: 0.5, y: 0.65))
                .offset(x: m.x, y: m.y)
        } keyframes: { _ in
            let shape = ReactionShape(reaction, still: reduceMotion)
            KeyframeTrack(\.y) {
                CubicKeyframe(shape.jump, duration: 0.16)
                CubicKeyframe(0, duration: 0.16)
                CubicKeyframe(shape.secondJump, duration: 0.14)
                CubicKeyframe(0, duration: 0.14)
            }
            KeyframeTrack(\.stretch) {
                CubicKeyframe(1 - shape.squash, duration: 0.06)
                CubicKeyframe(1 + shape.squash / 2, duration: 0.12)
                CubicKeyframe(1, duration: 0.14)
                SpringKeyframe(1, duration: 0.28)
            }
            KeyframeTrack(\.spin) {
                CubicKeyframe(shape.spin, duration: 0.34)
                LinearKeyframe(shape.spin, duration: 0.26)
            }
            KeyframeTrack(\.x) {
                LinearKeyframe(shape.shake, duration: 0.07)
                LinearKeyframe(-shape.shake, duration: 0.1)
                LinearKeyframe(shape.shake * 0.6, duration: 0.1)
                LinearKeyframe(-shape.shake * 0.3, duration: 0.1)
                LinearKeyframe(0, duration: 0.08)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(1, duration: 0.12)
                CubicKeyframe(0, duration: 0.5)
            }
        }
        .background(alignment: .bottom) {
            // A soft shadow to stand on, so it reads as sitting on whatever is behind it.
            Ellipse()
                .fill(.black.opacity(0.28))
                .frame(width: 52, height: 7)
                .blur(radius: 2.5)
                .offset(y: 2)
        }
    }

    private static func interval(_ pose: PetPose) -> TimeInterval {
        switch pose {
        case .sleeping: 1.1
        case .working: 0.28
        case .waiting: 0.4
        case .done: 0.5
        case .error: 0.6
        }
    }

    /// The animated values of a reaction; at rest, all neutral.
    struct Motion {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var spin: Double = 0
        var stretch: CGFloat = 1
        var glow: Double = 0
    }

    /// How a reaction moves. With Reduce Motion it only glows.
    private struct ReactionShape {
        var jump: CGFloat = 0
        var secondJump: CGFloat = 0
        var spin: Double = 0
        var shake: CGFloat = 0
        var squash: CGFloat = 0

        init(_ reaction: PetReaction, still: Bool) {
            guard !still else { return }
            switch reaction {
            case .wake: jump = -12; squash = 0.14
            case .hop: jump = -8; squash = 0.1
            case .wave: jump = -10; secondJump = -10; squash = 0.1
            case .cheer: jump = -20; spin = 360; squash = 0.16
            case .shake: shake = 5
            }
        }
    }
}

/// One frame of the pet: a 20×18 bitmap scaled up without smoothing. Drawn once per look and cached; a SwiftUI
/// `Canvas` would have cost the app a Metal renderer (some 55 MB) to draw a few hundred squares.
struct PixelPet: View {
    let species: PetSpecies
    let pose: PetPose
    let frame: Int
    let tint: RGB
    var waiting = 1

    var body: some View {
        Image(decorative: PetSprites.image(species: species, pose: pose, frame: frame, tint: tint, waiting: waiting), scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: PetViewModel.figureSize.width, height: PetViewModel.figureSize.height)
    }
}

/// Rendered frames of the pet, by everything that changes how one looks. Main thread only.
enum PetSprites {
    private struct Key: Hashable {
        let species: PetSpecies
        let pose: PetPose
        let frame: Int
        let r, g, b: Double
        let waiting: Int
    }

    private static var cache: [Key: CGImage] = [:]

    static func image(species: PetSpecies, pose: PetPose, frame: Int, tint: RGB, waiting: Int) -> CGImage {
        let key = Key(species: species, pose: pose, frame: frame % 2, r: tint.r, g: tint.g, b: tint.b,
                      waiting: pose == .waiting ? min(max(waiting, 1), 9) : 1)
        if let image = cache[key] { return image }
        // A handful of looks are in use at a time; start over rather than grow without bound.
        if cache.count > 96 { cache.removeAll() }
        let image = render(key, tint: tint)
        cache[key] = image
        return image
    }

    private static func render(_ key: Key, tint: RGB) -> CGImage {
        let size = PetArt.canvasSize
        let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = PetColors(tint: tint)
        func draw(_ sprite: PixelSprite, at origin: PixelPoint) {
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    guard let k = sprite.pixel(x: x, y: y), let c = colors[k] else { continue }
                    ctx.setFillColor(c)
                    // Core Graphics counts rows from the bottom.
                    ctx.fill(CGRect(x: origin.x + x, y: size.height - 1 - (origin.y + y), width: 1, height: 1))
                }
            }
        }
        let art = PetArt.frames(key.species)
        // Asleep and failed, the body holds still; only the props move.
        let body = art[key.pose == .sleeping || key.pose == .error ? 0 : key.frame % art.count]
        let origin = PetArt.bodyOrigin
        draw(body.body, at: origin)
        let eye = PetArt.eye(PetArt.expression(for: key.pose))
        for e in body.eyes { draw(eye, at: PixelPoint(origin.x + e.x, origin.y + e.y)) }
        if let mouth = PetArt.mouth(for: key.pose) {
            draw(mouth, at: PixelPoint(origin.x + body.mouth.x, origin.y + body.mouth.y))
        }
        for placed in PetArt.props(for: key.pose, frame: key.frame, waiting: key.waiting) {
            draw(placed.sprite, at: placed.at)
        }
        return ctx.makeImage()!
    }
}

/// The colors behind `PixelSprite`'s keys, for a body tint.
struct PetColors {
    private let body, shade, highlight, glow: CGColor
    private static let ink = RGB(r: 0.08, g: 0.09, b: 0.11).cgColor

    init(tint: RGB) {
        body = tint.cgColor
        shade = tint.mixed(with: RGB(r: 0, g: 0, b: 0), 0.3).cgColor
        highlight = tint.mixed(with: RGB(r: 1, g: 1, b: 1), 0.45).cgColor
        glow = tint.mixed(with: RGB(r: 1, g: 1, b: 1), 0.6).cgColor
    }

    subscript(key: Character) -> CGColor? {
        switch key {
        case "o", "e": Self.ink
        case "b": body
        case "s": shade
        case "h": highlight
        case "g": glow
        case "w": RGB(r: 0.96, g: 0.96, b: 0.96).cgColor
        case "k": RGB(r: 1, g: 1, b: 1).cgColor
        case "a": Palette.waiting.cgColor
        case "G": Palette.done.cgColor
        case "c": RGB(r: 0.49, g: 0.83, b: 0.99).cgColor
        case "z": RGB(r: 0.9, g: 0.91, b: 0.92).cgColor
        default: nil
        }
    }
}

private extension RGB {
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// Pixels flying out of clicks, drawn only while a burst lives. Plain squares rather than a `Canvas`, for the same
/// reason as the pet.
struct PetBurstLayer: View {
    let bursts: [PetViewModel.Burst]

    var body: some View {
        if !bursts.isEmpty {
            TimelineView(.animation) { ctx in
                ZStack(alignment: .topLeading) {
                    ForEach(bursts) { b in
                        let t = ctx.date.timeIntervalSince(b.start)
                        ForEach(b.particles.indices, id: \.self) { i in
                            let p = b.particles[i], o = p.offset(at: t)
                            Rectangle()
                                .fill(p.accent ? Color.white : b.color.color)
                                .frame(width: p.size, height: p.size)
                                .opacity(p.opacity(at: t))
                                .position(x: b.origin.x + o.x, y: b.origin.y + o.y)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .allowsHitTesting(false)
        }
    }
}
