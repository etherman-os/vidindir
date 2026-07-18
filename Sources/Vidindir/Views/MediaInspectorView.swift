import SwiftUI
import VidindirDomain

struct MediaInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    let startDownload: (LibraryItemSummary) -> Void
    @State private var confirmsDelete = false
    @State private var showsRename = false
    @State private var renameText = ""

    var body: some View {
        Group {
            if let item = library.selectedItem {
                inspector(item)
            } else if let job = library.selectedJob {
                downloadInspector(job)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a library item to see its details and actions.")
                )
            }
        }
        .frame(minWidth: 260, idealWidth: 300)
        .navigationTitle("Inspector")
    }

    private func inspector(_ item: LibraryItemSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MediaThumbnail(item: item)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.mediaItem.title ?? item.mediaItem.sourceURL.host ?? "Untitled Media")
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    if let creator = item.mediaItem.creator {
                        Text(creator)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                facts(item)

                if !library.collections.filter({ $0.kind == .user }).isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Collections")
                            .font(.headline)
                        ForEach(library.collections.filter { $0.kind == .user }) { collection in
                            Toggle(
                                collection.name,
                                isOn: Binding(
                                    get: { item.collectionIDs.contains(collection.id) },
                                    set: { value in
                                        library.setCollectionMembership(
                                            item: item,
                                            collectionID: collection.id,
                                            value: value
                                        )
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Local Status")
                        .font(.headline)
                    LocalStatusLabel(item: item)
                }

                VStack(spacing: 9) {
                    Button {
                        startDownload(item)
                    } label: {
                        Label(
                            item.localAssetStatus == .available
                                ? "Download Again"
                                : "Download on This Mac",
                            systemImage: "arrow.down.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VidindirTheme.accent)

                    if item.localAssetStatus == .available {
                        Button {
                            library.revealLocalFile(item)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    HStack {
                        Button {
                            library.openSource(item)
                        } label: {
                            Label("Open Source", systemImage: "safari")
                        }
                        Button {
                            library.copySourceURL(item)
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Button {
                            renameText = item.mediaItem.title
                                ?? item.mediaItem.sourceURL.host
                                ?? "Untitled Media"
                            showsRename = true
                        } label: {
                            Label("Rename…", systemImage: "pencil")
                        }

                        Button {
                            library.refreshMetadata(item)
                        } label: {
                            if library.isResolvingMetadata(for: item) {
                                Label("Fetching Details…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("Fetch Details", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(library.isResolvingMetadata(for: item))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        library.setFavorite(item, value: !item.isFavorite)
                    } label: {
                        Label(
                            item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: item.isFavorite ? "star.slash" : "star"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button("Delete from Library", role: .destructive) {
                        confirmsDelete = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .alert("Delete from Library?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete from Library", role: .destructive) {
                library.deleteFromLibrary(item)
            }
        } message: {
            Text("The saved link is removed. Vidindir does not silently delete a separate local media file.")
        }
        .alert("Rename Media", isPresented: $showsRename) {
            TextField("Media name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                library.rename(item, to: renameText)
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Use a name that will make this item easy to find later.")
        }
    }

    private func facts(_ item: LibraryItemSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            fact("Source", item.mediaItem.sourceType.displayName)
            if let duration = LibraryBrowserView.duration(item.mediaItem.durationSeconds) {
                fact("Duration", duration)
            }
            fact(
                "Added",
                item.mediaItem.version.createdAt.formatted(
                    .dateTime.month(.abbreviated).day().year()
                )
            )
            fact("Workspace", "Personal")
        }
        .font(.subheadline)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func downloadInspector(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(job.state.displayName, systemImage: symbol(for: job.state))
                .font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                fact("Format", job.mediaKind == .audio ? "Audio" : "Video")
                fact("Quality", job.qualityPreset.rawValue.capitalized)
                fact("Attempts", String(job.attemptCount))
                fact("Created", job.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
            }
            if let summary = job.errorSummary {
                Divider()
                Text(summary)
                    .foregroundStyle(.secondary)
                if let detail = job.technicalDetail {
                    DisclosureGroup("Technical Details") {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private func symbol(for state: DownloadJobState) -> String {
        switch state {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .paused: "pause.circle"
        case .interrupted: "arrow.clockwise.circle"
        default: "arrow.down.circle"
        }
    }
}
