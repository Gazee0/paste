import AppKit
import ApplicationServices
import CoreGraphics

enum PasteOutcome: Equatable {
    case pasted
    case noTarget
    case needsPermission
    case notDelivered
    case copyFailed

    var message: String {
        switch self {
        case .pasted: return "已粘贴"
        case .noTarget: return "已拷贝到剪贴板"
        case .needsPermission: return "已拷贝 · 开启辅助功能后可自动粘贴"
        case .notDelivered: return "已拷贝 · 未能切换回目标应用"
        case .copyFailed: return "拷贝失败，请重试"
        }
    }
}

/// Tracks the app the user was in before opening Paste, and delivers ⌘V to it.
///
/// Only the copy half lives here: the caller has already written the pasteboard. Synthetic
/// keystrokes require Accessibility and must be posted after the target app is frontmost, so
/// the sequence hides our panel, activates the remembered app, waits for activation, then
/// posts ⌘V directly to that pid.
@MainActor
enum PasteTarget {
    private static var lastActiveApp: NSRunningApplication?
    private static var observing = false
    private static var hasPromptedForAccessibility = false

    static func startObserving() {
        guard !observing else { return }
        observing = true
        lastActiveApp = externalFrontmostApp()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in
                lastActiveApp = app
            }
        }
    }

    /// The app to paste into. If nothing was remembered, fall back to the app that supplied
    /// the clip's content.
    static func target(rememberedSource: String? = nil) -> NSRunningApplication? {
        if let app = lastActiveApp, !app.isTerminated,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            return app
        }
        if let rememberedSource {
            return NSWorkspace.shared.runningApplications.first {
                $0.localizedName == rememberedSource && !$0.isTerminated
            }
        }
        return externalFrontmostApp()
    }

    /// Returns `.pasted` only when the key event was actually handed to a target app.
    /// `keepWindowVisible` is used for a pinned palette: paste still targets the remembered app,
    /// but the floating panel is not hidden.
    static func paste(rememberedSource: String? = nil, keepWindowVisible: Bool = false) -> PasteOutcome {
        guard let target = target(rememberedSource: rememberedSource) else { return .noTarget }
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            return .needsPermission
        }

        if !keepWindowVisible {
            NSApp.hide(nil)
        }
        target.activate(options: [.activateAllWindows])
        waitUntilFrontmost(target) { frontmost in
            guard frontmost else { return }
            sendCommandV(to: target.processIdentifier)
        }
        return .pasted
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !hasPromptedForAccessibility {
            hasPromptedForAccessibility = true
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func externalFrontmostApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    private static func waitUntilFrontmost(
        _ app: NSRunningApplication,
        attemptsLeft: Int = 40,
        then: @escaping (Bool) -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            then(true)
            return
        }
        guard attemptsLeft > 0, !app.isTerminated else {
            then(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            MainActor.assumeIsolated {
                waitUntilFrontmost(app, attemptsLeft: attemptsLeft - 1, then: then)
            }
        }
    }

    private static func sendCommandV(to pid: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }
}
