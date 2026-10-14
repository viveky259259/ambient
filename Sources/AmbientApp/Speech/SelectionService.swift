import AppKit

/// "Speak with Ambient" in every app's Services menu, and the shortcut macOS gives it. macOS hands us the
/// selection on a pasteboard, so this route needs no Accessibility permission.
final class SelectionService: NSObject {
    private let onText: (String?) -> Void

    init(onText: @escaping (String?) -> Void) {
        self.onText = onText
    }

    func register() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Named by `NSMessage` in Info.plist.
    @objc func speakWithAmbient(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string)
        DispatchQueue.main.async { self.onText(text) }
    }
}
