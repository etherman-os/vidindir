import SwiftUI
import VidindirDomain

struct LibraryBrowserView: View {
    @ObservedObject var library: LibraryViewModel
    let displayMode: LibraryDisplayMode
    let startDownload: (LibraryItemSummary) -> Void
    @State private var pendingDelete: LibraryItemSummary?

    var body: some View {
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
                        Text(item.mediaItem.title ?? item.mediaItem.sourceURL.host ?? "Untitled Media")
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
                    Text(item.mediaItem.title ?? item.mediaItem.sourceURL.host ?? "Untitled Media")
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
        Button("Download on This Mac") { startDownload(item) }
        if item.localAssetStatus == .available {
            Button("Reveal in Finder") { library.revealLocalFile(item) }
        }
        Divider()
        Button("Open Source") { library.openSource(item) }
        Button("Copy URL") { library.copySourceURL(item) }
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
        case .inbox: "New links can wait here until you organize them."
        case .library: "Save a media link to keep it searchable, even before downloading."
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
                Text(item.mediaItem.title ?? item.mediaItem.sourceURL.host ?? "Untitled Media")
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

extension SourceType {
    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .x: "X"
        case .vimeo: "Vimeo"
        case .generic: "Web"
        default: rawValue.capitalized
        }
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
