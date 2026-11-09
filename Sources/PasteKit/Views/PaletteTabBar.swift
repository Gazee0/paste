import SwiftUI

/// Two top-level modes: clipboard history and quick snippets. Also switchable with Tab.
struct PaletteTabBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PaletteTab.allCases) { tab in
                let isSelected = model.activeTab == tab
                Button {
                    model.setActiveTab(tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tab == .clipboard ? "剪贴板历史" : "快贴")
            }
            Spacer(minLength: 0)
            previewButton
            PanelIconButton(
                systemName: model.isWindowPinned ? "pin.fill" : "pin",
                help: "窗口置顶",
                iconSize: 11.5,
                tint: model.isWindowPinned ? .accentColor : nil
            ) {
                model.toggleWindowPin()
            }
            PanelIconButton(systemName: "xmark", help: "关闭", iconSize: 11, iconOffsetY: -0.5) {
                model.requestHide()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: PasteLayout.tabBarHeight)
        .background(WindowDragHandle())
    }

    private var previewButton: some View {
        PanelIconButton(
            systemName: "eye",
            help: "预览（空格 / ⇧空格）",
            iconSize: 11,
            iconOffsetY: -1,
            tint: model.isPreviewVisible ? .accentColor : nil,
            isActive: model.isPreviewVisible
        ) {
            model.togglePreview()
        }
        // Keep the close action available if the preview is open while the current tab has
        // no selectable item; otherwise there is nothing to show.
        .disabled(!model.currentSelectionExists && !model.isPreviewOpen)
        .opacity(model.currentSelectionExists || model.isPreviewOpen ? 1 : 0.45)
    }
}
