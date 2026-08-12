import SwiftUI

enum VidindirTheme {
    static let accent = Color(red: 0.31, green: 0.56, blue: 0.55)
    static let accentDeep = Color(red: 0.12, green: 0.28, blue: 0.27)
    static let success = Color(red: 0.24, green: 0.60, blue: 0.42)
}

private struct VidindirCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}

extension View {
    func vidindirCard() -> some View {
        modifier(VidindirCardModifier())
    }
}

struct VidindirMark: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.primary.opacity(0.055))

            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(VidindirTheme.accent)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
