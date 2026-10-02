import AppKit

/// Where the island lives: the hardware notch, or a virtual one centered in the menu bar.
struct IslandGeometry: Equatable {
    let screenFrame: CGRect
    let hasNotch: Bool
    /// Width of the hardware notch; the virtual notch on other displays.
    let notchWidth: CGFloat
    /// Height of the notch (the menu bar on notched displays).
    let notchHeight: CGFloat
    /// Horizontal center of the notch in global screen coordinates.
    let centerX: CGFloat

    /// The panel is big enough for the largest presentation and never resizes.
    static let panelSize = CGSize(width: 560, height: 420)

    var panelFrame: CGRect {
        CGRect(x: centerX - Self.panelSize.width / 2, y: screenFrame.maxY - Self.panelSize.height,
               width: Self.panelSize.width, height: Self.panelSize.height)
    }

    /// A rect of `size` hanging from the top center of the notch, in global coordinates.
    func screenRect(for size: CGSize) -> CGRect {
        CGRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// The display with the hardware notch if there is one; otherwise the display with the menu bar, which macOS lists
    /// first (on a Mac Studio or a Mac mini, wherever you put the menu bar in Displays settings).
    static func current() -> IslandGeometry? {
        let screens = NSScreen.screens
        let notched = ignoresNotch ? nil : screens.first(where: { $0.safeAreaInsets.top > 0 })
        guard let screen = notched ?? screens.first else { return nil }
        let frame = screen.frame

        if notched != nil, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The auxiliary areas are reported relative to the screen; normalize to global coordinates.
            let offset = left.minX >= frame.minX - 0.5 && left.minX <= frame.minX + 0.5 ? 0 : frame.minX
            let notchLeft = left.maxX + offset, notchRight = right.minX + offset
            return IslandGeometry(screenFrame: frame, hasNotch: true, notchWidth: max(0, notchRight - notchLeft),
                                  notchHeight: screen.safeAreaInsets.top, centerX: (notchLeft + notchRight) / 2)
        }

        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 8 ? menuBar : NSStatusBar.system.thickness
        return IslandGeometry(screenFrame: frame, hasNotch: false, notchWidth: 120, notchHeight: height, centerX: frame.midX)
    }

    #if DEBUG || AMBIENT_DEV
    /// Dev builds: `defaults write com.viveky259259.Ambient debugVirtualNotch -bool true` lays the island out as on a
    /// Mac without a notch, to try the Mac Studio and Mac mini layout on a MacBook.
    private static var ignoresNotch: Bool { UserDefaults.standard.bool(forKey: "debugVirtualNotch") }
    #else
    private static let ignoresNotch = false
    #endif
}
