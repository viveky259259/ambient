/// A color as plain numbers, so code without AppKit or SwiftUI can choose one.
public struct RGB: Equatable, Sendable {
    public let r, g, b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(digits, radix: 16) ?? 0
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    /// A straight mix toward `other`; `t` is clamped to 0...1.
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        let t = min(1, max(0, t))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}
