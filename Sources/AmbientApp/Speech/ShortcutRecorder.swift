import AmbientCore
import AppKit
import SwiftUI

/// Shows the read-aloud shortcut; click it and press keys to change it. Esc cancels, Delete puts the default back.
struct ShortcutRecorder: View {
    @ObservedObject var center: ShortcutCenter
    @State private var recording = false
    @State private var problem: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Text(recording ? "Type a shortcut…" : center.shortcut.display)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(minWidth: 110)
                }
                .buttonStyle(.pill)
                .accessibilityLabel(recording ? "Recording shortcut. Press keys, or Escape to cancel."
                                              : "Read-aloud shortcut, \(center.shortcut.display). Change")
                if !center.isDefault, !recording {
                    Button("Reset") { center.set(nil) }.buttonStyle(.pill)
                }
            }
            if let message = problem ?? (recording ? "Esc cancels · Delete restores ⌥⎋" : center.note) {
                Text(message).font(.caption).foregroundStyle(problem != nil || center.note != nil ? .orange : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        problem = nil
        recording = true
        center.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        center.resume()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let keyCode = UInt32(event.keyCode)
        if modifiers.isEmpty, keyCode == 53 { stop(); return }          // Esc: cancel
        if modifiers.isEmpty, keyCode == 51 || keyCode == 117 {           // Delete: default
            stop()
            center.set(nil)
            return
        }
        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers,
                                key: Shortcut.keyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers ?? ""))
        if let issue = shortcut.problem {
            problem = issue.message
            return
        }
        problem = nil
        stop()
        center.set(shortcut)
    }
}
