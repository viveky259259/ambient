import Foundation

/// The Solar System world's geometry: planets in rows while the island is closed, and Kepler ellipses around the
/// notch-sun while it's open. Orbits lie on a tilted plane; the sun is at a focus and each far point is at the bottom,
/// so planets drift slowly across the lower screen and race round behind the sun.
public enum SolarLayout {
    public static let maxOrbiting = 6
    public static let eccentricity = 0.45
    /// Vertical squash of the orbital plane.
    public static let tilt = 0.72
    /// Gravity in plane units: angular speed is √(gm · a(1 − e²)) / r².
    public static let gm = 0.045

    /// Where `count` planets stand while the island is closed, as fractions of the screen: one row up to four,
    /// two centred rows beyond.
    public static func rowSlots(count: Int) -> [Vec2] {
        guard count > 0 else { return [] }
        let rows = count > 4 ? 2 : 1
        let perRow = (count + rows - 1) / rows
        return (0..<count).map { i in
            let row = i / perRow, column = i % perRow
            let inRow = row == rows - 1 ? count - perRow * (rows - 1) : perRow
            let span = min(0.8, 0.2 * Double(inRow - 1))
            let x = inRow == 1 ? 0.5 : (1 - span) / 2 + span * Double(column) / Double(inRow - 1)
            let y = rows == 1 ? 0.46 : (row == 0 ? 0.40 : 0.60)
            return Vec2(x, y)
        }
    }

    /// The agents that orbit: the most urgent six (ties keep their order), innermost orbit first.
    public static func orbiters(_ agents: [NotchAgent]) -> [String] {
        agents.enumerated()
            .sorted { $0.element.urgency != $1.element.urgency ? $0.element.urgency < $1.element.urgency : $0.offset < $1.offset }
            .prefix(maxOrbiting)
            .map(\.element.id)
    }

    /// Distance from the sun, in plane units, of an orbit with semi-major axis `a` at angle `theta`
    /// (screen-style angles: π/2 points down, where the far point is).
    public static func radius(a: Double, theta: Double) -> Double {
        let e = eccentricity
        return a * (1 - e * e) / (1 - e * sin(theta))
    }

    /// Kepler's second law: fast near the sun, slow far out.
    public static func angularSpeed(a: Double, theta: Double) -> Double {
        let e = eccentricity, r = radius(a: a, theta: theta)
        return (gm * a * (1 - e * e)).squareRoot() / (r * r)
    }

    /// Points per plane unit: the widest orbit (a = 0.72) fits the screen's width.
    public static func scale(screen: Vec2) -> Double {
        min(screen.y * 1.1, screen.x * 0.49 / (0.72 * (1 - eccentricity * eccentricity).squareRoot()))
    }

    /// Semi-major axes for `count` orbiters, innermost first. The innermost far point clears the island's menu.
    public static func orbits(count: Int, geometry: NotchGeometry) -> [Double] {
        guard count > 0 else { return [] }
        let s = scale(screen: geometry.screen)
        let clear = (geometry.menu.y + 30 - geometry.notchBottom) / ((1 + eccentricity) * s * tilt)
        let inner = max(0.42, clear), outer = max(0.72, inner + 0.12)
        guard count > 1 else { return [inner] }
        return (0..<count).map { inner + (outer - inner) * Double($0) / Double(count - 1) }
    }

    /// Where on screen a planet on orbit `a` at angle `theta` is.
    public static func point(a: Double, theta: Double, geometry: NotchGeometry) -> Vec2 {
        let s = scale(screen: geometry.screen), r = radius(a: a, theta: theta)
        return geometry.center + Vec2(cos(theta) * r * s, sin(theta) * r * s * tilt)
    }
}
