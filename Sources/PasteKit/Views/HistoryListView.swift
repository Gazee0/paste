import SwiftUI

/// Compact kind filter above the history list: 全部 / 文本 / 图片 / 文件.
struct HistoryListHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases) { filter in
                let isSelected = model.historyFilter == filter
                Button {
                    model.setHistoryFilter(filter)
                } label: {
                    Text(filter.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("筛选：\(filter.title)（⌘[ / ⌘] 切换）")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.top, 5)
        .padding(.bottom, 4)
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
                    EmptyHistoryView(isFiltering: model.isFiltering && model.hasItems)
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
            // Lazy rows keep a 200-item history from materializing every row (and its image
            // thumbnail) at once. The scroll padding below keeps the viewport stable during the
            // preview resize animation.
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    rowView(for: item, showsSeparator: index < rows.count - 1)
                }
            }
            .padding(.top, 3)
            // Preview expansion adds exactly this much usable height to the list. Matching it
            // with extra scrollable room keeps the scroll offset (and therefore the rows under
            // the cursor/keyboard selection) stable while the window animates.
            .padding(.bottom, model.isPreviewVisible ? Self.previewHeightDelta : 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let previewHeightDelta =
        PasteLayout.expandedSize.height - PasteLayout.collapsedSize.height

    private func rowView(for item: ClipboardItem, showsSeparator: Bool) -> some View {
        HistoryRowView(
            item: item,
            thumbnail: item.kind == .image ? model.thumbnail(for: item) : nil,
            isSelected: model.isSelected(item.id),
            isMultiSelecting: model.isMultiSelecting,
            isInteractionLocked: model.isEditingPreview || model.isPreviewTransitioning,
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

/// Placeholder for an empty history or a filter/search without matches.
private struct EmptyHistoryView: View {
    let isFiltering: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: isFiltering ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(isFiltering ? "没有找到匹配的内容" : "暂无剪贴板记录")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(isFiltering ? "换个筛选项或关键词试试" : "复制任意内容后会自动出现在这里")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
