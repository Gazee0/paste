import AppKit
import Carbon.HIToolbox

/// The one global shortcut: ⌥V, registered with Carbon so it works while another app is
/// frontmost and without any Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isPressed = false
    private var action: (() -> Void)?

    private static let signature = OSType(0x50415354) // 'PAST'
    private static let identifier: UInt32 = 1

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V),
                  modifiers: UInt32 = UInt32(optionKey),
                  action: @escaping () -> Void) -> Bool {
        self.action = action
        unregister()
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, reference != nil else {
            NSLog("Paste: global shortcut could not be registered (OSStatus \(status))")
            return false
        }
        hotKeyRef = reference
        return true
    }

    func unregister() {
        isPressed = false
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    fileprivate func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &id
        )
        guard status == noErr, id.signature == Self.signature, id.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard !isPressed else { return noErr }
            isPressed = true
            action?()
        case UInt32(kEventHotKeyReleased):
            isPressed = false
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), pasteHotKeyHandler, specs.count, &specs, nil, &handlerRef)
    }
}

private func pasteHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    return MainActor.assumeIsolated {
        GlobalHotKeyCenter.shared.handle(event)
    }
}

/// Small holder so the C callback can reach the one hot key instance without capturing state.
@MainActor
enum GlobalHotKeyCenter {
    static let shared = GlobalHotKey()
}
