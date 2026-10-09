import Carbon.HIToolbox
import SpyreCore

/// Registers the global shortcut with Carbon `RegisterEventHotKey`.
/// This API needs no Accessibility permission, and it never sees other key presses. `SPEC.md` 4.4.
@MainActor
final class GlobalHotkey {
    private let action: () -> Void
    private var hotkey: Hotkey?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// Registers `hotkey`, and removes the old one. Returns a warning when macOS refuses it, else `nil`.
    func register(_ hotkey: Hotkey) -> String? {
        if hotkey == self.hotkey, reference != nil { return nil }
        unregister()
        installHandlerOnce()
        self.hotkey = hotkey
        let id = EventHotKeyID(signature: OSType(0x5350_5952), id: 1)  // "SPYR"
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &reference
        )
        guard status != noErr else { return nil }
        reference = nil
        return hotkey.registrationWarning(status: status)
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }, 1, &type, context, &handler)
    }
}
