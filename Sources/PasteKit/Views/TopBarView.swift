import SwiftUI

/// Full-width top bar: search, preview toggle, pin, and close.
struct TopBarView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isSearchFocused: Bool

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 8) {
            searchField
            previewButton
            PanelIconButton(
                systemName: model.isWindowPinned ? "pin.fill" : "pin",
                help: "窗口置顶",
                tint: model.isWindowPinned ? .accentColor : nil
            ) {
                model.toggleWindowPin()
            }
            PanelIconButton(systemName: "xmark", help: "关闭") {
                model.requestHide()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragHandle())
        .onAppear { focusSearchField() }
        .onChange(of: model.focusRequestNonce) { _, _ in focusSearchField() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("搜索拷贝的文本", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .frame(maxWidth: .infinity)

            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                    focusSearchField()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(PasteTheme.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? Color.accentColor : PasteTheme.fieldBorder,
                    lineWidth: isSearchFocused ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { focusSearchField() }
    }

    // MARK: - Trailing controls

    private var previewButton: some View {
        PanelIconButton(
            systemName: "eye",
            help: "预览（空格 / ⇧空格）",
            tint: model.isPreviewVisible ? .accentColor : nil,
            isActive: model.isPreviewVisible
        ) {
            model.togglePreview()
        }
        .disabled(model.selectedItem == nil)
        .opacity(model.selectedItem == nil ? 0.45 : 1)
    }

    // MARK: - Focus

    private func focusSearchField() {
        guard !model.isEditingPreview else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }
}
