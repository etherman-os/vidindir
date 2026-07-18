import SwiftUI
import VidindirDomain

struct LibraryBrowserView: View {
    @ObservedObject var library: LibraryViewModel
    let displayMode: LibraryDisplayMode
    let startDownload: (LibraryItemSummary) -> Void
    @State private var pendingDelete: LibraryItemSummary?
    @State private var pendingRename: LibraryItemSummary?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            scopeExplanation
            Divider()
            Group {
                if library.items.isEmpty, !library.isLoading {
                    emptyState
                } else {
                    switch displayMode {
                    case .grid:
                        grid
                    case .list:
                        table
                    case .compact:
                        compactList
                    }
                }
            }
        }
        .overlay {
            if library.isLoading, library.items.isEmpty {
                ProgressView("Loading library…")
                    .controlSize(.small)
            }
        }
        .alert(
            "Delete from Library?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete from Library", role: .destructive) {
                library.deleteFromLibrary(item)
                pendingDelete = nil
            }
        } message: { _ in
            Text("This removes the saved link from your library. A local media file is a separate item and is never silently deleted.")
        }
        .alert(
            "Rename Media",
            isPresented: Binding(
                get: { pendingRename != nil },
                set: { if !$0 { pendingRename = nil } }
            )
        ) {
            TextField("Media name", text: $renameText)
            Button("Cancel", role: .cancel) { pendingRename = nil }
            Button("Save") {
                if let item = pendingRename {
                    library.rename(item, to: renameText)
                }
                pendingRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Use a name that will make this item easy to find later.")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 18)],
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(library.items) { item in
                    MediaGridCell(
                        item: item,
                        isSelected: library.selectedMediaItemID == item.id
                    ) {
                        library.selectedMediaItemID = item.id
                    }
                    .contextMenu { itemMenu(item) }
                    .draggable(item.mediaItem.sourceURL.absoluteString)
                }
            }
            .padding(20)
        }
    }

    private var table: some View {
        Table(library.items, selection: $library.selectedMediaItemID) {
            TableColumn("Title") { item in
                HStack(spacing: 10) {
                    MediaThumbnail(item: item, compact: true)
                        .frame(width: 72, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.mediaItem.displayTitle)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(item.mediaItem.sourceURL.host ?? "Media link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contextMenu { itemMenu(item) }
            }
            .width(min: 260, ideal: 380)

            TableColumn("Creator") { item in
                Text(item.mediaItem.creator ?? "—")
                    .foregroundStyle(item.mediaItem.creator == nil ? .secondary : .primary)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Duration") { item in
                Text(Self.duration(item.mediaItem.durationSeconds) ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(item.mediaItem.durationSeconds == nil ? .secondary : .primary)
            }
            .width(75)

            TableColumn("Local Status") { item in
                LocalStatusLabel(item: item)
            }
            .width(min: 105, ideal: 130)

            TableColumn("Added") { item in
                Text(item.mediaItem.version.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(.secondary)
            }
            .width(min: 95, ideal: 115)
        }
    }

    private var compactList: some View {
        List(library.items, selection: $library.selectedMediaItemID) { item in
            HStack(spacing: 10) {
                MediaThumbnail(item: item, compact: true)
                    .frame(width: 64, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.mediaItem.displayTitle)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(item.mediaItem.creator ?? item.mediaItem.sourceType.displayName)
                        if let duration = Self.duration(item.mediaItem.durationSeconds) {
                            Text("·")
                            Text(duration).monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if item.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                LocalStatusLabel(item: item, iconOnly: true)
            }
            .tag(item.id)
            .contextMenu { itemMenu(item) }
            .draggable(item.mediaItem.sourceURL.absoluteString)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyDescription)
        } actions: {
            if library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add Link") { library.isQuickAddPresented = true }
                    .buttonStyle(.borderedProminent)
                    .tint(VidindirTheme.accent)
            } else {
                Button("Clear Search") { library.searchText = "" }
            }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: LibraryItemSummary) -> some View {
        if library.destination == .inbox {
            Button("Remove from Inbox") { library.removeFromInbox(item) }
            Divider()
        }
        Button("Download on This Mac") { startDownload(item) }
        if item.localAssetStatus == .available {
            Button("Reveal in Finder") { library.revealLocalFile(item) }
        }
        Divider()
        Button("Open Source") { library.openSource(item) }
        Button("Copy URL") { library.copySourceURL(item) }
        Button("Rename…") {
            renameText = item.mediaItem.title ?? ""
            pendingRename = item
        }
        Button("Fetch Details") { library.refreshMetadata(item) }
            .disabled(library.isResolvingMetadata(for: item))
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            library.setFavorite(item, value: !item.isFavorite)
        }
        if !library.collections.filter({ $0.kind == .user }).isEmpty {
            Menu("Collections") {
                ForEach(library.collections.filter { $0.kind == .user }) { collection in
                    let isMember = item.collectionIDs.contains(collection.id)
                    Button {
                        library.setCollectionMembership(
                            item: item,
                            collectionID: collection.id,
                            value: !isMember
                        )
                    } label: {
                        Label(collection.name, systemImage: isMember ? "checkmark" : "folder")
                    }
                }
            }
        }
        Divider()
        Button("Delete from Library", role: .destructive) { pendingDelete = item }
    }

    private var emptyTitle: String {
        if !library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No results for “\(library.searchText)”"
        }
        return switch library.destination {
        case .inbox: "Your inbox is clear"
        case .library: "Build your video library"
        case .favorites: "No favorites yet"
        case .collection: "No media in this collection"
        default: "Nothing here yet"
        }
    }

    private var emptyDescription: String {
        if !library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different title, creator, URL, or collection name."
        }
        return switch library.destination {
        case .inbox: "New links wait here until you organize them or remove them from Inbox. They remain saved in All Media."
        case .library: "Every saved link appears here, including items that are still in Inbox."
        case .favorites: "Favorite useful media to find it quickly later."
        case .collection: "Add a link here or use an item's Collections menu."
        default: "Saved media will appear here."
        }
    }

    private var emptySymbol: String {
        if !library.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }
        return library.destination.systemImage
    }

    private var scopeExplanation: some View {
        HStack(spacing: 8) {
            Image(systemName: library.destination.systemImage)
                .foregroundStyle(VidindirTheme.accent)
            Text(scopeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var scopeDescription: String {
        switch library.destination {
        case .inbox:
            "New links waiting to be organized. Every item here is already saved in All Media."
        case .library:
            "Every saved link, including items still waiting in Inbox."
        case .favorites:
            "A quick view of media you marked as a favorite."
        case .collection:
            "A collection organizes links without duplicating their library records."
        default:
            "Saved media on this Mac."
        }
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct MediaThumbnail: View {
    let item: LibraryItemSummary
    var compact = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.09))
            if let thumbnailURL = item.mediaItem.thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView().controlSize(.small)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: item.mediaItem.sourceType == .youtube ? "play.rectangle" : "film")
            .font(compact ? .body : .largeTitle)
            .foregroundStyle(VidindirTheme.accent.opacity(0.8))
    }
}

private struct MediaGridCell: View {
    let item: LibraryItemSummary
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    MediaThumbnail(item: item)
                    if let duration = LibraryBrowserView.duration(item.mediaItem.durationSeconds) {
                        Text(duration)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thickMaterial, in: Capsule())
                            .padding(7)
                    }
                }
                Text(item.mediaItem.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(item.mediaItem.creator ?? item.mediaItem.sourceType.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    LocalStatusLabel(item: item, iconOnly: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                isSelected ? VidindirTheme.accent.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? VidindirTheme.accent.opacity(0.75) : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LocalStatusLabel: View {
    let item: LibraryItemSummary
    var iconOnly = false

    var body: some View {
        if let status = item.localAssetStatus {
            styledLabel(
                title: title(status),
                systemImage: symbol(status),
                color: color(status)
            )
        } else if let state = item.latestDownloadState,
                  state != .completed {
            styledLabel(
                title: state.displayName,
                systemImage: "arrow.down.circle",
                color: .secondary
            )
        } else {
            styledLabel(
                title: "Not downloaded",
                systemImage: "icloud.and.arrow.down",
                color: .secondary
            )
        }
    }

    @ViewBuilder
    private func styledLabel(title: String, systemImage: String, color: Color) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(color)
                .help(title)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(color)
                .help(title)
        }
    }

    private func title(_ status: LocalAssetStatus) -> String {
        switch status {
        case .available: "On this Mac"
        case .missing: "File missing"
        case .removed: "Local file removed"
        default: "Checking file"
        }
    }

    private func symbol(_ status: LocalAssetStatus) -> String {
        switch status {
        case .available: "checkmark.circle.fill"
        case .missing: "questionmark.circle"
        case .removed: "minus.circle"
        default: "clock"
        }
    }

    private func color(_ status: LocalAssetStatus) -> Color {
        status == .available ? VidindirTheme.success : .secondary
    }
}

extension DownloadJobState {
    var displayName: String {
        switch self {
        case .created: "Created"
        case .resolving: "Resolving"
        case .ready: "Ready"
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .postProcessing: "Finishing"
        case .completed: "Completed"
        case .paused: "Paused"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted"
        default: rawValue.capitalized
        }
    }
}
