import AppKit
import ApplicationServices
import Carbon
import os

/// The selected text in the frontmost app, through Accessibility, falling back to copying it. Claude's and Codex's
/// chat views don't offer their selection to the Services menu, so this is how the shortcut reads them.
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private static let log = Logger(subsystem: "com.viveky259259.Ambient", category: "speech")

    @MainActor static func selectedText() async -> String? {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        if let text = accessibilitySelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.info("selection: \(text.count) characters from \(app, privacy: .public) via Accessibility")
            return text
        }
        let copied = await copySelection()
        log.info("selection: \(copied?.count ?? 0) characters from \(app, privacy: .public) via copy")
        return copied
    }

    /// Electron apps (Claude, Codex) build their accessibility tree only when asked, through AXManualAccessibility.
    static func accessibilitySelection() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                         "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        // The type check above makes this cast safe.
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    /// Presses ⌘C in the frontmost app, reads what it copied, then puts the clipboard back as it was.
    @MainActor static func copySelection() async -> String? {
        // The shortcut's own modifiers would turn ⌘C into ⌃⌥⌘C; wait for them to be released.
        for _ in 0..<20 where !NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let board = NSPasteboard.general
        let saved: [NSPasteboardItem] = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let before = board.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if board.changeCount != before {
                text = board.string(forType: .string)
                break
            }
        }
        if board.changeCount != before {
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
        return text
    }
}
