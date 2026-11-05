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
        Button {
            model.togglePreview()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .medium))
                Text("预览")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.primary.opacity(model.isPreviewOpen ? 1 : 0.8))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(model.isPreviewOpen ? Color.primary.opacity(0.10) : PasteTheme.controlFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.selectedItem == nil)
        .opacity(model.selectedItem == nil ? 0.45 : 1)
        .help("预览")
    }

    // MARK: - Focus

    private func focusSearchField() {
        guard !model.isEditingPreview else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }
}
