import AppKit
import SwiftUI

/// A borderless, keyable panel. It behaves like a clipboard palette rather than a document
/// window: no title bar, no main-window role, but it can take keyboard focus for the search
/// field.
final class PastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        // The global key monitor handles Escape, but AppKit may route cancelOperation first
        // when the field editor has focus. Keeping this a no-op avoids a beep; the monitor
        // still sees the key event.
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: PastePanel

    private let model: AppModel
    private var keyObserver: NSObjectProtocol?
    private var isExpanded = false

    init(model: AppModel) {
        self.model = model
        self.panel = PastePanel(
            contentRect: NSRect(origin: .zero, size: PasteLayout.collapsedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = !model.isWindowPinned
        panel.level = model.isWindowPinned ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Do not let a drag anywhere in the palette move the window. Moving is handled by the
        // explicit 7pt handle at the top edge; the rest of the surface — especially preview
        // text — belongs to selection and scrolling.
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingView(rootView: RootView(model: model))
        host.frame = NSRect(origin: .zero, size: PasteLayout.collapsedSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        model.onPreviewChanged = { [weak self] open in
            self?.setExpanded(open)
        }
        model.onPinChanged = { [weak self] pinned in
            self?.applyPin(pinned)
        }
        model.onHideRequested = { [weak self] in
            self?.hide()
        }

        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.panelDidBecomeKey()
            }
        }
    }

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }

    // MARK: - Visibility

    func present(prepare: Bool) {
        if prepare {
            model.prepareForPresentation()
        }
        normalizeWindowSizeForCurrentMode()
        if !hasSavedPosition {
            centerOnMainScreen()
        } else {
            restorePosition()
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.panelDidBecomeKey()
    }

    func toggle() {
        if panel.isVisible && NSApp.isActive {
            hide()
        } else if panel.isVisible {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            model.panelDidBecomeKey()
        } else {
            present(prepare: true)
        }
    }

    func hide() {
        persistPosition()
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    func persistNow() {
        persistPosition()
    }

    // MARK: - Size and position

    /// Slow enough to read as a deliberate window transition instead of a jump.
    private static let previewResizeDuration: TimeInterval = 0.5

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        let size = expanded ? PasteLayout.expandedSize : PasteLayout.collapsedSize
        var frame = panel.frame
        // Grow/shrink around the window center instead of pinning the left edge. This keeps the
        // motion balanced and avoids the “everything is being pushed to the right” feeling.
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin = NSPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        frame = constrained(frame)

        let transitionGeneration = model.beginPreviewWindowTransition()

        guard panel.isVisible else {
            panel.setFrame(frame, display: false)
            persistPosition()
            model.finishPreviewWindowTransition(generation: transitionGeneration)
            if !expanded {
                model.finishPreviewCollapse()
            }
            return
        }

        // Let SwiftUI lay out/display the new preview state before the window frame starts
        // moving. Without this, the first animation frame can be drawn with the previous
        // content size, which flashes as a missing strip on the left.
        let targetFrame = frame
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isExpanded == expanded else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.previewResizeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isExpanded == expanded else { return }
                    // NSWindow's animator can report completion on a frame where the backing
                    // content has not quite caught up with the final frame. Commit the exact
                    // target and flush the view tree before releasing hover/layout state; this
                    // removes the tiny "pause then grow again" at the end of the transition.
                    self.panel.setFrame(targetFrame, display: true)
                    self.panel.contentView?.layoutSubtreeIfNeeded()
                    self.panel.displayIfNeeded()

                    // Let that final frame render before changing SwiftUI state (which unlocks
                    // hover and, on close, removes the preview column).
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isExpanded == expanded else { return }
                        self.model.finishPreviewWindowTransition(generation: transitionGeneration)
                        if !expanded {
                            self.model.finishPreviewCollapse()
                        }
                        self.persistPosition()
                    }
                }
            }
        }
    }

    /// The preview is always closed when the palette is presented, so make sure a frame restored
    /// by macOS from an expanded session cannot leave the history column with a blank right side.
    private func normalizeWindowSizeForCurrentMode() {
        guard !isExpanded else { return }
        let target = PasteLayout.collapsedSize
        guard abs(panel.frame.width - target.width) > 0.5 ||
              abs(panel.frame.height - target.height) > 0.5 else { return }

        var frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = target
        frame.origin = NSPoint(
            x: center.x - target.width / 2,
            y: center.y - target.height / 2
        )
        panel.setFrame(constrained(frame), display: false)
    }

    private func constrained(_ frame: NSRect) -> NSRect {
        guard let screen = panel.screen ?? NSScreen.main else { return frame }
        let visible = screen.visibleFrame
        var result = frame
        if result.width > visible.width {
            result.size.width = visible.width
        }
        if result.height > visible.height {
            result.size.height = visible.height
        }
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private func centerOnMainScreen() {
        let size = panel.frame.size
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        let frame = constrained(NSRect(origin: origin, size: size))
        panel.setFrame(frame, display: false)
    }

    private func applyPin(_ pinned: Bool) {
        panel.level = pinned ? .floating : .normal
        panel.hidesOnDeactivate = !pinned
        if pinned {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Persisted top-left

    private var hasSavedPosition: Bool {
        UserDefaults.standard.object(forKey: AppStorageKey.panelTopLeftX) != nil
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        let x = defaults.double(forKey: AppStorageKey.panelTopLeftX)
        let y = defaults.double(forKey: AppStorageKey.panelTopLeftY)
        let size = panel.frame.size
        var frame = NSRect(x: x, y: y - size.height, width: size.width, height: size.height)
        frame = constrained(frame)
        panel.setFrame(frame, display: false)
    }

    private func persistPosition() {
        let defaults = UserDefaults.standard
        defaults.set(panel.frame.minX, forKey: AppStorageKey.panelTopLeftX)
        defaults.set(panel.frame.maxY, forKey: AppStorageKey.panelTopLeftY)
    }

    func windowDidMove(_ notification: Notification) {
        persistPosition()
    }

    func windowDidResignKey(_ notification: Notification) {
        persistPosition()
    }
}
