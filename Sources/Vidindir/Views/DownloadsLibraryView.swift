import SwiftUI
import VidindirDomain

struct DownloadsLibraryView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var download: AppModel
    @State private var pendingClearScope: DownloadHistoryScope?

    var body: some View {
        VStack(spacing: 0) {
            if library.completedDownloadCount > 0 || library.failedDownloadCount > 0 {
                historyActions
                Divider()
            }

            List(selection: $library.selectedDownloadJobID) {
                if download.shouldShowToolSetup {
                    ToolSetupView(model: download)
                        .listRowSeparator(.hidden)
                }

                if download.phase != .idle {
                    DownloadStatusView(model: download)
                        .listRowSeparator(.hidden)
                }

                if library.downloadJobs.isEmpty, !download.phase.isBusy {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(library.downloadJobs) { job in
                        DownloadJobRow(
                            job: job,
                            item: library.items.first { $0.id == job.mediaItemID },
                            reveal: {
                                guard let item = library.items.first(where: { $0.id == job.mediaItemID }) else {
                                    return
                                }
                                library.revealLocalFile(item)
                            },
                            retry: {
                                download.retryDownload(job.id)
                            }
                        )
                        .tag(job.id)
                    }

                    if library.canLoadMore {
                        loadMoreButton
                            .listRowSeparator(.hidden)
                    }
                }

                if !download.processLog.isEmpty || download.phase.isBusy {
                    DisclosureGroup("Activity Log") {
                        TerminalLogView(model: download)
                    }
                }
            }
            .listStyle(.inset)
        }
        .onChange(of: library.selectedDownloadJobID) { _, selectedID in
            guard let selectedID,
                  let job = library.downloadJobs.first(where: { $0.id == selectedID }) else {
                return
            }
            library.selectedMediaItemID = job.mediaItemID
        }
        .overlay {
            if library.isLoading, library.downloadJobs.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .alert(
            clearHistoryTitle,
            isPresented: Binding(
                get: { pendingClearScope != nil },
                set: { if !$0 { pendingClearScope = nil } }
            ),
            presenting: pendingClearScope
        ) { scope in
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                library.clearDownloadHistory(scope)
                pendingClearScope = nil
            }
        } message: { _ in
            Text("Only download activity records are removed. Saved links, downloaded files, and local-file records stay intact.")
        }
    }

    private var historyActions: some View {
        HStack {
            Spacer()
            Menu("Clear History", systemImage: "trash") {
                Button("Clear Completed…") {
                    pendingClearScope = .completed
                }
                .disabled(library.completedDownloadCount == 0)
                Button("Clear Needs Attention…") {
                    pendingClearScope = .needsAttention
                }
                .disabled(library.failedDownloadCount == 0)
                Divider()
                Button("Clear All Finished History…", role: .destructive) {
                    pendingClearScope = .allTerminal
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: library.destination.systemImage)
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("Add Link") { library.isQuickAddPresented = true }
                .buttonStyle(.borderedProminent)
                .tint(VidindirTheme.accent)
        }
    }

    private var emptyTitle: String {
        switch library.destination {
        case .activeDownloads: "No active downloads"
        case .completedDownloads: "No completed downloads"
        case .failedDownloads: "Nothing needs attention"
        default: "No downloads"
        }
    }

    private var emptyDescription: String {
        switch library.destination {
        case .activeDownloads: "Queued and in-progress work on this Mac appears here."
        case .completedDownloads: "Downloaded files stay linked to their library items."
        case .failedDownloads: "Failed, cancelled, and interrupted downloads appear here with a clear reason."
        default: "Your device-specific download history appears here."
        }
    }

    private var loadMoreButton: some View {
        Button {
            library.loadMore()
        } label: {
            if library.isLoadingMore {
                ProgressView().controlSize(.small)
            } else {
                Text("Load More")
            }
        }
        .buttonStyle(.borderless)
        .disabled(library.isLoadingMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var clearHistoryTitle: String {
        switch pendingClearScope {
        case .completed: "Clear Completed History?"
        case .needsAttention: "Clear Needs Attention History?"
        case .allTerminal: "Clear All Finished History?"
        case nil: "Clear Download History?"
        }
    }
}

private struct DownloadJobRow: View {
    let job: DownloadJob
    let item: LibraryItemSummary?
    let reveal: () -> Void
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item?.mediaItem.displayTitle ?? "Media download")
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)
                    rowAction
                }

                HStack(spacing: 6) {
                    Label(job.state.displayName, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                    Text("·")
                    Text(job.mediaKind == .audio ? "Audio" : "Video")
                    if let container = job.container {
                        Text(container.uppercased())
                    }
                    Spacer(minLength: 8)
                    if let fraction = job.progressFraction,
                       job.state != .completed {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let fraction = job.progressFraction,
                   job.state != .completed {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                if let summary = job.errorSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let item {
            MediaThumbnail(item: item, compact: true)
                .frame(width: 80, height: 45)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 80, height: 45)
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var rowAction: some View {
        if job.state == .completed {
            Button("Show in Finder", action: reveal)
                .buttonStyle(.borderless)
                .controlSize(.small)
        } else if [.failed, .cancelled, .interrupted].contains(job.state) {
            Button("Try Again", action: retry)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    private var statusSymbol: String {
        switch job.state {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        case .paused: "pause.circle"
        case .interrupted: "arrow.clockwise.circle"
        default: "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .completed: VidindirTheme.success
        case .failed: .red
        case .cancelled: .secondary
        case .interrupted: .orange
        default: .secondary
        }
    }
}
