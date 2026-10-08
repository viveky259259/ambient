import CoreGraphics
import Foundation

/// The burst of pixels that flies out of a click on the pet or a session: square particles that shoot out,
/// slow down, fall and fade. Seeded, so a burst plays the same however often it's drawn.
public enum PetBurst {
    public static let lifetime: TimeInterval = 0.9
    /// Points per second squared, screen-down.
    static let gravity: CGFloat = 320
    /// How quickly particles lose their launch speed.
    static let drag: CGFloat = 3

    public struct Particle: Equatable, Sendable {
        /// Radians, counterclockwise from screen-right.
        public let angle: CGFloat
        /// Points per second at launch.
        public let speed: CGFloat
        /// Side of the square, in points.
        public let size: CGFloat
        /// Drawn in the accent (white) rather than the burst's color.
        public let accent: Bool

        public init(angle: CGFloat, speed: CGFloat, size: CGFloat, accent: Bool) {
            self.angle = angle
            self.speed = speed
            self.size = size
            self.accent = accent
        }

        /// Where the particle is `t` seconds in, relative to the burst's origin, in view coordinates (y down).
        public func offset(at t: TimeInterval) -> CGPoint {
            let t = CGFloat(max(0, t))
            let travelled = speed * (1 - exp(-drag * t)) / drag
            return CGPoint(x: cos(angle) * travelled, y: -sin(angle) * travelled + gravity * t * t / 2)
        }

        public func opacity(at t: TimeInterval) -> Double {
            guard t > 0 else { return 1 }
            guard t < lifetime else { return 0 }
            let p = t / lifetime
            return 1 - p * p
        }
    }

    public static func particles(seed: UInt64, count: Int = 18) -> [Particle] {
        var rng = SplitMix(seed: seed)
        return (0..<count).map { i in
            // Spread evenly round the circle with some jitter, so no burst comes out lopsided.
            let base = CGFloat(i) / CGFloat(count) * 2 * .pi
            return Particle(angle: base + CGFloat(rng.next() - 0.5) * 0.5,
                            speed: 120 + CGFloat(rng.next()) * 140,
                            size: rng.next() < 0.3 ? 3 : 4,
                            accent: rng.next() < 0.25)
        }
    }
}
