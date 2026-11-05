import AppKit
import SwiftUI

/// Large, standalone image viewer opened from the inline preview.
///
/// The viewer owns an absolute display scale (1.0 == the image's natural point size), starts at
/// a fit-to-window scale, and supports pinch-to-zoom, drag-to-pan, double-click toggling between
/// fit and actual size, plus explicit zoom controls.
struct LargeImagePreviewView: View {
    let item: ClipboardItem
    let image: NSImage
    /// The image canvas; does not include the top bar or footer.
    let canvasSize: CGSize
    let onClose: () -> Void

    @State private var scale: CGFloat
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

    private let fitScale: CGFloat

    static let topBarHeight: CGFloat = 48
    static let footerHeight: CGFloat = 32

    private static let minScale: CGFloat = 0.05
    private static let maxScale: CGFloat = 8

    init(item: ClipboardItem, image: NSImage, canvasSize: CGSize, onClose: @escaping () -> Void) {
        self.item = item
        self.image = image
        self.canvasSize = canvasSize
        self.onClose = onClose

        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let rawFit = min(canvasSize.width / width, canvasSize.height / height)
        let fit = min(max(rawFit, Self.minScale), 4)
        self.fitScale = fit
        _scale = State(initialValue: fit)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            divider
            imageCanvas
            footer
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height + Self.topBarHeight + Self.footerHeight
        )
        .background(Color(red: 0.055, green: 0.058, blue: 0.065))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            WindowDragHandle()
                .frame(height: 8)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))

            Text(item.displayText)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            if let source = item.sourceApp, !source.isEmpty {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            zoomControls

            iconButton(systemName: "xmark", help: "关闭") {
                onClose()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.topBarHeight)
        .background(Color.white.opacity(0.055))
    }

    private var zoomControls: some View {
        HStack(spacing: 5) {
            iconButton(systemName: "minus", help: "缩小") {
                zoom(by: 1 / 1.25)
            }

            Text(percentText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .monospacedDigit()
                .frame(width: 42)

            iconButton(systemName: "plus", help: "放大") {
                zoom(by: 1.25)
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            textButton("适应", help: "适应窗口") {
                zoomToFit()
            }
            textButton("100%", help: "实际大小") {
                zoomToActualSize()
            }
        }
    }

    private func iconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func textButton(
        _ title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Canvas

    private var imageCanvas: some View {
        ZStack {
            Color(red: 0.035, green: 0.037, blue: 0.042)

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width * effectiveScale,
                       height: imageSize.height * effectiveScale)
                .offset(x: displayOffset.width, y: displayOffset.height)
                .gesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) { toggleFitAndActual() }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("双击切换适应 / 100% · 捏合缩放 · 拖拽平移 · Esc 关闭")
                .font(.system(size: 10))
            Spacer(minLength: 8)
            Text("\(Int(imageSize.width))×\(Int(imageSize.height))")
                .font(.system(size: 10))
                .monospacedDigit()
        }
        .foregroundStyle(Color.white.opacity(0.4))
        .padding(.horizontal, 14)
        .frame(height: Self.footerHeight)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    // MARK: - Zoom & pan

    private var imageSize: CGSize {
        CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
    }

    private var effectiveScale: CGFloat {
        min(max(scale * pinch, Self.minScale), Self.maxScale)
    }

    private var displayOffset: CGSize {
        clampedOffset(
            CGSize(
                width: offset.width + dragTranslation.width,
                height: offset.height + dragTranslation.height
            ),
            scale: effectiveScale
        )
    }

    private var percentText: String {
        "\(Int((effectiveScale * 100).rounded()))%"
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = clampScale(scale * value.magnification)
                offset = clampedOffset(offset, scale: scale)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = clampedOffset(
                    CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    ),
                    scale: effectiveScale
                )
            }
    }

    private func zoom(by factor: CGFloat) {
        scale = clampScale(scale * factor)
        offset = clampedOffset(offset, scale: scale)
    }

    private func zoomToFit() {
        scale = fitScale
        offset = .zero
    }

    private func zoomToActualSize() {
        scale = 1
        offset = .zero
    }

    private func toggleFitAndActual() {
        if abs(scale - fitScale) < 0.001 {
            scale = 1
        } else {
            scale = fitScale
        }
        offset = .zero
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minScale), Self.maxScale)
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let maxX = max(0, (scaledWidth - canvasSize.width) / 2)
        let maxY = max(0, (scaledHeight - canvasSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
