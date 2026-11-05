import AppKit
import SwiftUI

/// The read-only text view used by `SelectableTextView`; the keyboard router uses this type to
/// let native text selection keep its arrow keys and copy shortcuts.
final class PreviewTextView: NSTextView {}

/// Read-only, selectable text surface for the preview pane.
///
/// SwiftUI's `Text` selection can be awkward while another control (the search field) owns the
/// first responder. An `NSTextView` gives us native drag selection, `⌘C`, and the standard
/// context menu without turning the preview into an editable field.
struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false

        let textView = PreviewTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.allowsUndo = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.setText(text)
        DispatchQueue.main.async {
            context.coordinator.layout()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.setText(text)
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        DispatchQueue.main.async {
            context.coordinator.layout()
        }
    }

    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?

        private static let paragraphStyle: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return style
        }()

        @MainActor
        func setText(_ text: String) {
            guard let textView else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: Self.paragraphStyle,
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        }

        @MainActor
        func layout() {
            guard let scrollView, let textView,
                  let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            let width = max(1, scrollView.contentSize.width)
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            textView.frame = NSRect(
                origin: .zero,
                size: NSSize(width: width, height: max(1, scrollView.contentSize.height))
            )
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let contentHeight = used.height + textView.textContainerInset.height * 2
            textView.frame = NSRect(
                origin: .zero,
                size: NSSize(
                    width: width,
                    height: max(contentHeight, scrollView.contentSize.height)
                )
            )
        }
    }
}
