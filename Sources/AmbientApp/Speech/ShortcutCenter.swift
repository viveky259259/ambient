import AmbientCore
import Combine
import Foundation

/// Owns one shortcut: which one is in effect, registering it, and re-registering when you change it. The read-aloud
/// shortcut by default; voice sync has its own. Used from the main thread.
final class ShortcutCenter: ObservableObject {
    /// The shortcut in effect.
    @Published private(set) var shortcut: Shortcut
    /// Why the shortcut isn't working, or why the default isn't ⌥⎋; nil when all is well.
    @Published private(set) var note: String?
    /// True once the shortcut has been pressed; the island's hint stops then.
    var onPress: () -> Void = {}

    private let prefs: Preferences
    private let key: ReferenceWritableKeyPath<Preferences, String?>
    private let fallback: () -> Shortcut
    private var hotKey: HotKey?

    /// The read-aloud shortcut.
    convenience init(prefs: Preferences) {
        self.init(prefs: prefs, key: \.speechShortcut, fallback: { ShortcutCenter.systemDefault })
    }

    /// A shortcut saved at `key`, which is `fallback()` until one is chosen.
    init(prefs: Preferences, key: ReferenceWritableKeyPath<Preferences, String?>, fallback: @escaping () -> Shortcut) {
        self.prefs = prefs
        self.key = key
        self.fallback = fallback
        shortcut = prefs[keyPath: key].flatMap(Shortcut.init(stored:)) ?? fallback()
    }

    /// What Delete in the recorder goes back to.
    var defaultShortcut: Shortcut { fallback() }

    /// ⌥⎋, or ⌃⌥S when macOS's own Speak Selection key is turned on (it uses ⌥⎋).
    static var systemDefault: Shortcut {
        let on = CFPreferencesCopyAppValue("SpokenUIUseSpeakingHotKeyFlag" as CFString,
                                           "com.apple.speech.synthesis.general.prefs" as CFString) as? Bool ?? false
        return Shortcut.default(systemSpeakSelectionOn: on)
    }

    func start() {
        register()
    }

    /// Saves and registers `new`; nil goes back to the default.
    func set(_ new: Shortcut?) {
        prefs[keyPath: key] = new?.stored
        shortcut = new ?? fallback()
        register()
    }

    /// While the recorder listens, the shortcut is let go so pressing it again can be recorded.
    func pause() {
        hotKey = nil
    }

    func resume() {
        register()
    }

    var isDefault: Bool { prefs[keyPath: key] == nil }

    private func register() {
        hotKey = nil
        hotKey = HotKey(shortcut) { [weak self] in self?.onPress() }
        if hotKey == nil {
            note = "\(shortcut.display) is used by another app. Pick another shortcut."
        } else if isDefault, key == \Preferences.speechShortcut, shortcut == .controlOptionS {
            note = "macOS Speak Selection already uses ⌥⎋, so Ambient uses ⌃⌥S."
        } else {
            note = nil
        }
    }
}
