import AmbientCore
import AppKit

/// The window a note is written in: a plain-text box you can type or paste into, the Mac it goes to, and Send. Ambient
/// is a menu bar app with no Edit menu, which is what normally carries ⌘V and the other editing shortcuts to a text
/// box, so this window carries them itself. Main thread only.
final class NoteComposer: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private let window: NoteWindow
    private let text = NSTextView()
    private let picker = NSPopUpButton()
    private let count = NSTextField(labelWithString: "")
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let destinations: [VoiceDestination]
    private let onSend: (String, VoiceDestination) -> Void
    private let onClose: () -> Void

    init(destinations: [VoiceDestination], chosen: VoiceDestination,
         onSend: @escaping (String, VoiceDestination) -> Void, onClose: @escaping () -> Void) {
        self.destinations = destinations.contains(chosen) ? destinations : [chosen] + destinations
        self.onSend = onSend
        self.onClose = onClose
        window = NoteWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        build(chosen: chosen)
    }

    /// Brings the window to the front, with the cursor in the box.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
    }

    private var destination: VoiceDestination {
        destinations.indices.contains(picker.indexOfSelectedItem) ? destinations[picker.indexOfSelectedItem] : destinations[0]
    }

    private func build(chosen: VoiceDestination) {
        window.title = "New Note"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 360, height: 220)
        window.delegate = self
        window.center()

        let to = NSTextField(labelWithString: "To")
        for d in destinations { picker.addItem(withTitle: d.isOnline() ? d.label : "\(d.label) (away)") }
        picker.selectItem(at: destinations.firstIndex(of: chosen) ?? 0)
        let hint = NSTextField(labelWithString: "Type or paste. ⌘↩ sends.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let top = NSStackView(views: [to, picker, NSView(), hint])
        top.orientation = .horizontal
        top.spacing = 8

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.delegate = self
        scroll.documentView = text

        let paste = NSButton(title: "Paste", target: self, action: #selector(pasteClipboard))
        paste.toolTip = "Paste what's on the clipboard (⌘V)"
        count.textColor = .secondaryLabelColor
        count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = .command
        sendButton.bezelColor = .controlAccentColor
        let bottom = NSStackView(views: [paste, count, NSView(), cancel, sendButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8

        let stack = NSStackView(views: [top, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in [top, scroll, bottom] { row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        refresh()
    }

    /// The count and whether there's anything to send, as the text changes.
    private func refresh() {
        let n = text.string.count
        count.stringValue = n == 0 ? "" : "\(n.formatted()) / \(VoiceLine.maxText.formatted())"
        count.textColor = n > VoiceLine.maxText ? .systemOrange : .secondaryLabelColor
        sendButton.isEnabled = VoiceLine.noteText(text.string) != nil
    }

    func textDidChange(_ notification: Notification) { refresh() }

    /// Escape in the box closes the window, rather than offering completions.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancel()
        return true
    }

    @objc private func pasteClipboard() {
        window.makeFirstResponder(text)
        text.pasteAsPlainText(nil)
    }

    @objc private func send() {
        guard let note = VoiceLine.noteText(text.string) else { return }
        let to = destination
        window.close()
        onSend(note, to)
    }

    @objc private func cancel() { window.close() }

    func windowWillClose(_ notification: Notification) { onClose() }
}

/// Gives the window the editing shortcuts an app's Edit menu would.
private final class NoteWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased() {
            let shift = flags.contains(.shift)
            let action: Selector? = switch (key, shift) {
            case ("x", false): #selector(NSText.cut(_:))
            case ("c", false): #selector(NSText.copy(_:))
            case ("v", false): #selector(NSTextView.pasteAsPlainText(_:))
            case ("a", false): #selector(NSText.selectAll(_:))
            case ("z", false): Selector(("undo:"))
            case ("z", true): Selector(("redo:"))
            case ("w", false): #selector(NSWindow.performClose(_:))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
