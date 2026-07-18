import AppKit
import Foundation
import VidindirDomain
import VidindirPersistence

enum LibraryDestination: Hashable, Identifiable {
    case inbox
    case library
    case favorites
    case activeDownloads
    case completedDownloads
    case failedDownloads
    case collection(CollectionID)

    var id: String {
        switch self {
        case .inbox: "inbox"
        case .library: "library"
        case .favorites: "favorites"
        case .activeDownloads: "downloads.active"
        case .completedDownloads: "downloads.completed"
        case .failedDownloads: "downloads.failed"
        case .collection(let id): "collection.\(id)"
        }
    }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .library: "All Media"
        case .favorites: "Favorites"
        case .activeDownloads: "Active"
        case .completedDownloads: "Completed"
        case .failedDownloads: "Failed"
        case .collection: "Collection"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .library: "rectangle.stack"
        case .favorites: "star"
        case .activeDownloads: "arrow.down.circle"
        case .completedDownloads: "checkmark.circle"
        case .failedDownloads: "exclamationmark.triangle"
        case .collection: "folder"
        }
    }

    var libraryScope: LibraryScope? {
        switch self {
        case .inbox: .inbox
        case .library: .all
        case .favorites: .favorites
        case .collection(let id): .collection(id)
        case .activeDownloads, .completedDownloads, .failedDownloads: nil
        }
    }
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case grid
    case list
    case compact

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        case .compact: "rectangle.grid.1x2"
        }
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var destination: LibraryDestination = .inbox {
        didSet {
            guard destination != oldValue else { return }
            selectedMediaItemID = nil
            selectedDownloadJobID = nil
            scheduleReload(immediately: true)
        }
    }
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleReload(immediately: false)
        }
    }
    @Published var selectedMediaItemID: MediaItemID?
    @Published var selectedDownloadJobID: DownloadJobID?
    @Published var isQuickAddPresented = false
    @Published private(set) var items: [LibraryItemSummary] = []
    @Published private(set) var downloadJobs: [DownloadJob] = []
    @Published private(set) var collections: [Collection] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var inboxCount = 0
    @Published private(set) var libraryCount = 0
    @Published private(set) var favoritesCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var startupError: String?
    @Published private(set) var importResult: LegacyHistoryImportResult?
    @Published private(set) var resolvingMetadataIDs: Set<MediaItemID> = []
    @Published var alert: AppAlert?

    private let libraryRepository: (any LibraryRepository)?
    private let downloadRepository: (any DownloadJobRepository)?
    private let legacyImporter: LegacyHistoryImporter?
    private let legacyHistoryData: Data?
    private let metadataResolver: (any MediaMetadataResolving)?
    private var didBootstrap = false
    private var loadTask: Task<Void, Never>?
    private var metadataRefreshTask: Task<Void, Never>?
    private var loadGeneration = UUID()

    init(
        libraryRepository: (any LibraryRepository)?,
        downloadRepository: (any DownloadJobRepository)?,
        legacyImporter: LegacyHistoryImporter?,
        legacyHistoryData: Data?,
        metadataResolver: (any MediaMetadataResolving)? = nil,
        startupError: String? = nil
    ) {
        self.libraryRepository = libraryRepository
        self.downloadRepository = downloadRepository
        self.legacyImporter = legacyImporter
        self.legacyHistoryData = legacyHistoryData
        self.metadataResolver = metadataResolver
        self.startupError = startupError
    }

    deinit {
        loadTask?.cancel()
        metadataRefreshTask?.cancel()
    }

    var isAvailable: Bool {
        libraryRepository != nil && downloadRepository != nil && startupError == nil
    }

    var selectedItem: LibraryItemSummary? {
        guard let selectedMediaItemID else { return nil }
        return items.first { $0.id == selectedMediaItemID }
    }

    var selectedJob: DownloadJob? {
        guard let selectedDownloadJobID else { return nil }
        return downloadJobs.first { $0.id == selectedDownloadJobID }
    }

    var destinationTitle: String {
        guard case .collection(let id) = destination else { return destination.title }
        return collections.first { $0.id == id }?.name ?? "Collection"
    }

    var isDownloadDestination: Bool {
        destination.libraryScope == nil
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        loadTask = Task { [weak self] in
            await self?.bootstrapNow()
        }
    }

    func bootstrapNow() async {
        guard isAvailable,
              let libraryRepository,
              let downloadRepository else { return }
        isLoading = true
        do {
            if let legacyImporter {
                importResult = try await legacyImporter.importHistoryData(legacyHistoryData)
            }
            _ = try await downloadRepository.interruptActiveJobsAfterLaunch()
            collections = try await libraryRepository.collections(
                workspaceID: VidindirIdentity.personalWorkspace
            )
            await reloadNow()
            refreshMissingMetadataInBackground()
        } catch {
            isLoading = false
            alert = AppAlert(
                title: "Library could not be opened",
                message: Self.userFacingMessage(for: error)
            )
        }
    }

    func reload() {
        scheduleReload(immediately: true)
    }

    func reloadNow() async {
        guard let libraryRepository, let downloadRepository else {
            isLoading = false
            return
        }
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        let selectedDestination = destination
        do {
            if let scope = selectedDestination.libraryScope {
                let page = try await libraryRepository.page(LibraryQuery(
                    scope: scope,
                    searchText: searchText,
                    limit: 500
                ))
                guard loadGeneration == generation, !Task.isCancelled else { return }
                items = page.items
                totalCount = page.totalCount
                downloadJobs = []
            } else {
                let states: Set<DownloadJobState>
                switch selectedDestination {
                case .activeDownloads:
                    states = [
                        .created, .resolving, .ready, .queued, .downloading,
                        .postProcessing, .paused, .interrupted,
                    ]
                case .completedDownloads:
                    states = [.completed]
                case .failedDownloads:
                    states = [.failed]
                default:
                    states = []
                }
                let jobs = try await downloadRepository.jobs(DownloadJobQuery(
                    states: states,
                    limit: 500
                ))
                let mediaPage = try await libraryRepository.page(LibraryQuery(
                    searchText: searchText,
                    limit: 500
                ))
                let visibleMediaIDs = Set(mediaPage.items.map(\.id))
                let filteredJobs = searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty ? jobs : jobs.filter { visibleMediaIDs.contains($0.mediaItemID) }
                guard loadGeneration == generation, !Task.isCancelled else { return }
                downloadJobs = filteredJobs
                items = mediaPage.items.filter { item in
                    filteredJobs.contains { $0.mediaItemID == item.id }
                }
                totalCount = filteredJobs.count
            }
            if let selectedMediaItemID,
               !items.contains(where: { $0.id == selectedMediaItemID }) {
                self.selectedMediaItemID = nil
            }
            if let selectedDownloadJobID,
               !downloadJobs.contains(where: { $0.id == selectedDownloadJobID }) {
                self.selectedDownloadJobID = nil
            }
            await refreshNavigationCounts()
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard loadGeneration == generation else { return }
            isLoading = false
            alert = AppAlert(title: "Could not load this view", message: Self.userFacingMessage(for: error))
        }
    }

    func addLink(
        _ url: URL,
        destination: SaveDestination,
        allowDuplicate: Bool = false,
        metadata: ResolvedMediaMetadata? = nil
    ) async throws -> SaveLinkResult {
        guard let libraryRepository else {
            throw LibraryDomainError.recordNotFound
        }
        var result = try await libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: url,
            destination: destination,
            allowDuplicate: allowDuplicate
        ))
        if case .saved(let item) = result {
            if let metadata,
               let updated = try? await libraryRepository.updateMedia(UpdateMediaCommand(
                   id: item.id,
                   workspaceID: item.workspaceID,
                   expectedRevision: item.version.revision,
                   metadata: MediaMetadataUpdate(
                       title: metadata.title,
                       creator: metadata.creator,
                       description: nil,
                       durationSeconds: metadata.durationSeconds,
                       thumbnailURL: metadata.thumbnailURL,
                       status: metadata.title == nil ? .failed : .resolved,
                       errorCode: metadata.title == nil ? "missing_title" : nil
                   )
               )) {
                result = .saved(updated)
            }
            await refreshCollections()
            await reloadNow()
            if case .saved(let savedItem) = result {
                selectedMediaItemID = savedItem.id
            }
        }
        return result
    }

    func resolveMetadata(for url: URL) async throws -> ResolvedMediaMetadata {
        guard let metadataResolver else {
            throw MetadataResolutionError.engineUnavailable
        }
        return try await metadataResolver.resolve(url)
    }

    func isResolvingMetadata(for item: LibraryItemSummary) -> Bool {
        resolvingMetadataIDs.contains(item.id)
    }

    func refreshMetadata(_ item: LibraryItemSummary) {
        Task { [weak self] in
            await self?.resolveAndStoreMetadata(item, reportsFailure: true)
        }
    }

    func rename(_ item: LibraryItemSummary, to rawTitle: String) {
        guard let libraryRepository else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 4_096 else {
            alert = AppAlert(
                title: "Enter a shorter name",
                message: "Media names must contain between 1 and 4,096 UTF-8 bytes."
            )
            return
        }
        Task { [weak self] in
            do {
                let media = item.mediaItem
                _ = try await libraryRepository.updateMedia(UpdateMediaCommand(
                    id: media.id,
                    workspaceID: media.workspaceID,
                    expectedRevision: media.version.revision,
                    metadata: MediaMetadataUpdate(
                        title: title,
                        creator: media.creator,
                        description: media.description,
                        durationSeconds: media.durationSeconds,
                        thumbnailURL: media.thumbnailURL,
                        status: .resolved
                    )
                ))
                await self?.reloadNow()
            } catch {
                self?.alert = AppAlert(
                    title: "Could not rename this item",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    func createCollection(named rawName: String) async -> Collection? {
        guard let libraryRepository else { return nil }
        do {
            let collection = try await libraryRepository.createCollection(
                CreateCollectionCommand(name: rawName)
            )
            await refreshCollections()
            destination = .collection(collection.id)
            return collection
        } catch {
            alert = AppAlert(
                title: "Could not create the collection",
                message: Self.userFacingMessage(for: error)
            )
            return nil
        }
    }

    func setFavorite(_ item: LibraryItemSummary, value: Bool) {
        guard let libraryRepository else { return }
        Task { [weak self] in
            do {
                try await libraryRepository.setFavorite(
                    mediaID: item.id,
                    workspaceID: item.mediaItem.workspaceID,
                    value: value
                )
                await self?.reloadNow()
            } catch {
                self?.alert = AppAlert(
                    title: "Could not update Favorites",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    func setCollectionMembership(
        item: LibraryItemSummary,
        collectionID: CollectionID,
        value: Bool
    ) {
        guard let libraryRepository else { return }
        let organizesInbox = destination == .inbox && value
        Task { [weak self] in
            do {
                if organizesInbox {
                    try await libraryRepository.organizeFromInbox(
                        mediaID: item.id,
                        workspaceID: item.mediaItem.workspaceID,
                        collectionIDs: [collectionID]
                    )
                } else {
                    try await libraryRepository.setCollectionMembership(MembershipCommand(
                        workspaceID: item.mediaItem.workspaceID,
                        mediaItemID: item.id,
                        collectionID: collectionID,
                        isMember: value
                    ))
                }
                await self?.reloadNow()
            } catch {
                self?.alert = AppAlert(
                    title: "Could not update the collection",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    func removeFromInbox(_ item: LibraryItemSummary) {
        guard let libraryRepository else { return }
        Task { [weak self] in
            do {
                try await libraryRepository.organizeFromInbox(
                    mediaID: item.id,
                    workspaceID: item.mediaItem.workspaceID,
                    collectionIDs: []
                )
                await self?.reloadNow()
            } catch {
                self?.alert = AppAlert(
                    title: "Could not clear this item from Inbox",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    func addExistingMedia(
        _ mediaItem: MediaItem,
        to collectionID: CollectionID
    ) async throws {
        guard let libraryRepository else {
            throw LibraryDomainError.recordNotFound
        }
        try await libraryRepository.setCollectionMembership(MembershipCommand(
            workspaceID: mediaItem.workspaceID,
            mediaItemID: mediaItem.id,
            collectionID: collectionID,
            isMember: true
        ))
        await reloadNow()
    }

    func deleteFromLibrary(_ item: LibraryItemSummary) {
        guard let libraryRepository else { return }
        Task { [weak self] in
            do {
                try await libraryRepository.tombstoneMedia(
                    id: item.id,
                    workspaceID: item.mediaItem.workspaceID,
                    expectedRevision: item.mediaItem.version.revision
                )
                await self?.reloadNow()
            } catch {
                self?.alert = AppAlert(
                    title: "Could not remove this item",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    func copySourceURL(_ item: LibraryItemSummary) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            item.mediaItem.sourceURL.absoluteString,
            forType: .string
        )
    }

    func openSource(_ item: LibraryItemSummary) {
        NSWorkspace.shared.open(item.mediaItem.sourceURL)
    }

    func revealLocalFile(_ item: LibraryItemSummary) {
        guard let downloadRepository else { return }
        Task { [weak self] in
            do {
                let assets = try await downloadRepository.localAssets(mediaItemID: item.id)
                guard let asset = assets.first(where: { $0.status == .available }),
                      let url = Self.resolve(asset: asset),
                      FileManager.default.fileExists(atPath: url.path) else {
                    if let missing = assets.first(where: { $0.status == .available }) {
                        _ = try await downloadRepository.markLocalAssetMissing(id: missing.id)
                        await self?.reloadNow()
                    }
                    self?.alert = AppAlert(
                        title: "Local file not found",
                        message: "The library link is safe. Download the file again on this Mac when you need it."
                    )
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self?.alert = AppAlert(
                    title: "Could not reveal the file",
                    message: Self.userFacingMessage(for: error)
                )
            }
        }
    }

    private func refreshCollections() async {
        guard let libraryRepository else { return }
        do {
            collections = try await libraryRepository.collections(
                workspaceID: VidindirIdentity.personalWorkspace
            )
        } catch {
            alert = AppAlert(
                title: "Could not load collections",
                message: Self.userFacingMessage(for: error)
            )
        }
    }

    private func refreshNavigationCounts() async {
        guard let libraryRepository else { return }
        do {
            async let inboxPage = libraryRepository.page(LibraryQuery(scope: .inbox, limit: 1))
            async let libraryPage = libraryRepository.page(LibraryQuery(scope: .all, limit: 1))
            async let favoritesPage = libraryRepository.page(LibraryQuery(scope: .favorites, limit: 1))
            let (inbox, library, favorites) = try await (inboxPage, libraryPage, favoritesPage)
            inboxCount = inbox.totalCount
            libraryCount = library.totalCount
            favoritesCount = favorites.totalCount
        } catch {
            // Counts are navigation hints. The authoritative view remains usable
            // if a transient count query cannot be completed.
        }
    }

    private func refreshMissingMetadataInBackground() {
        guard metadataRefreshTask == nil,
              metadataResolver != nil,
              libraryRepository != nil else { return }
        metadataRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.metadataRefreshTask = nil }

            // Inbox is only the current view, not the complete library. Resolve
            // missing details from every scope so a link saved directly to
            // Library never remains labelled with only its source website.
            let page: LibraryPage
            do {
                guard let libraryRepository = self.libraryRepository else { return }
                page = try await libraryRepository.page(LibraryQuery(
                    scope: .all,
                    limit: 100
                ))
            } catch {
                return
            }
            let candidates = page.items.filter {
                $0.mediaItem.title == nil && $0.mediaItem.metadataStatus != .resolved
            }
            for item in candidates.prefix(12) {
                guard !Task.isCancelled else { break }
                await self.resolveAndStoreMetadata(item, reportsFailure: false)
            }
        }
    }

    private func resolveAndStoreMetadata(
        _ item: LibraryItemSummary,
        reportsFailure: Bool
    ) async {
        guard let libraryRepository,
              let metadataResolver,
              !resolvingMetadataIDs.contains(item.id) else { return }
        resolvingMetadataIDs.insert(item.id)
        defer { resolvingMetadataIDs.remove(item.id) }

        do {
            let metadata = try await metadataResolver.resolve(item.mediaItem.sourceURL)
            let media = item.mediaItem
            _ = try await libraryRepository.updateMedia(UpdateMediaCommand(
                id: media.id,
                workspaceID: media.workspaceID,
                expectedRevision: media.version.revision,
                metadata: MediaMetadataUpdate(
                    title: metadata.title ?? media.title,
                    creator: metadata.creator ?? media.creator,
                    description: media.description,
                    durationSeconds: metadata.durationSeconds ?? media.durationSeconds,
                    thumbnailURL: metadata.thumbnailURL ?? media.thumbnailURL,
                    status: (metadata.title ?? media.title) == nil ? .failed : .resolved,
                    errorCode: (metadata.title ?? media.title) == nil ? "missing_title" : nil
                )
            ))
            await reloadNow()
        } catch {
            let media = item.mediaItem
            _ = try? await libraryRepository.updateMedia(UpdateMediaCommand(
                id: media.id,
                workspaceID: media.workspaceID,
                expectedRevision: media.version.revision,
                metadata: MediaMetadataUpdate(
                    title: media.title,
                    creator: media.creator,
                    description: media.description,
                    durationSeconds: media.durationSeconds,
                    thumbnailURL: media.thumbnailURL,
                    status: .failed,
                    errorCode: "metadata_unavailable"
                )
            ))
            await reloadNow()
            if reportsFailure {
                alert = AppAlert(
                    title: "Video details are unavailable",
                    message: "Vidindir could not read this link's title right now. You can still give it a custom name or try again later."
                )
            }
        }
    }

    private func scheduleReload(immediately: Bool) {
        guard didBootstrap else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            await self?.reloadNow()
        }
    }

    private static func resolve(asset: LocalAsset) -> URL? {
        if let bookmark = asset.fileBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
            stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        guard NSString(string: asset.lastKnownPath).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: asset.lastKnownPath)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        switch error {
        case LibraryDomainError.invalidSourceURL:
            return "Enter a valid HTTP or HTTPS media link."
        case LibraryDomainError.emptyName:
            return "Enter a name."
        case LibraryDomainError.concurrentModification:
            return "This item changed elsewhere. Reload the library and try again."
        case LibraryDomainError.recordNotFound:
            return "This item is no longer available."
        default:
            return "Vidindir could not finish that library operation."
        }
    }
}
