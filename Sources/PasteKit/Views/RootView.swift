import SwiftUI

/// The whole palette surface, hosted by `PanelController` inside the borderless `NSPanel`.
///
/// The history column is 560pt and the preview is a fixed 284pt column drawn as an overlay to
/// its right. Keeping the preview out of the HStack's intrinsic width lets the window animate
/// its width; the preview is revealed as the window grows instead of being squashed/reflowed.
struct RootView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        GeometryReader { proxy in
            let previewOpen = model.isPreviewOpen
            let contentHeight = max(0, proxy.size.height - PasteLayout.topBarHeight - 1)

            VStack(spacing: 0) {
                TopBarView(model: model)
                    .frame(height: PasteLayout.topBarHeight)
                Hairline()
                ZStack(alignment: .topLeading) {
                    historyColumn
                        .frame(width: previewOpen ? PasteLayout.historyWidth : proxy.size.width)
                    if previewOpen {
                        previewColumn
                            .frame(width: PasteLayout.previewWidth, height: contentHeight)
                            .offset(x: PasteLayout.historyWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
