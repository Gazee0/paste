import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The one global shortcut: ⌥V, registered with Carbon so it works while another app is
/// frontmost and without any Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isPressed = false
    private var lastPressTime: CFTimeInterval = 0
    private var lastActionTime: CFTimeInterval = 0
    private var releaseFallback: DispatchWorkItem?
    private var globalMonitor: Any?
    private var isRegistered = false
    private var savedKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    private var savedModifiers: UInt32 = UInt32(optionKey)
    private var action: (() -> Void)?

    private static let signature = OSType(0x50415354) // 'PAST'
    private static let identifier: UInt32 = 1

    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V),
                  modifiers: UInt32 = UInt32(optionKey),
                  action: @escaping () -> Void) -> Bool {
        self.action = action
        savedKeyCode = keyCode
        savedModifiers = modifiers
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
        if status == noErr, let reference {
            hotKeyRef = reference
            isRegistered = true
        } else {
            isRegistered = false
            NSLog("Paste: global shortcut could not be registered (OSStatus \(status))")
        }

        // Carbon can occasionally fail or miss an event; when Accessibility is already granted
        // (for auto-paste), a passive global monitor gives the shortcut a second path.
        installGlobalMonitorIfPossible()
        return isRegistered
    }

    func unregister() {
        resetPressState()
        removeGlobalMonitor()
        isRegistered = false
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    func retryRegistrationIfNeeded() {
        guard !isRegistered, let action else { return }
        _ = register(keyCode: savedKeyCode, modifiers: savedModifiers, action: action)
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

    private func triggerFromAnyPath() {
        let now = CACurrentMediaTime()
        // Carbon and the passive monitor can both see the same physical key press.
        guard now - lastActionTime > 0.25 else { return }
        lastActionTime = now
        action?()
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
            triggerFromAnyPath()

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
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            pasteHotKeyHandler,
            specs.count,
            &specs,
            nil,
            &handlerRef
        )
        if status != noErr {
            NSLog("Paste: global shortcut handler could not be installed (OSStatus \(status))")
        }
    }

    private func installGlobalMonitorIfPossible() {
        guard globalMonitor == nil, AXIsProcessTrusted() else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad])
            guard event.keyCode == UInt16(kVK_ANSI_V), flags == .option else { return }
            Task { @MainActor [weak self] in
                self?.triggerFromAnyPath()
            }
        }
    }

    private func removeGlobalMonitor() {
        guard let globalMonitor else { return }
        NSEvent.removeMonitor(globalMonitor)
        self.globalMonitor = nil
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
