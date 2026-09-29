import AmbientCore
import SwiftUI

/// How much a scene may move.
struct SceneMotion: Equatable {
    /// Reduce Motion: nothing drifts, sways or circles; glows still fade in and out.
    var reduce = false
    /// A still frame: covered, Low Power Mode, a thumbnail, or the lock-screen fallback image.
    var still = false
}

/// Where text sits in a scene: the clock and your day top-left, the labels beside inhabitants, and the story
/// and timeline along the bottom.
enum SceneTextRegion {
    case header, labels, footer
}

/// Draws one world. Spots are in unit coordinates: (0, 0) is the top-left corner, (1, 1) the bottom-right.
protocol SceneRenderer {
    /// Where inhabitant spot `slot` sits. Lock-screen spots stay clear of the lock screen's clock (top center)
    /// and password field (bottom center).
    func spot(_ slot: Int, surface: SceneSurface) -> CGPoint
    /// What only changes with the state: sky, land, water and the day's build-up. Drawn once per change, not per frame.
    func drawScenery(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState)
    /// What moves: inhabitants, twinkles, sparks, wakes, fireflies, and the turn that just finished. Drawn every frame.
    func drawLife(_ ctx: inout GraphicsContext, size: CGSize, state: SceneState, date: Date, motion: SceneMotion)
    /// Whether text in `region` needs dark ink: only where it sits on bright sky.
    func darkInk(_ region: SceneTextRegion, light: DayLight) -> Bool
}

enum SceneRenderers {
    static func renderer(for kind: SceneKind) -> any SceneRenderer {
        switch kind {
        case .sky: SkyScene()
        case .harbor: HarborScene()
        case .garden: GardenScene()
        case .solar: SkyScene()
        }
    }
}

/// Repeatable randomness (SplitMix64), so stars and fireflies sit in the same places every frame and every launch.
struct SceneRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

extension GraphicsContext {
    /// A soft light: `color` at the center, fading out by `radius`.
    func fillGlow(at center: CGPoint, radius: CGFloat, color: Color) {
        guard radius > 0 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(stops: [
            .init(color: color, location: 0),
            .init(color: color.opacity(0.3), location: 0.3),
            .init(color: color.opacity(0), location: 1),
        ])
        fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
    }

    func fillCircle(at center: CGPoint, radius: CGFloat, color: Color) {
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
             with: .color(color))
    }

    /// A top-to-bottom gradient over `rect`. Stops are (location 0...1, color).
    func fillVertical(_ rect: CGRect, _ stops: [(Double, Color)]) {
        let gradient = Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) })
        fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                               endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }
}

/// How bright an inhabitant's glow is right now, in the Dock glow's rhythms. Failures flicker.
func glowLevel(_ inhabitant: SceneInhabitant, date: Date, motion: SceneMotion) -> Double {
    guard let style = GlowStyle.for(mood: inhabitant.mood, agent: inhabitant.agent) else { return 0.18 }
    if motion.still { return style.high }
    let t = date.timeIntervalSinceReferenceDate
    if inhabitant.mood == .error, !motion.reduce { return style.high * (sin(t * 7) > 0.7 ? 0.45 : 1) }
    return style.level(at: t)
}

/// A spot in unit coordinates, on a canvas of `size`.
func scenePoint(_ spot: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: spot.x * size.width, y: spot.y * size.height)
}

/// How far a just-finished turn has come on its way into the day's build-up: 0 → 1 over two seconds,
/// nil when nothing is arriving.
func arrivalProgress(of marks: [DayMark], at date: Date) -> Double? {
    guard let last = marks.last else { return nil }
    let age = date.timeIntervalSince(last.at)
    return age >= 0 && age < 2 ? age / 2 : nil
}
