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
            Text("Tab")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 2)
                .help("按 Tab 切换")
        }
        .padding(.horizontal, 12)
        .frame(height: PasteLayout.tabBarHeight)
        .background(WindowDragHandle())
    }
}
