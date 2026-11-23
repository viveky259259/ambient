import AmbientCore
import AppKit

/// A small window to type a note for another Mac. Plain text only: the other Mac shows it as written.
enum NoteComposer {
    /// The note, or nil when it was cancelled or left empty.
    static func compose(to label: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Note for \(label)"
        alert.informativeText = "It shows under the notch there, ready to copy."
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 340, height: 140)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        guard let text = scroll.documentView as? NSTextView else { return nil }
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = text

        // A menu bar app isn't active, and the window would open behind the one in front.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return VoiceLine.noteText(text.string)
    }
}
