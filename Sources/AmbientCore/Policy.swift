import Foundation

/// When Ambient interrupts: notifications and sounds are for moments that need the user.
public enum AlertPolicy {
    public struct Settings: Equatable, Sendable {
        public var notifications: Bool
        public var sounds: Bool
        /// Turns shorter than this finish silently; the user was probably watching.
        public var doneThreshold: TimeInterval
        public var quiet: Bool

        public init(notifications: Bool, sounds: Bool, doneThreshold: TimeInterval, quiet: Bool) {
            self.notifications = notifications
            self.sounds = sounds
            self.doneThreshold = doneThreshold
            self.quiet = quiet
        }
    }

    public struct Alert: Equatable, Sendable {
        public let mood: Mood
        public let notify: Bool
        public let sound: Bool

        public init(mood: Mood, notify: Bool, sound: Bool) {
            self.mood = mood
            self.notify = notify
            self.sound = sound
        }
    }

    public static let attentionMoods: Set<Mood> = [.waiting, .done, .error]

    public static func decide(_ t: SessionChange, settings: Settings, hostIsFrontmost: Bool) -> Alert? {
        guard !t.removed, !settings.quiet, !hostIsFrontmost else { return nil }
        let mood = t.session.mood
        guard attentionMoods.contains(mood), mood != t.previousMood else { return nil }
        if mood == .done, (t.session.turnDuration ?? 0) < settings.doneThreshold { return nil }
        guard settings.notifications || settings.sounds else { return nil }
        return Alert(mood: mood, notify: settings.notifications, sound: settings.sounds)
    }
}

/// What the notch island shows.
public enum IslandPolicy {
    /// The session the collapsed island represents.
    public static func primary(_ sessions: [Session]) -> Session? {
        sessions.first { $0.mood != .idle }
    }

    public static func isVisible(_ sessions: [Session], showWhileWorking: Bool) -> Bool {
        guard let primary = primary(sessions) else { return false }
        return primary.mood != .working || showWhileWorking
    }

    /// How long the island opens up to announce a transition, or nil to stay collapsed.
    public static func bloomDuration(for t: SessionChange, quiet: Bool) -> TimeInterval? {
        guard !quiet, !t.removed, t.session.mood != t.previousMood else { return nil }
        switch t.session.mood {
        case .waiting: return 8
        case .done, .error: return 5
        case .working, .idle: return nil
        }
    }
}

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
}

public enum Palette {
    public static let claude = RGB(hex: "#D97757")
    public static let codex = RGB(hex: "#10A37F")
    public static let gemini = RGB(hex: "#4F8DF7")
    public static let waiting = RGB(hex: "#F5A524")
    public static let done = RGB(hex: "#3FB950")
    public static let error = RGB(hex: "#F85149")
    public static let idle = RGB(hex: "#8B949E")

    public static func agent(_ a: AgentKind) -> RGB {
        switch a {
        case .claude: claude
        case .codex: codex
        case .gemini: gemini
        }
    }

    public static func mood(_ m: Mood, agent: AgentKind) -> RGB {
        switch m {
        case .working: Self.agent(agent)
        case .waiting: waiting
        case .done: done
        case .error: error
        case .idle: idle
        }
    }
}

/// How the Dock glow looks for a mood.
public struct GlowStyle: Equatable, Sendable {
    public let color: RGB
    public let low: Double
    public let high: Double
    /// Seconds per breath; nil holds steady.
    public let period: Double?

    public static func `for`(mood: Mood, agent: AgentKind) -> GlowStyle? {
        let color = Palette.mood(mood, agent: agent)
        switch mood {
        case .idle: return nil
        case .working: return GlowStyle(color: color, low: 0.35, high: 0.8, period: 3.2)
        case .waiting: return GlowStyle(color: color, low: 0.3, high: 1.0, period: 1.2)
        case .done: return GlowStyle(color: color, low: 0.75, high: 0.75, period: nil)
        case .error: return GlowStyle(color: color, low: 0.6, high: 0.6, period: nil)
        }
    }
}
