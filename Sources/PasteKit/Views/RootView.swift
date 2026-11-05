import SwiftUI

/// The whole palette surface, hosted by `PanelController` inside the borderless `NSPanel`.
///
/// Layout is fixed in points: a 560pt history column and, when open, a 284pt preview column
/// to its right. The window controller animates the panel frame; the content just fills it.
struct RootView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(model: model)
                .frame(height: PasteLayout.topBarHeight)
            Hairline()
            HStack(spacing: 0) {
                historyColumn
                    .frame(width: PasteLayout.historyWidth)
                if model.isPreviewOpen {
                    previewColumn
                        .frame(width: PasteLayout.previewWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PasteTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: PasteLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PasteLayout.cornerRadius, style: .continuous)
                .strokeBorder(PasteTheme.windowBorder, lineWidth: 1)
        }
        .overlay(alignment: .top) {
            WindowDragHandle()
                .frame(height: 7)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Columns

    private var historyColumn: some View {
        VStack(spacing: 0) {
            HistoryListHeader()
            HistoryListView(model: model)
                .frame(maxHeight: .infinity)
            FooterView(model: model)
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
    }

    private var previewColumn: some View {
        PreviewPaneView(model: model)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(PasteTheme.separator)
                    .frame(width: 1)
            }
    }

    // MARK: - Toast

    /// Floats just above the footer, centered over the history column only.
    private var toastOverlay: some View {
        ZStack {
            if let toast = model.toast {
                ToastView(
                    message: toast,
                    onAction: { model.performToastAction() },
                    onDismiss: { model.dismissToast() }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity
                ))
                .padding(.bottom, PasteLayout.footerHeight + 10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toast)
    }
}
