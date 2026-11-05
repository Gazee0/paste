import AppKit

/// Writes a stored entry back onto the system pasteboard.
enum PasteboardWriter {
    /// Writes the item and returns the pasteboard change count so the clipboard monitor can
    /// acknowledge the app's own write. Returns nil when nothing could be written.
    @discardableResult
    static func write(
        _ item: ClipboardItem,
        imageData: Data?,
        to pasteboard: NSPasteboard = .general
    ) -> Int? {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(text, forType: .string)
            if let rtf = item.rtfData {
                pasteboardItem.setData(rtf, forType: .rtf)
            }
            if let html = item.htmlData {
                pasteboardItem.setData(html, forType: .html)
            }
            guard pasteboard.writeObjects([pasteboardItem]) else { return nil }

        case .image:
            guard let imageData, !imageData.isEmpty else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(imageData, forType: .png)
            if let image = NSImage(data: imageData), let tiff = image.tiffRepresentation {
                pasteboardItem.setData(tiff, forType: .tiff)
            }
            guard pasteboard.writeObjects([pasteboardItem]) else { return nil }

        case .files:
            let urls = item.fileURLs.map { $0 as NSURL }
            guard !urls.isEmpty else { return nil }
            guard pasteboard.writeObjects(urls) else { return nil }
        }

        return pasteboard.changeCount
    }
}
