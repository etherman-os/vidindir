import SwiftUI
import VidindirDomain

struct DownloadsLibraryView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var download: AppModel
    @State private var pendingClearScope: DownloadHistoryScope?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if library.completedDownloadCount > 0 || library.failedDownloadCount > 0 {
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
                    }
                }

                if download.shouldShowToolSetup {
                    ToolSetupView(model: download)
                }

                if download.phase != .idle {
                    DownloadStatusView(model: download)
                }

                if library.downloadJobs.isEmpty, !download.phase.isBusy {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    ForEach(library.downloadJobs) { job in
                        DownloadJobRow(
                            job: job,
                            item: library.items.first { $0.id == job.mediaItemID },
                            isSelected: library.selectedDownloadJobID == job.id
                        ) {
                            library.selectedDownloadJobID = job.id
                            library.selectedMediaItemID = job.mediaItemID
                        } reveal: {
                            guard let item = library.items.first(where: { $0.id == job.mediaItemID }) else {
                                return
                            }
                            library.revealLocalFile(item)
                        } retry: {
                            download.retryDownload(job.id)
                        }
                    }

                    if library.canLoadMore {
                        loadMoreButton
                    }
                }

                if !download.processLog.isEmpty || download.phase.isBusy {
                    DisclosureGroup("Activity Log") {
                        TerminalLogView(model: download)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
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
        .buttonStyle(.bordered)
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
    let isSelected: Bool
    let select: () -> Void
    let reveal: () -> Void
    let retry: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                if let item {
                    MediaThumbnail(item: item, compact: true)
                        .frame(width: 96, height: 54)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 96, height: 54)
                        .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item?.mediaItem.displayTitle ?? "Media download")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Label(job.state.displayName, systemImage: statusSymbol)
                        Text("·")
                        Text(job.mediaKind == .audio ? "Audio" : "Video")
                        if let container = job.container {
                            Text(container.uppercased())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(statusColor)

                    if let fraction = job.progressFraction,
                       job.state != .completed {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    }
                }

                Spacer()

                if job.state == .completed {
                    Button("Show in Finder", action: reveal)
                        .buttonStyle(.bordered)
                } else {
                    VStack(alignment: .trailing, spacing: 6) {
                        if [.failed, .cancelled, .interrupted].contains(job.state) {
                            Button("Try Again", action: retry)
                                .buttonStyle(.bordered)
                        }
                        if let summary = job.errorSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: 180, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                isSelected ? VidindirTheme.accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? VidindirTheme.accent.opacity(0.65) : Color.primary.opacity(0.06)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
