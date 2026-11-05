import AppKit
import SwiftUI

/// Square icon-only button used by the top bar and the preview header.
struct PanelIconButton: View {
    private let systemName: String
    private let help: String
    private let iconSize: CGFloat
    private let iconOffsetY: CGFloat
    private let tint: Color?
    private let isActive: Bool
    private let action: () -> Void

    @State private var isHovered = false

    init(
        systemName: String,
        help: String,
        iconSize: CGFloat = 12,
        iconOffsetY: CGFloat = 0,
        tint: Color? = nil,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.iconSize = iconSize
        self.iconOffsetY = iconOffsetY
        self.tint = tint
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary)
                .offset(y: iconOffsetY)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: PasteMetrics.controlCornerRadius, style: .continuous)
                        .fill(isActive ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.07) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: PasteMetrics.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Small flat icon + text button used by the footer.
struct FlatIconTextButton: View {
    private let title: String
    private let systemName: String
    private let tint: Color
    private let isEnabled: Bool
    private let action: () -> Void

    @State private var isHovered = false

    init(
        title: String,
        systemName: String,
        tint: Color = .secondary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: PasteMetrics.footerControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && isEnabled ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
    }
}

/// 1pt horizontal hairline in the palette separator color.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(PasteTheme.separator)
            .frame(height: 1)
    }
}

/// Invisible 7pt strip along the very top edge that drags the borderless window. The search
/// field starts 8pt down, so this never competes with the controls.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}
