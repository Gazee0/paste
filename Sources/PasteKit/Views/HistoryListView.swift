import SwiftUI

/// Small "最近" header above the history list.
struct HistoryListHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("最近")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// Scrollable list of clips.
///
/// Hovering a row selects it so the preview follows the pointer; keyboard navigation bumps
/// `keyboardScrollNonce`, which scrolls the new selection into view.
struct HistoryListView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if model.filteredItems.isEmpty {
                    EmptyHistoryView(isSearching: model.isSearching && model.hasItems)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    scrollList
                }
            }
            .onChange(of: model.keyboardScrollNonce) { _, _ in
                scrollToSelection(using: proxy)
            }
        }
    }

    // MARK: - List

    private var scrollList: some View {
        let rows = model.filteredItems
        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    rowView(for: item, showsSeparator: index < rows.count - 1)
                }
            }
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowView(for item: ClipboardItem, showsSeparator: Bool) -> some View {
        HistoryRowView(
            item: item,
            thumbnail: item.kind == .image ? model.image(for: item) : nil,
            isSelected: model.isSelected(item.id),
            isMultiSelecting: model.isMultiSelecting,
            isInteractionLocked: model.isEditingPreview,
            isChecked: model.isChecked(item.id),
            shortcutIndex: model.shortcutIndex(for: item),
            timeText: model.timeText(for: item.createdAt),
            showsSeparator: showsSeparator,
            onHover: {
                guard !model.isMultiSelecting,
                      !model.isEditingPreview,
                      !model.isPreviewTransitioning else { return }
                model.select(item)
            },
            onClick: {
                if model.isMultiSelecting {
                    model.toggleChecked(item)
                } else {
                    model.select(item)
                    model.refocusSearch()
                }
            },
            onDoubleClick: {
                guard !model.isMultiSelecting else { return }
                model.paste(item)
            },
            onCopy: { model.copy(item) },
            onPaste: { model.paste(item) },
            onTogglePin: { model.togglePin(item) },
            onDelete: { model.delete(item) }
        )
        .equatable()
    }

    // MARK: - Keyboard scroll

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        guard let selectedID = model.selectedID,
              model.filteredItems.contains(where: { $0.id == selectedID }) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }
}

/// Placeholder for an empty history or a search without matches.
private struct EmptyHistoryView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(isSearching ? "没有找到匹配的内容" : "暂无剪贴板记录")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(isSearching ? "换个关键词试试" : "复制任意内容后会自动出现在这里")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
