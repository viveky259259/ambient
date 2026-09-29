import Foundation

/// The worlds the living wallpaper can show.
public enum SceneKind: String, CaseIterable, Codable, Sendable {
    case sky, harbor, garden, solar

    public var displayName: String {
        switch self {
        case .sky: "Sky"
        case .harbor: "Harbor"
        case .garden: "Garden"
        case .solar: "Solar System"
        }
    }
}

/// What the user picked in Settings: one world, or a new one each day.
public enum SceneChoice: Equatable, Sendable, RawRepresentable {
    case fixed(SceneKind)
    case daily

    public init?(rawValue: String) {
        if rawValue == "daily" {
            self = .daily
        } else if let kind = SceneKind(rawValue: rawValue) {
            self = .fixed(kind)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .daily: "daily"
        case let .fixed(kind): kind.rawValue
        }
    }
}

public enum ScenePolicy {
    /// The world to show: the picked one, or one per day in a fixed order that changes at local midnight.
    public static func kind(for choice: SceneChoice, on date: Date, calendar: Calendar = .current) -> SceneKind {
        switch choice {
        case let .fixed(kind):
            return kind
        case .daily:
            let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            return SceneKind.allCases[day % SceneKind.allCases.count]
        }
    }
}
