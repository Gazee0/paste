import AppKit
import Foundation

/// Polls `NSPasteboard.general` and reports content copied by other apps.
@MainActor
final class ClipboardMonitor {
    /// Called with fresh content whenever the system pasteboard changes.
    var onCapture: ((ClipboardPayload) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    private let pasteboard: NSPasteboard

    func start(interval: TimeInterval = 0.35) {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        // .common keeps polling alive while menus, sheets, or a drag is running.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call immediately after writing the pasteboard ourselves, so an echo is not captured
    /// as a new history item.
    func acknowledgeOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let payload = ClipboardReader.read(from: pasteboard) else { return }
        onCapture?(payload)
    }
}
