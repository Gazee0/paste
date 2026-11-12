import AppKit

/// The menu-bar extra. Left click opens/closes the palette, right click shows a small menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onOpen: () -> Void
    private let onSettings: () -> Void
    private let onAccessibility: () -> Void
    private let onQuit: () -> Void

    init(
        onOpen: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onAccessibility: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.onAccessibility = onAccessibility
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Paste · ⌥V"
        }

        menu.delegate = self
        let openItem = NSMenuItem(title: "打开 Paste", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let accessItem = NSMenuItem(title: "辅助功能设置…", action: #selector(openAccessibility), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Paste", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onOpen()
        }
    }

    @objc private func openPanel() {
        onOpen()
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func openAccessibility() {
        onAccessibility()
    }

    @objc private func quit() {
        onQuit()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}
