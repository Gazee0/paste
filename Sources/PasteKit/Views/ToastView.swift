import SwiftUI

/// Transient dark capsule floating above the footer.
struct ToastView: View {
    let message: ToastMessage
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let actionTitle = message.actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .underline()
                }
                .buttonStyle(.plain)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: 28)
        .background(Capsule().fill(PasteTheme.toastFill))
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        .contentShape(Capsule())
        .onTapGesture(perform: onDismiss)
    }
}
