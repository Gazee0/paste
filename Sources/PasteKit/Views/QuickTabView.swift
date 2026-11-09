import SwiftUI

/// The quick-snippet tab: folder sidebar + snippet list, with the same footer height as the
/// clipboard tab.
struct QuickTabView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                QuickFolderSidebar(model: model)
                    .frame(width: PasteLayout.quickFolderSidebarWidth)
                Rectangle()
                    .fill(PasteTheme.separator)
                    .frame(width: 1)
                QuickSnippetListView(model: model)
            }
            .frame(maxHeight: .infinity)
            QuickFooterView(model: model)
        }
    }
}

// MARK: - Folder sidebar

private struct QuickFolderSidebar: View {
    @ObservedObject var model: AppModel
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var folderToDelete: QuickFolder?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("文件夹")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    newFolderName = ""
                    showingNewFolder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("新建文件夹")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 32)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    folderRow(.all)
                    folderRow(.uncategorized)
                    ForEach(model.quickFolders) { folder in
                        folderRow(.folder(folder.id))
                            .contextMenu {
                                Button("删除文件夹", role: .destructive) {
                                    folderToDelete = folder
                                }
                            }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.primary.opacity(0.018))
        .alert("新建文件夹", isPresented: $showingNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                _ = model.addQuickFolder(named: newFolderName)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("快贴可以按文件夹归类")
        }
        .confirmationDialog(
            "删除文件夹？",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            presenting: folderToDelete
        ) { folder in
            Button("删除「\(folder.name)」", role: .destructive) {
                model.deleteQuickFolder(id: folder.id)
                folderToDelete = nil
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("文件夹里的快贴会移到「未分类」")
        }
    }

    private func folderRow(_ selection: QuickFolderSelection) -> some View {
        let isSelected = model.quickFolderSelection == selection
        let count = model.quickCount(in: selection)
        return Button {
            model.setQuickFolder(selection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection == .all ? "tray.full" : (selection == .uncategorized ? "tray" : "folder"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 14)
                Text(model.quickFolderTitle(for: selection))
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 7)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("筛选：\(model.quickFolderTitle(for: selection))")
    }
}

// MARK: - Snippet list

private struct QuickSnippetListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.quickFolderTitle(for: model.quickFolderSelection))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !model.quickFilteredSnippets.isEmpty {
                    Text("\(model.quickFilteredSnippets.count)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: 32)

            if model.quickFilteredSnippets.isEmpty {
                QuickEmptyView(isSearching: model.isSearching || model.quickFolderSelection != .all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(model.quickFilteredSnippets) { snippet in
                                QuickSnippetRowView(
                                    snippet: snippet,
                                    folderTitle: model.quickFolderTitle(for: snippet),
                                    isSelected: model.selectedQuickID == snippet.id,
                                    shortcutIndex: model.quickShortcutIndex(for: snippet),
                                    timeText: model.timeText(for: snippet.updatedAt),
                                    onHover: { model.selectQuick(snippet) },
                                    onClick: {
                                        model.selectQuick(snippet)
                                        model.refocusSearch()
                                    },
                                    onDoubleClick: { model.pasteQuick(snippet) },
                                    onEdit: { model.beginEditingQuickSnippet(snippet) },
                                    onCopy: { model.copyQuick(snippet) },
                                    onPaste: { model.pasteQuick(snippet) },
                                    onDelete: { model.deleteQuickSnippet(snippet) }
                                )
                                .id(snippet.id)
                            }
                        }
                        .padding(.top, 2)
                        // Match the clipboard list: the preview adds height to the window, and
                        // the matching scrollable room keeps the quick list offset stable while
                        // that transition animates.
                        .padding(.bottom, model.isPreviewVisible ? (PasteLayout.expandedSize.height - PasteLayout.collapsedSize.height) : 6)
                    }
                    .onChange(of: model.keyboardScrollNonce) { _, _ in
                        guard let selected = model.selectedQuickID,
                              model.quickFilteredSnippets.contains(where: { $0.id == selected }) else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(selected, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct QuickSnippetRowView: View {
    let snippet: QuickSnippet
    let folderTitle: String
    let isSelected: Bool
    let shortcutIndex: Int?
    let timeText: String
    let onHover: () -> Void
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var lastClickDate = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: PasteMetrics.iconTileCornerRadius, style: .continuous)
                        .fill(Color.teal.opacity(0.13))
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.teal)
                }
                .frame(width: PasteMetrics.iconTileSize, height: PasteMetrics.iconTileSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.content)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .lineSpacing(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !snippet.note.isEmpty {
                        Text(snippet.note)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8.5))
                        Text(folderTitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.tertiary)
                }

                VStack(alignment: .trailing, spacing: 3) {
                    Text(timeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(minHeight: PasteMetrics.rowMinHeight)
            .background(
                RoundedRectangle(cornerRadius: PasteMetrics.rowCornerRadius, style: .continuous)
                    .fill(isSelected || isHovered ? PasteTheme.rowHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: PasteMetrics.rowCornerRadius, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
                if hovering { onHover() }
            }
            .onTapGesture(perform: handleTap)
            .contextMenu {
                Button("编辑") { onEdit() }
                Button("拷贝") { onCopy() }
                Button("粘贴") { onPaste() }
                Divider()
                Button("删除", role: .destructive) { onDelete() }
            }

            Rectangle()
                .fill(PasteTheme.separator)
                .frame(height: 1)
                .padding(.leading, 44)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 6)
    }

    private func handleTap() {
        let now = Date()
        let isDoubleTap = now.timeIntervalSince(lastClickDate) < 0.5
        lastClickDate = now
        if isDoubleTap {
            onDoubleClick()
        } else {
            onClick()
        }
    }
}

private struct QuickEmptyView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isSearching ? "magnifyingglass" : "note.text")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isSearching ? "没有找到匹配的快贴" : "暂无快贴")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(isSearching ? "换个关键词或文件夹试试" : "点击下方「新建」添加一条快贴")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

// MARK: - Footer

private struct QuickFooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            FlatIconTextButton(
                title: "新建",
                systemName: "plus",
                tint: .accentColor
            ) {
                model.beginNewQuickSnippet()
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                Text(model.quickCountText)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: PasteLayout.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PasteTheme.separator)
                .frame(height: 1)
        }
    }
}
