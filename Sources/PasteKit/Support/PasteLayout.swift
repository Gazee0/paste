import Foundation

/// Fixed geometry shared by the window controller and the SwiftUI view.
enum PasteLayout {
    /// Width of the history column; the preview adds to the right of it.
    static let historyWidth: CGFloat = 560
    static let previewWidth: CGFloat = 284
    static let tabBarHeight: CGFloat = 36
    static let topBarHeight: CGFloat = 48
    static let footerHeight: CGFloat = 40
    static let quickFolderSidebarWidth: CGFloat = 148
    static let cornerRadius: CGFloat = 12

    static let collapsedSize = CGSize(width: historyWidth, height: 456)
    static let expandedSize = CGSize(width: historyWidth + previewWidth, height: 540)
}

enum AppStorageKey {
    static let windowPinned = "paste.windowPinned"
    static let panelTopLeftX = "paste.panelTopLeftX"
    static let panelTopLeftY = "paste.panelTopLeftY"
}
