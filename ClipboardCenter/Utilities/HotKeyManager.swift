import Carbon
import Foundation

// MARK: - HotKeyManager
// Manages global keyboard shortcut registration using the Carbon Event API.
// Carbon's RegisterEventHotKey is the standard way to register system-wide
// hotkeys on macOS without requiring external dependencies.
//
// IMPORTANT: This requires Accessibility permissions on macOS.
// The user will be prompted by the system on first use.

final class HotKeyManager {

    // MARK: - Properties

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// The callback invoked when the hotkey is triggered.
    /// Stored as a static to survive the C-function callback bridge.
    private static var callback: (() -> Void)?

    /// Unique hotkey identifier
    private let hotKeyID = EventHotKeyID(
        signature: OSType(0x434C_4950), // "CLIP" in hex
        id: 1
    )

    // MARK: - Registration

    /// Registers a global hotkey with the given key code and modifier flags.
    ///
    /// - Parameters:
    ///   - keyCode: The Carbon virtual key code (e.g., `kVK_ANSI_V` = 9)
    ///   - modifiers: Carbon modifier flags (e.g., `cmdKey | shiftKey`)
    ///   - handler: Closure called when the hotkey is triggered
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKeyManager.callback = handler

        // Install an event handler for the hot key pressed event
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The C callback bridges to our static Swift callback
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                HotKeyManager.callback?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            print("HotKeyManager: Failed to install event handler (status: \(status))")
            return
        }

        // Register the actual hotkey combination
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("HotKeyManager: Failed to register hotkey (status: \(registerStatus))")
        }
    }

    // MARK: - Unregistration

    /// Unregisters the global hotkey. Called on app termination.
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        HotKeyManager.callback = nil
    }

    deinit {
        unregister()
    }
}
