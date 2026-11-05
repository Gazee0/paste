import Foundation

/// Freshly captured pasteboard content, before it becomes a stored `ClipboardItem`.
struct ClipboardPayload: Sendable {
    var kind: ClipboardKind
    var text: String?
    var imageData: Data?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var filePaths: [String]
    var rtfData: Data?
    var htmlData: Data?
    var sourceApp: String?
    var byteCount: Int

    init(
        kind: ClipboardKind,
        text: String? = nil,
        imageData: Data? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        filePaths: [String] = [],
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        sourceApp: String? = nil,
        byteCount: Int = 0
    ) {
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.filePaths = filePaths
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.sourceApp = sourceApp
        self.byteCount = byteCount
    }

    var contentHash: String {
        switch kind {
        case .text:
            return ClipboardItem.hash(text: text ?? "")
        case .image:
            return ClipboardItem.hash(imageData: imageData ?? Data())
        case .files:
            return ClipboardItem.hash(filePaths: filePaths)
        }
    }
}

/// A short-lived message shown near the bottom of the panel.
struct ToastMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let actionTitle: String?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}
