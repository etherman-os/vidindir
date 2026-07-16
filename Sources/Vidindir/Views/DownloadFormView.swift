import AppKit
import SwiftUI

struct DownloadFormView: View {
    @ObservedObject var model: AppModel
    @FocusState private var linkIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Link", systemImage: "link")

                HStack(spacing: 10) {
                    TextField("Paste a video or audio link", text: $model.linkText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($linkIsFocused)
                        .onSubmit(model.startDownload)
                        .disabled(model.phase.isBusy)
                        .accessibilityLabel("Media link")

                    Button(action: model.pasteFromClipboard) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(VidindirTheme.accent)
                    .disabled(model.phase.isBusy)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            model.linkValidationMessage == nil
                                ? VidindirTheme.accent.opacity(linkIsFocused ? 0.75 : 0.2)
                                : Color.red.opacity(0.65),
                            lineWidth: linkIsFocused ? 1.5 : 1
                        )
                }

                if let message = model.linkValidationMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "Format", systemImage: "slider.horizontal.3")

                HStack(spacing: 10) {
                    FormatChoice(
                        title: "MP4",
                        subtitle: "Video",
                        systemImage: "film",
                        isSelected: model.selectedFormat == .mp4,
                        action: { model.selectFormat(.mp4) }
                    )

                    FormatChoice(
                        title: "MP3",
                        subtitle: "Audio only",
                        systemImage: "waveform",
                        isSelected: model.selectedFormat == .mp3,
                        action: { model.selectFormat(.mp3) }
                    )
                }
                .disabled(model.phase.isBusy)
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "Save to", systemImage: "folder")

                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(VidindirTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.destinationDirectory.lastPathComponent)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(model.destinationDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    Button("Choose…", action: model.chooseDestinationDirectory)
                        .disabled(model.phase.isBusy)
                }

                Text("Vidindir remembers a different folder for each format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: model.startDownload) {
                HStack(spacing: 9) {
                    if model.phase == .preparing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(model.phase.isBusy ? "Downloading…" : "Download")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(VidindirTheme.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canStartDownload)
        }
        .vidindirCard()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                linkIsFocused = true
            }
        }
    }
}

private struct FormatChoice: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? VidindirTheme.accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? VidindirTheme.accent : Color.secondary.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                isSelected ? VidindirTheme.accent.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? VidindirTheme.accent.opacity(0.55) : Color.primary.opacity(0.09))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
