import SwiftUI

enum VidindirTheme {
    static let accent = Color(red: 0.31, green: 0.56, blue: 0.55)
    static let accentDeep = Color(red: 0.12, green: 0.28, blue: 0.27)
    static let warm = Color(red: 0.98, green: 0.97, blue: 0.93)
    static let success = Color(red: 0.24, green: 0.60, blue: 0.42)
}

private struct VidindirCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 16, y: 8)
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
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [VidindirTheme.warm, VidindirTheme.accent.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: size * 0.04) {
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(VidindirTheme.accent)
                    .offset(y: size * 0.04)

                ShoreLine()
                    .stroke(VidindirTheme.accentDeep, style: StrokeStyle(lineWidth: max(1.5, size * 0.035), lineCap: .round))
                    .frame(width: size * 0.58, height: size * 0.13)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: VidindirTheme.accentDeep.opacity(0.13), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

private struct ShoreLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.maxY)
        )
        return path
    }
}

struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.7)
    }
}
