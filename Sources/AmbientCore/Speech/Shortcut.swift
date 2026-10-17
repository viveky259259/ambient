import Foundation

/// The read-aloud shortcut: a virtual key code plus modifiers, with the name the key is shown by.
public struct Shortcut: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Why a shortcut can't be used.
    public enum Problem: Equatable, Sendable {
        /// Without ⌃ or ⌥ it would take a key, or an app's ⌘ shortcut, away from every app.
        case needsControlOrOption
        /// ⌥ with a character key types a special character (⌥S is ß); taking it would stop you typing it.
        case typesCharacter

        public var message: String {
            switch self {
            case .needsControlOrOption: "Use ⌃ or ⌥ in the shortcut, so it doesn't take a key from your apps."
            case .typesCharacter: "⌥ with that key types a character. Add ⌃ or ⌘, or pick another key."
            }
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// How the key is shown: "S", "⎋", "F5".
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// ⌥⎋, the key macOS itself uses for speaking a selection.
    public static let optionEscape = Shortcut(keyCode: 53, modifiers: [.option], key: "⎋")
    /// Used instead when macOS's own Speak Selection already has ⌥⎋.
    public static let controlOptionS = Shortcut(keyCode: 1, modifiers: [.control, .option], key: "S")

    public static func `default`(systemSpeakSelectionOn: Bool) -> Shortcut {
        systemSpeakSelectionOn ? .controlOptionS : .optionEscape
    }

    /// Modifier symbols in the order macOS menus use, then the key.
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    public var problem: Problem? {
        if Self.functionKeys[keyCode] != nil { return nil }
        guard !modifiers.isDisjoint(with: [.control, .option]) else { return .needsControlOrOption }
        if modifiers.isDisjoint(with: [.control, .command]), Self.specialKeys[keyCode] == nil || keyCode == 49 {
            return .typesCharacter
        }
        return nil
    }

    /// For preferences.
    public var stored: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }

    public init?(stored: String) {
        guard let s = try? JSONDecoder().decode(Shortcut.self, from: Data(stored.utf8)) else { return nil }
        self = s
    }

    /// The name to show for a key, from its virtual key code, or the characters it types.
    public static func keyName(keyCode: UInt32, characters: String) -> String {
        if let name = functionKeys[keyCode] ?? specialKeys[keyCode] { return name }
        return characters.uppercased()
    }

    static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        90: "F20",
    ]

    /// Keys that don't type a character (except Space, which does).
    static let specialKeys: [UInt32: String] = [
        53: "⎋", 49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}
