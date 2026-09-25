import AmbientCore
import AppKit
import SwiftUI

extension RGB {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

extension Activity {
    /// The mood this activity has before acknowledgement; drives colors and glyphs.
    var rawMood: Mood {
        switch self {
        case .idle: .idle
        case .thinking, .tool, .compacting: .working
        case .waiting: .waiting
        case .done: .done
        case .error: .error
        }
    }
}

extension Session {
    /// The color of what the session is literally doing, for rows that describe it.
    var tint: RGB { Palette.mood(activity.rawMood, agent: agent) }
    /// The color of how much it wants attention, for the aggregate signals (island wings, menu bar, Dock).
    var moodTint: RGB { Palette.mood(mood, agent: agent) }
}
