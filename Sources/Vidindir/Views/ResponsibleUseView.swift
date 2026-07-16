import SwiftUI

struct ResponsibleUseView: View {
    let accept: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VidindirMark(size: 68)

            VStack(spacing: 8) {
                Text("Download responsibly")
                    .font(.title2.weight(.semibold))
                Text("Save only content you own, content under an open license, or content you have permission to download. Platform terms and copyright law still apply.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Vidindir does not bypass DRM.", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(VidindirTheme.accentDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(VidindirTheme.accent.opacity(0.10), in: Capsule())

            Button("I Understand", action: accept)
                .buttonStyle(.borderedProminent)
                .tint(VidindirTheme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }
}
