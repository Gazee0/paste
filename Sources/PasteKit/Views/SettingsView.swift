import AppKit
import SwiftUI

/// The standalone settings window. It is intentionally a plain reference page today, with the
/// complete shortcut map grouped by where the keys are active.
struct SettingsView: View {
    let onClose: () -> Void

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutCatalog.sections) { section in
                        shortcutSection(section)
                    }
                    footer
                }
                .padding(20)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 620, height: 700)
        .background(PasteTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: PasteLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PasteLayout.cornerRadius, style: .continuous)
                .strokeBorder(PasteTheme.windowBorder, lineWidth: 1)
        }
        .accessibilityLabel("Paste 设置")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                Text("Paste 快捷键与行为")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            PanelIconButton(systemName: "xmark", help: "关闭设置", iconSize: 11, iconOffsetY: -0.5) {
                onClose()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(WindowDragHandle())
    }

    private func shortcutSection(_ section: ShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(section.title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 3)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    ShortcutRow(item: item)
                    if item.id != section.items.last?.id {
                        Hairline()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.022))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(PasteTheme.separator, lineWidth: 1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Paste \(version)")
            Spacer(minLength: 12)
            Text("数据目录：")
            Text(HistoryStore.defaultDirectory().path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(HistoryStore.defaultDirectory().path)
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.defaultDirectory()])
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 3)
        .padding(.top, 2)
    }
}

// MARK: - Rows

private struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                ForEach(Array(item.alternatives.enumerated()), id: \.offset) { index, keys in
                    if index > 0 {
                        Text("/")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 1)
                    }
                    HStack(spacing: 3) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            KeyCap(label: key)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, item.detail == nil ? 8 : 6)
        .frame(minHeight: item.detail == nil ? 36 : 42)
    }
}

private struct KeyCap: View {
    let label: String

    private var isWide: Bool { label.count > 1 }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.78))
            .frame(minWidth: isWide ? 28 : 21, minHeight: 21)
            .padding(.horizontal, isWide ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PasteTheme.fieldFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(PasteTheme.controlStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 0.5, y: 1)
    }
}

// MARK: - Shortcut catalog

struct ShortcutSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let items: [ShortcutItem]

    init(title: String, systemImage: String, items: [ShortcutItem]) {
        self.id = title
        self.title = title
        self.systemImage = systemImage
        self.items = items
    }
}

struct ShortcutItem: Identifiable {
    let id: String
    let title: String
    let alternatives: [[String]]
    let detail: String?

    init(_ title: String, _ alternatives: [[String]], detail: String? = nil) {
        self.id = title + alternatives.flatMap { $0 }.joined()
        self.title = title
        self.alternatives = alternatives
        self.detail = detail
    }
}

enum ShortcutCatalog {
    static let sections: [ShortcutSection] = [
        ShortcutSection(title: "全局", systemImage: "globe", items: [
            ShortcutItem("打开 / 隐藏 Paste", [["⌥", "V"]]),
        ]),
        ShortcutSection(title: "窗口与搜索", systemImage: "macwindow", items: [
            ShortcutItem("关闭面板 / 退出编辑 / 清空搜索", [["Esc"]], detail: "按当前状态逐级处理，不会关闭预览"),
            ShortcutItem("切换剪贴板 / 快贴", [["Tab"]]),
        ]),
        ShortcutSection(title: "通用（剪贴板与快贴）", systemImage: "square.grid.2x2", items: [
            ShortcutItem("在列表区上移 / 下移选择", [["↑"], ["↓"]]),
            ShortcutItem("打开 / 关闭预览", [["Space"]], detail: "搜索框为空时"),
            ShortcutItem("随时打开 / 关闭预览", [["⇧", "Space"]]),
            ShortcutItem("粘贴选中条目", [["↩"]]),
            ShortcutItem("粘贴第 1–9 条", [["⌘", "1–9"]]),
            ShortcutItem("粘贴条目 / 打开菜单", [["双击"], ["右键"]]),
        ]),
        ShortcutSection(title: "剪贴板", systemImage: "doc.on.clipboard", items: [
            ShortcutItem("切换类型筛选", [["←"], ["→"]], detail: "搜索框为空时"),
        ]),
        ShortcutSection(title: "快贴", systemImage: "bolt", items: [
            ShortcutItem("进入文件夹区 / 返回列表区", [["←"], ["→"]], detail: "搜索框为空时"),
            ShortcutItem("在文件夹区上移 / 下移", [["↑"], ["↓"]]),
            ShortcutItem("文件夹区返回列表区", [["↩"]]),
        ]),
    ]
}
