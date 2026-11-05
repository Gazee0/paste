import AppKit
import SwiftUI

/// Borderless panel used only by the large image viewer.
private final class ImageViewerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the standalone large-image window.
@MainActor
final class ImagePreviewController: NSObject {
    private let parentPanel: NSPanel
    private let onClose: () -> Void

    private var panel: ImageViewerPanel?
    private var keyMonitor: Any?

    init(parentPanel: NSPanel, onClose: @escaping () -> Void) {
        self.parentPanel = parentPanel
        self.onClose = onClose
        super.init()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func show(item: ClipboardItem, image: NSImage) {
        close(restoringFocus: false)

        let screen = parentPanel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(visible.width * 0.78, 760), 1500)
        let height = min(max(visible.height * 0.78, 520), 940)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )

        let panel = ImageViewerPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let canvasSize = CGSize(
            width: width,
            height: height - LargeImagePreviewView.topBarHeight - LargeImagePreviewView.footerHeight
        )
        let host = NSHostingView(
            rootView: LargeImagePreviewView(
                item: item,
                image: image,
                canvasSize: canvasSize,
                onClose: { [weak self] in self?.close() }
            )
        )
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close(restoringFocus: Bool = true) {
        removeKeyMonitor()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil

        guard restoringFocus else { return }
        NSApp.activate(ignoringOtherApps: true)
        parentPanel.makeKeyAndOrderFront(nil)
        onClose()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad])
            if event.keyCode == 53 || (event.keyCode == 13 && flags == .command) {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}
