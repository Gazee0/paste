import AppKit
import SwiftUI

/// The 284pt right-hand preview column.
///
/// Text can be edited inline (cancel/save replace the edit button), images are aspect-fit with
/// a caption, and files list their names with the parent path underneath.
struct PreviewPaneView: View {
    @ObservedObject var model: AppModel
    @State private var draftText = ""
    @FocusState private var isEditorFocused: Bool

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            divider
            footer
        }
        .background(PasteTheme.background)
        .onAppear { syncDraftWithEditingItem() }
        .onChange(of: model.editingID) { _, _ in syncDraftWithEditingItem() }
    }

    /// The editor can be opened in the same update that inserts the preview column (for example
    /// from a keyboard shortcut), so `onChange` alone is not enough: seed the draft whenever the
    /// pane appears while an item is already being edited.
    private func syncDraftWithEditingItem() {
        guard let id = model.editingID,
              let item = model.editingItem,
              item.id == id else { return }
        draftText = item.text ?? ""
        DispatchQueue.main.async { isEditorFocused = true }
    }

    private var divider: some View {
        Rectangle()
            .fill(PasteTheme.separator)
            .frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PanelIconButton(systemName: "xmark", help: "关闭预览", iconSize: 10.5) {
                model.closePreview()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.trailing, 8)
        .frame(height: PasteLayout.previewHeaderHeight)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let item = model.previewItem {
            switch item.kind {
            case .text:
                textContent(item)
            case .image:
                imageContent(item)
            case .files:
                filesContent(item)
            }
        } else {
            emptyPreview
        }
    }

    private var emptyPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("选择一条记录以预览")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    @ViewBuilder
    private func textContent(_ item: ClipboardItem) -> some View {
        if model.editingID == item.id {
            TextEditor(text: $draftText)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PasteTheme.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
                .padding(14)
                .focused($isEditorFocused)
                .onAppear {
                    DispatchQueue.main.async { isEditorFocused = true }
                }
        } else {
            ScrollView(.vertical) {
                Text(item.text ?? "")
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(Rectangle())
                    .onTapGesture { model.refocusSearch() }
            }
        }
    }

    private func imageContent(_ item: ClipboardItem) -> some View {
        VStack(spacing: 8) {
            if let image = model.image(for: item) {
                GeometryReader { proxy in
                    let pixelSize = CGSize(
                        width: item.pixelWidth.map(CGFloat.init) ?? image.size.width,
                        height: item.pixelHeight.map(CGFloat.init) ?? image.size.height
                    )
                    let fitted = fittedImageSize(pixelSize, in: proxy.size)
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                    Text("无法载入图片")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 0) {
                Text(item.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    /// Aspect-fit inside the preview column, rounded to the actual image bounds so the border
    /// hugs the picture instead of the empty space around it.
    private func fittedImageSize(_ imageSize: CGSize, in available: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              available.width > 0, available.height > 0 else { return available }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func filesContent(_ item: ClipboardItem) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(item.filePaths.enumerated()), id: \.offset) { _, path in
                    let url = URL(fileURLWithPath: path)
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "doc")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(url.deletingLastPathComponent().path)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if let item = model.previewItem {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(model.timeText(for: item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let source = item.sourceApp, !source.isEmpty {
                        Text(source)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 4)
                footerActions(for: item)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: PasteLayout.footerHeight)
        } else {
            Color.clear
                .frame(height: PasteLayout.footerHeight)
        }
    }

    @ViewBuilder
    private func footerActions(for item: ClipboardItem) -> some View {
        let isEditing = model.editingID == item.id
        HStack(spacing: 6) {
            if isEditing {
                secondaryButton("取消") { model.cancelEditing() }
                accentButton("保存") { saveDraft() }
            } else if item.kind == .text {
                secondaryButton("编辑") { beginEditing(item) }
            }
            accentButton("拷贝", isEnabled: !isEditing) { model.copy(item) }
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(PasteTheme.controlStroke, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func accentButton(
        _ title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    // MARK: - Editing

    private func beginEditing(_ item: ClipboardItem) {
        draftText = item.text ?? ""
        model.beginEditing()
    }

    private func saveDraft() {
        if !model.saveEditing(text: draftText) {
            DispatchQueue.main.async { isEditorFocused = true }
        }
    }
}
