import AppKit
import SwiftUI

/// Colors and inner metrics shared by every surface of the palette.
///
/// The palette is warm paper in light mode and a deep neutral in dark mode. Everything that
/// AppKit can resolve dynamically is built from a dynamic `NSColor`, so the views never need
/// to branch on the color scheme themselves.
enum PasteTheme {
    /// Panel background: warm paper (`#FAF9F6`) in light mode, near-black (`#1C1C1E`) in dark.
    static let background = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 0.980, green: 0.976, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)
    ))

    /// Fill behind the search field and the inline text editor.
    static let fieldFill = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
    ))

    /// Resting 1pt border around the search field.
    static let fieldBorder = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    ))

    /// Hairline dividers between the top bar, list rows, preview sections, and footer.
    static let separator = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.075),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085)
    ))

    /// 1pt outline around the panel. The window itself is borderless and transparent.
    static let windowBorder = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)
    ))

    /// Row fill for the selected row and for the row under the pointer.
    static let rowHighlight = Color.primary.opacity(0.065)

    /// Fill for a checked row while multi-select is active.
    static let checkedRow = Color.accentColor.opacity(0.10)

    /// Flat fill used by the small trailing top-bar controls ("预览").
    static let controlFill = Color.primary.opacity(0.055)

    /// Border used by small secondary controls ("编辑").
    static let controlStroke = Color.primary.opacity(0.12)

    /// Dark capsule behind transient toast messages.
    static let toastFill = Color(nsColor: .pasteAdaptive(
        light: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 0.92),
        dark: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 0.96)
    ))

    /// Tint for the type icon tile in a history row.
    static func tint(for kind: ClipboardKind) -> Color {
        switch kind {
        case .text: return .blue
        case .image: return .purple
        case .files: return .orange
        }
    }
}

extension NSColor {
    /// A color that resolves to `light` in Aqua and `dark` in Dark Aqua.
    static func pasteAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Inner spacing for the history column. Outer window geometry lives in `PasteLayout`.
enum PasteMetrics {
    static let listInset: CGFloat = 6
    static let rowCornerRadius: CGFloat = 7
    static let controlCornerRadius: CGFloat = 7
    static let rowMinHeight: CGFloat = 52
    static let iconTileSize: CGFloat = 26
    static let iconTileCornerRadius: CGFloat = 6
    static let footerControlHeight: CGFloat = 24
}
