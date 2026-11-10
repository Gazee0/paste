import AppKit
import Carbon.HIToolbox

/// The one global shortcut: ⌥V, registered with Carbon so it works while another app is
/// frontmost and without any Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isPressed = false
    private var lastPressTime: CFTimeInterval = 0
    private var releaseFallback: DispatchWorkItem?
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
        resetPressState()
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    /// Carbon normally sends a release event for every press. If the release is lost while
    /// switching apps/spaces, the old boolean guard would reject every later press forever.
    /// A timestamp-based debounce plus this reset keeps the shortcut recoverable.
    func resetPressState() {
        isPressed = false
        lastPressTime = 0
        releaseFallback?.cancel()
        releaseFallback = nil
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
            let now = CACurrentMediaTime()
            if isPressed, now - lastPressTime < 0.5 { return noErr }
            isPressed = true
            lastPressTime = now
            action?()

            // If the release event is lost (for example when app/space activation changes),
            // clear the pressed state shortly after rather than leaving the shortcut dead.
            releaseFallback?.cancel()
            let fallback = DispatchWorkItem { [weak self] in
                self?.isPressed = false
            }
            releaseFallback = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: fallback)
        case UInt32(kEventHotKeyReleased):
            isPressed = false
            releaseFallback?.cancel()
            releaseFallback = nil
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
