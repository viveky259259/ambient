import AmbientCore
import AppKit
import SwiftUI

/// Ambient's design tokens: spacing, shape, type, color and layout, in one place.
enum Theme {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let panel: CGFloat = 18
    }

    enum Fonts {
        static let heroTitle = Font.system(size: 30, weight: .bold)
        static let paneTitle = Font.system(size: 26, weight: .bold)
        static let paneSubtitle = Font.system(size: 13)
        static let sectionHeader = Font.system(size: 13, weight: .semibold)
        static let row = Font.system(size: 13)
        static let rowEmphasis = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        static let mono = Font.system(size: 11, design: .monospaced)
        static let button = Font.system(size: 12, weight: .medium)
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 200
        static let contentMaxWidth: CGFloat = 560
        static let previewHeight: CGFloat = 150
        static let rowMinHeight: CGFloat = 44
        static let windowSize = CGSize(width: 780, height: 560)
        static let windowMinSize = CGSize(width: 700, height: 480)
        /// Like System Settings: wider than this only spreads the pane away from the sidebar.
        static let windowMaxWidth: CGFloat = 900
    }

    enum Colors {
        /// Grouped-card fill: a lift above the window in both appearances.
        static let card = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.75)
        })
        static let hairline = Color(nsColor: .separatorColor)
        static let hover = Color.primary.opacity(0.05)
        static let selection = Color.accentColor.opacity(0.16)

        /// A soft desktop behind the previews.
        static func wallpaper(_ scheme: ColorScheme) -> LinearGradient {
            let colors: [Color] = scheme == .dark
                ? [Color(red: 0.11, green: 0.16, blue: 0.29), Color(red: 0.23, green: 0.14, blue: 0.29)]
                : [Color(red: 0.62, green: 0.76, blue: 0.96), Color(red: 0.95, green: 0.78, blue: 0.85)]
            return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// What a badge, dot or note is saying.
    enum Status {
        case success, warning, error, neutral

        /// Fills: dots and tints, in Ambient's own palette.
        var color: Color {
            switch self {
            case .success: Palette.done.color
            case .warning: Palette.waiting.color
            case .error: Palette.error.color
            case .neutral: Palette.idle.color
            }
        }

        /// Text: system colors keep their contrast in light and dark.
        var textColor: Color {
            switch self {
            case .success: .green
            case .warning: .orange
            case .error: .red
            case .neutral: .secondary
            }
        }
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
