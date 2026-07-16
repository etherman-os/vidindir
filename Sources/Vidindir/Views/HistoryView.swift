import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Recent", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Clear", action: model.clearHistory)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                    HistoryRow(record: record) {
                        model.reveal(record)
                    }
                    if index < min(model.history.count, 5) - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .vidindirCard()
    }
}

private struct HistoryRow: View {
    let record: DownloadRecord
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconColor.opacity(0.11))
                    Image(systemName: record.format == .mp4 ? "film" : "waveform")
                        .foregroundStyle(iconColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title ?? record.sourceURL.host ?? "Download")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(record.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(record.format.displayName)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.055), in: Capsule())

                Image(systemName: record.outputFileURL == nil ? statusSymbol : "arrow.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(record.outputFileURL == nil)
    }

    private var iconColor: Color {
        record.status == .completed ? VidindirTheme.accent : .secondary
    }

    private var statusSymbol: String {
        switch record.status {
        case .failed: return "exclamationmark.circle"
        case .cancelled: return "xmark.circle"
        default: return "circle"
        }
    }
}
