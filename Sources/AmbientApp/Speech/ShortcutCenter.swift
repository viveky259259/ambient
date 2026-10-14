import AmbientCore
import Combine
import Foundation

/// Owns the read-aloud shortcut: which one is in effect, registering it, and re-registering when you change it.
/// Used from the main thread.
final class ShortcutCenter: ObservableObject {
    /// The shortcut in effect.
    @Published private(set) var shortcut: Shortcut
    /// Why the shortcut isn't working, or why the default isn't ⌥⎋; nil when all is well.
    @Published private(set) var note: String?
    /// True once the shortcut has been pressed; the island's hint stops then.
    var onPress: () -> Void = {}

    private let prefs: Preferences
    private var hotKey: HotKey?

    init(prefs: Preferences) {
        self.prefs = prefs
        shortcut = Self.chosen(prefs) ?? Self.systemDefault
    }

    /// ⌥⎋, or ⌃⌥S when macOS's own Speak Selection key is turned on (it uses ⌥⎋).
    static var systemDefault: Shortcut {
        let on = CFPreferencesCopyAppValue("SpokenUIUseSpeakingHotKeyFlag" as CFString,
                                           "com.apple.speech.synthesis.general.prefs" as CFString) as? Bool ?? false
        return Shortcut.default(systemSpeakSelectionOn: on)
    }

    private static func chosen(_ prefs: Preferences) -> Shortcut? {
        prefs.speechShortcut.flatMap(Shortcut.init(stored:))
    }

    func start() {
        register()
    }

    /// Saves and registers `new`; nil goes back to the default.
    func set(_ new: Shortcut?) {
        prefs.speechShortcut = new?.stored
        shortcut = new ?? Self.systemDefault
        register()
    }

    /// While the recorder listens, the shortcut is let go so pressing it again can be recorded.
    func pause() {
        hotKey = nil
    }

    func resume() {
        register()
    }

    var isDefault: Bool { prefs.speechShortcut == nil }

    private func register() {
        hotKey = nil
        hotKey = HotKey(shortcut) { [weak self] in self?.onPress() }
        if hotKey == nil {
            note = "\(shortcut.display) is used by another app. Pick another shortcut."
        } else if isDefault, shortcut == .controlOptionS {
            note = "macOS Speak Selection already uses ⌥⎋, so Ambient uses ⌃⌥S."
        } else {
            note = nil
        }
    }
}
