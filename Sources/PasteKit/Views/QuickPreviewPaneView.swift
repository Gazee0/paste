import SwiftUI

/// Right-hand preview for a quick snippet. The show/hide mechanics are owned by the shared
/// palette preview state, exactly like the clipboard preview.
struct QuickPreviewPaneView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(PasteTheme.background)
    }

    @ViewBuilder
    private var content: some View {
        if let snippet = model.selectedQuickSnippet {
            VStack(spacing: 0) {
                if !snippet.note.isEmpty {
                    noteBanner(snippet.note)
                }
                SelectableTextView(text: snippet.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 7) {
                Image(systemName: "note.text")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("选择一条快贴查看")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func noteBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "text.quote")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            Text(note)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PasteTheme.fieldFill.opacity(0.65))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PasteTheme.separator)
                .frame(height: 1)
        }
    }

    private var footer: some View {
        Group {
            if let snippet = model.selectedQuickSnippet {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Text(model.timeText(for: snippet.updatedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(model.quickFolderTitle(for: snippet))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        secondaryButton("编辑") { model.beginEditingQuickSnippet(snippet) }
                        accentButton("拷贝") { model.copyQuick(snippet) }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: PasteLayout.footerHeight)
            } else {
                Color.clear
                    .frame(height: PasteLayout.footerHeight)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PasteTheme.separator)
                .frame(height: 1)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PasteTheme.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(PasteTheme.controlStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func accentButton(_ title: String, action: @escaping () -> Void) -> some View {
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
        }
        .buttonStyle(.plain)
    }
}
