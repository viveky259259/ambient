import Carbon

/// A system-wide shortcut through Carbon's hotkey API, which needs no permission to register.
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x414D_4253), id: 1)  // "AMBS"
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// ⌃⌥⌘S.
    static func speakSelection(_ action: @escaping () -> Void) -> HotKey? {
        HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), action: action)
    }
}
