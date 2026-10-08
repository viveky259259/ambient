import CoreGraphics

/// Where the pet and its panel go on screen, in global screen coordinates (origin bottom-left).
public enum PetLayout {
    /// Distance from the screen's edges of the default spot.
    public static let inset: CGFloat = 24
    /// Least distance between the bubble and the panel's sides.
    public static let bubbleMargin: CGFloat = 4

    public struct Placement: Equatable, Sendable {
        public let panel: CGRect
        /// The pet's origin inside the panel, bottom-left based like the screen.
        public let petInPanel: CGPoint
        /// The bubble opens above the pet (lower half of the screen) or below it.
        public let opensUp: Bool
    }

    /// The bottom-right corner of the visible screen.
    public static func defaultOrigin(in visible: CGRect, pet: CGSize) -> CGPoint {
        CGPoint(x: visible.maxX - pet.width - inset, y: visible.minY + inset)
    }

    /// Keeps the whole pet on screen.
    public static func clamp(_ origin: CGPoint, pet: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: clamped(origin.x, visible.minX, visible.maxX - pet.width),
                y: clamped(origin.y, visible.minY, visible.maxY - pet.height))
    }

    /// The panel that holds the pet and its bubble: centered on the pet, on the side of the pet with more room,
    /// and on screen.
    public static func place(pet: CGPoint, petSize: CGSize, panel: CGSize, in visible: CGRect) -> Placement {
        let opensUp = pet.y + petSize.height / 2 < visible.midY
        let x = clamped(pet.x + petSize.width / 2 - panel.width / 2, visible.minX, visible.maxX - panel.width)
        let y = clamped(opensUp ? pet.y : pet.y + petSize.height - panel.height, visible.minY, visible.maxY - panel.height)
        return Placement(panel: CGRect(origin: CGPoint(x: x, y: y), size: panel),
                         petInPanel: CGPoint(x: pet.x - x, y: pet.y - y), opensUp: opensUp)
    }

    /// The bubble's horizontal center: over the pet, but inside the panel.
    public static func bubbleCenterX(petMidX: CGFloat, width: CGFloat, panelWidth: CGFloat) -> CGFloat {
        clamped(petMidX, width / 2 + bubbleMargin, panelWidth - width / 2 - bubbleMargin)
    }

    private static func clamped(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        hi < lo ? lo : min(max(v, lo), hi)
    }
}
