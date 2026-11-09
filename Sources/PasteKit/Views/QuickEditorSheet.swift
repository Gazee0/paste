import SwiftUI

/// Modal editor for creating/updating a quick snippet.
struct QuickEditorSheet: View {
    @ObservedObject var model: AppModel
    let draft: QuickEditorDraft

    @State private var content: String
    @State private var note: String
    @State private var folderID: UUID?

    init(model: AppModel, draft: QuickEditorDraft) {
        self.model = model
        self.draft = draft
        _content = State(initialValue: draft.content)
        _note = State(initialValue: draft.note)
        _folderID = State(initialValue: draft.folderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.isNew ? "新建快贴" : "编辑快贴")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("文件夹", selection: $folderID) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(model.quickFolders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            TextEditor(text: $content)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PasteTheme.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PasteTheme.controlStroke, lineWidth: 1)
                }
                .frame(minHeight: 170)

            TextField("备注（可选）", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PasteTheme.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PasteTheme.controlStroke, lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("取消") {
                    model.cancelQuickEditor()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    model.saveQuickEditor(
                        snippetID: draft.snippetID,
                        folderID: folderID,
                        content: content,
                        note: note
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460, height: 360)
        .background(PasteTheme.background)
    }
}
