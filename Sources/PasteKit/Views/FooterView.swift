import SwiftUI

/// 40pt footer under the history list: multi-select entry point, destructive actions, and the
/// total number of clips in the history (never the filtered number alone).
struct FooterView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 8) {
            FlatIconTextButton(
                title: model.isMultiSelecting ? "完成" : "多选",
                systemName: model.isMultiSelecting ? "checkmark.circle.fill" : "checkmark.circle",
                tint: model.isMultiSelecting ? .accentColor : .secondary
            ) {
                model.toggleMultiSelect()
            }

            if model.isMultiSelecting {
                FlatIconTextButton(
                    title: "删除 \(model.checkedCount)",
                    systemName: "trash",
                    tint: .red,
                    isEnabled: model.checkedCount > 0
                ) {
                    model.deleteChecked()
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10))
                Text(countText)
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

    /// While searching, show `filtered/total` so the total is still discoverable.
    private var countText: String {
        if model.isSearching {
            return "\(model.filteredItems.count)/\(model.historyCount)"
        }
        return "\(model.historyCount)"
    }
}
