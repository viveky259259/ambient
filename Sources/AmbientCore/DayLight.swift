import Foundation

/// The four looks a scene takes through the day.
public enum DayPhase: String, CaseIterable, Sendable {
    case night, dawn, day, dusk
}

/// Where the day is: the phase the scene is in, the one it's turning into, and how far along.
public struct DayLight: Equatable, Sendable {
    public let from: DayPhase
    public let to: DayPhase
    /// 0 is all `from`, 1 is all `to`.
    public let blend: Double

    public init(from: DayPhase, to: DayPhase, blend: Double) {
        self.from = from
        self.to = to
        self.blend = blend
    }

    public var dominant: DayPhase { blend < 0.5 ? from : to }

    /// Dark text by day; light text at night, dawn and dusk.
    public var darkInk: Bool { dominant == .day }

    public func color(_ table: (DayPhase) -> RGB) -> RGB { table(from).mixed(with: table(to), blend) }

    public func amount(_ table: (DayPhase) -> Double) -> Double {
        table(from) + (table(to) - table(from)) * blend
    }

    /// Minutes after local midnight where the look changes. Between two keys of different phases the
    /// scene blends: night → dawn 05:00–06:00, dawn → day 06:30–07:30, day → dusk 17:30–18:30,
    /// dusk → night 20:00–21:00.
    static let keys: [(minute: Double, phase: DayPhase)] = [
        (0, .night), (300, .night), (360, .dawn), (390, .dawn), (450, .day),
        (1_050, .day), (1_110, .dusk), (1_200, .dusk), (1_260, .night), (1_440, .night),
    ]

    /// The light at a wall-clock time. Reads the hour and minute, so daylight-saving days keep to schedule.
    public static func at(_ date: Date, calendar: Calendar = .current) -> DayLight {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
        for (a, b) in zip(keys, keys.dropFirst()) where minute >= a.minute && minute < b.minute {
            guard a.phase != b.phase else { return DayLight(from: a.phase, to: a.phase, blend: 0) }
            return DayLight(from: a.phase, to: b.phase, blend: (minute - a.minute) / (b.minute - a.minute))
        }
        return DayLight(from: .night, to: .night, blend: 0)
    }
}

/// Whether the scene's light follows the clock, follows macOS's appearance, or stays light or dark.
public enum SceneLook: String, CaseIterable, Sendable {
    case timeOfDay, system, light, dark

    public var displayName: String {
        switch self {
        case .timeOfDay: "Follow the time of day"
        case .system: "Match macOS"
        case .light: "Always light"
        case .dark: "Always dark"
        }
    }

    /// The light to draw at `date`: the day's own, or held at midday (light) or night (dark).
    public func light(at date: Date, systemDark: Bool, calendar: Calendar = .current) -> DayLight {
        switch self {
        case .timeOfDay: DayLight.at(date, calendar: calendar)
        case .system: systemDark ? .steady(.night) : .steady(.day)
        case .light: .steady(.day)
        case .dark: .steady(.night)
        }
    }
}

extension DayLight {
    /// One phase, not turning into another.
    public static func steady(_ phase: DayPhase) -> DayLight { DayLight(from: phase, to: phase, blend: 0) }
}
