import Foundation

/// A point or vector in screen points, origin at the top-left.
public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public var length: Double { (x * x + y * y).squareRoot() }
}

/// Where the island is, on the display the wallpaper draws on, in that display's points (origin top-left).
public struct NotchGeometry: Equatable, Sendable {
    /// Width and height of the display.
    public var screen: Vec2
    public var notchCenterX: Double
    /// The notch's bottom edge: the hole's or sun's diameter lies along it.
    public var notchBottom: Double
    public var notchWidth: Double
    /// The island's menu when open (width, height), hanging from the top centre. It's drawn in front.
    public var menu: Vec2

    public init(screen: Vec2, notchCenterX: Double, notchBottom: Double, notchWidth: Double, menu: Vec2) {
        self.screen = screen
        self.notchCenterX = notchCenterX
        self.notchBottom = notchBottom
        self.notchWidth = notchWidth
        self.menu = menu
    }

    public var center: Vec2 { Vec2(notchCenterX, notchBottom) }
    /// The hole's or sun's full radius: half the notch.
    public var radius: Double { notchWidth / 2 }
    /// 1 on a display 600 points tall; the physics is tuned there and scaled.
    public var unit: Double { screen.y / 600 }

    /// The narrowest notch the effects are drawn for on a display without one, about a MacBook's.
    public static let minimumVirtualEffectWidth = 180.0

    /// The notch width the effects use. Displays without a notch get a narrow virtual one; the hole and the sun are
    /// drawn at least a MacBook notch wide there, so they read the same on a Mac Studio as on a MacBook.
    public static func effectWidth(notch: Double, hasNotch: Bool) -> Double {
        hasNotch ? notch : max(notch, minimumVirtualEffectWidth)
    }
}

/// An agent session taking part in a notch effect.
public struct NotchAgent: Equatable, Sendable {
    public let id: String
    /// Where it rests: its spot in the world.
    public var home: Vec2
    /// Lower is more urgent.
    public var urgency: Int

    public init(id: String, home: Vec2, urgency: Int) {
        self.id = id
        self.home = home
        self.urgency = urgency
    }

    /// Needs you › failed › working › done › idle.
    public static func urgency(of mood: Mood) -> Int {
        switch mood {
        case .waiting: 0
        case .error: 1
        case .working: 2
        case .done: 3
        case .idle: 4
        }
    }
}
