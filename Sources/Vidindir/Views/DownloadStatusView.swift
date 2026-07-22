import AppKit
import SwiftUI

struct DownloadStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.phase.title)
                        .font(.headline)
                    if !model.currentTitle.isEmpty {
                        Text(model.currentTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                phaseAction
            }

            if model.phase == .downloading || model.phase == .preparing || model.phase == .postProcessing {
                progressSection
            }

            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Try Again") { model.startDownload() }
                        .buttonStyle(.borderedProminent)
                        .tint(VidindirTheme.accent)
                    Button("New Download", action: model.resetForNewDownload)
                        .buttonStyle(.bordered)
                }
            }

            if model.phase == .cancelled {
                Button("New Download", action: model.resetForNewDownload)
                    .buttonStyle(.bordered)
            }
        }
        .vidindirCard()
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.13))
            Image(systemName: statusSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var phaseAction: some View {
        if model.phase.isBusy {
            Button("Cancel", action: model.cancelDownload)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if model.phase == .completed {
            HStack(spacing: 8) {
                Button("Show in Finder", action: model.revealCurrentDownload)
                    .buttonStyle(.borderedProminent)
                    .tint(VidindirTheme.accent)
                Button("New", action: model.resetForNewDownload)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fraction = model.metrics.fractionCompleted,
               model.phase == .downloading {
                ProgressView(value: fraction)
                    .tint(VidindirTheme.accent)
                HStack {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Spacer()
                    metricsText
                }
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(VidindirTheme.accent)
                HStack {
                    Text(model.phase == .postProcessing ? model.postProcessingLabel : "Working…")
                    Spacer()
                    metricsText
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metricsText: some View {
        HStack(spacing: 10) {
            if let speed = model.metrics.speedBytesPerSecond {
                Text("\(Self.byteFormatter.string(fromByteCount: Int64(speed)))/s")
            }
            if let eta = model.metrics.etaSeconds, eta.isFinite, eta >= 0 {
                Text("\(Self.durationFormatter.string(from: eta) ?? "") left")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch model.phase {
        case .completed:
            return VidindirTheme.success
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        default:
            return VidindirTheme.accent
        }
    }

    private var statusSymbol: String {
        switch model.phase {
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        case .cancelled:
            return "xmark"
        case .postProcessing:
            return "wand.and.stars"
        default:
            return "arrow.down"
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
}
