import AmbientCore
import Carbon

/// A system-wide shortcut through Carbon's hotkey API, which needs no permission to register. Each one has its own id,
/// and its handler passes on presses of any other, so several can be registered at once.
final class HotKey {
    private static let signature = OSType(0x414D_4253) // "AMBS"
    private static var nextID: UInt32 = 1

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            guard read == noErr, pressed.signature == HotKey.signature, pressed.id == hotKey.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Nil when macOS won't register it, usually because another app already has it.
    convenience init?(_ shortcut: Shortcut, action: @escaping () -> Void) {
        var carbon = 0
        if shortcut.modifiers.contains(.control) { carbon |= controlKey }
        if shortcut.modifiers.contains(.option) { carbon |= optionKey }
        if shortcut.modifiers.contains(.shift) { carbon |= shiftKey }
        if shortcut.modifiers.contains(.command) { carbon |= cmdKey }
        self.init(keyCode: shortcut.keyCode, modifiers: UInt32(carbon), action: action)
    }
}
