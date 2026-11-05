import AppKit
import SwiftUI

/// One clipboard history row.
///
/// The row is `Equatable` so a hover change on one row does not force every other row to
/// re-render. The action closures are intentionally ignored by equality: they always target
/// the same item identity.
struct HistoryRowView: View, Equatable {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isSelected: Bool
    let isMultiSelecting: Bool
    let isInteractionLocked: Bool
    let isChecked: Bool
    let shortcutIndex: Int?
    let timeText: String
    let showsSeparator: Bool

    let onHover: () -> Void
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var lastClickDate = Date.distantPast

    init(
        item: ClipboardItem,
        thumbnail: NSImage?,
        isSelected: Bool,
        isMultiSelecting: Bool,
        isInteractionLocked: Bool,
        isChecked: Bool,
        shortcutIndex: Int?,
        timeText: String,
        showsSeparator: Bool,
        onHover: @escaping () -> Void,
        onClick: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.thumbnail = thumbnail
        self.isSelected = isSelected
        self.isMultiSelecting = isMultiSelecting
        self.isInteractionLocked = isInteractionLocked
        self.isChecked = isChecked
        self.shortcutIndex = shortcutIndex
        self.timeText = timeText
        self.showsSeparator = showsSeparator
        self.onHover = onHover
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        self.onCopy = onCopy
        self.onPaste = onPaste
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }

    static func == (lhs: HistoryRowView, rhs: HistoryRowView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.displayText == rhs.item.displayText
            && lhs.item.isPinned == rhs.item.isPinned
            && (lhs.thumbnail != nil) == (rhs.thumbnail != nil)
            && lhs.isSelected == rhs.isSelected
            && lhs.isMultiSelecting == rhs.isMultiSelecting
            && lhs.isInteractionLocked == rhs.isInteractionLocked
            && lhs.isChecked == rhs.isChecked
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.timeText == rhs.timeText
            && lhs.showsSeparator == rhs.showsSeparator
    }

    var body: some View {
        VStack(spacing: 0) {
            rowContent
                .padding(.horizontal, PasteMetrics.listInset)
                .onHover { hovering in
                    guard !isInteractionLocked else {
                        isHovered = false
                        return
                    }
                    if hovering != isHovered {
                        isHovered = hovering
                    }
                    if hovering {
                        onHover()
                    }
                }
                .onChange(of: isInteractionLocked) { _, locked in
                    if locked {
                        isHovered = false
                    }
                }
                .onTapGesture(perform: handleTap)
                .contextMenu { contextMenu }

            if showsSeparator {
                Rectangle()
                    .fill(PasteTheme.separator)
                    .frame(height: 1)
                    .padding(.leading, 44)
                    .padding(.trailing, 12)
            }
        }
    }

    // MARK: - Row

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingAccessory
            if item.kind == .image, let thumbnail {
                imageThumbnail(thumbnail)
            }
            textContent
            Spacer(minLength: 6)
            metaStack
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(minHeight: PasteMetrics.rowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: PasteMetrics.rowCornerRadius, style: .continuous)
                .fill(rowFill)
        )
        .overlay {
            if isMultiSelecting && isChecked {
                RoundedRectangle(cornerRadius: PasteMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: PasteMetrics.rowCornerRadius, style: .continuous))
    }

    /// A copied screenshot reads as a picture, not a filename. The thumbnail is deliberately
    /// small so rows stay scannable, but tall enough to recognise what was captured.
    private func imageThumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 112, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .accessibilityLabel("图片缩略图")
    }

    private var rowFill: Color {
        if isMultiSelecting && isChecked { return PasteTheme.checkedRow }
        if isSelected { return PasteTheme.rowHighlight }
        if isHovered && !isInteractionLocked { return PasteTheme.rowHighlight }
        return .clear
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if isMultiSelecting {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: PasteMetrics.iconTileSize, height: PasteMetrics.iconTileSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: PasteMetrics.iconTileCornerRadius, style: .continuous)
                    .fill(PasteTheme.tint(for: item.kind).opacity(0.13))
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PasteTheme.tint(for: item.kind))
            }
            .frame(width: PasteMetrics.iconTileSize, height: PasteMetrics.iconTileSize)
        }
    }

    private var textContent: some View {
        Text(item.displayText)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .lineSpacing(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metaStack: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 3) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let shortcutIndex {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .padding(.trailing, 2)
    }

    // MARK: - Interaction

    private func handleTap() {
        let now = Date()
        let isDoubleTap = now.timeIntervalSince(lastClickDate) < 0.5
        lastClickDate = now

        if isDoubleTap {
            guard !isMultiSelecting else { return }
            onDoubleClick()
        } else {
            onClick()
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("拷贝") { onCopy() }
        Button("粘贴") { onPaste() }
        Button(item.isPinned ? "取消固定" : "固定项目") { onTogglePin() }
        Divider()
        Button("删除", role: .destructive) { onDelete() }
    }
}
