import Foundation
import Testing
import VidindirDomain
@testable import Vidindir
@testable import VidindirPersistence

@Suite("Native library view model")
struct LibraryViewModelTests {
    @Test @MainActor func bootstrapsInboxAndAppliesResolvedMetadataWhenSaving() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()
        await model.bootstrapNow()

        #expect(model.isAvailable)
        #expect(model.collections.contains { $0.kind == .systemInbox })
        #expect(model.items.isEmpty)

        let url = try #require(URL(string: "https://example.com/library-video"))
        let metadata = try await model.resolveMetadata(for: url)
        let result = try await model.addLink(
            url,
            destination: .inbox,
            metadata: metadata
        )
        guard case .saved(let saved) = result else {
            Issue.record("Expected a saved item")
            return
        }

        #expect(saved.title == "Resolved Video")
        #expect(saved.creator == "Etherman")
        #expect(saved.durationSeconds == 95)
        try await eventually { model.items.map(\.id) == [saved.id] }
        #expect(model.items.first?.mediaItem.metadataStatus == .resolved)
    }

    @Test @MainActor func destinationsSearchAndCollectionsUseTheSameStoredItem() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()
        await model.bootstrapNow()
        let url = try #require(URL(string: "https://example.com/searchable"))
        let saveResult = try await model.addLink(
            url,
            destination: .inbox,
            metadata: ResolvedMediaMetadata(
                title: "Native SwiftUI Research",
                creator: "Etherman",
                durationSeconds: 60,
                thumbnailURL: nil,
                sourceLabel: "Generic"
            )
        )
        let item = try savedItem(saveResult)
        let collection = try #require(await model.createCollection(named: "Programming"))
        try await fixture.libraryRepository.organizeFromInbox(
            mediaID: item.id,
            workspaceID: item.workspaceID,
            collectionIDs: [collection.id]
        )

        model.destination = .collection(collection.id)
        model.searchText = "swift research"
        await model.reloadNow()
        #expect(model.items.map(\.id) == [item.id])
        #expect(model.totalCount == 1)

        model.destination = .inbox
        model.searchText = ""
        await model.reloadNow()
        #expect(model.items.isEmpty)

        model.destination = .library
        await model.reloadNow()
        #expect(model.items.map(\.id) == [item.id])
    }

    @Test @MainActor func unavailableDatabaseFailsClosedWithoutInventingAnEmptyStore() async {
        let model = LibraryViewModel(
            libraryRepository: nil,
            downloadRepository: nil,
            legacyImporter: nil,
            legacyHistoryData: nil,
            startupError: "Preserved database"
        )

        await model.bootstrapNow()
        #expect(!model.isAvailable)
        #expect(model.startupError == "Preserved database")
        #expect(model.items.isEmpty)
    }

    @Test @MainActor func bootstrapRepairsPreviouslyUnresolvedMetadata() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let url = try #require(URL(string: "https://x.com/example/status/1234567890"))
        _ = try await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: url,
            destination: .libraryOnly
        ))

        let model = fixture.makeModel()
        await model.bootstrapNow()
        model.destination = .library
        await model.reloadNow()

        try await eventually {
            await model.reloadNow()
            return model.items.first?.mediaItem.title == "Resolved Video"
                && model.items.first?.mediaItem.creator == "Etherman"
                && model.items.first?.mediaItem.metadataStatus == .resolved
        }
    }

    @Test @MainActor func customNamePersistsAndPreventsAutomaticReplacement() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()
        await model.bootstrapNow()
        let url = try #require(URL(string: "https://x.com/example/status/9876543210"))
        let saved = try savedItem(await model.addLink(url, destination: .inbox))
        try await eventually { model.items.contains { $0.id == saved.id } }
        let item = try #require(model.items.first { $0.id == saved.id })

        model.rename(item, to: "My custom clip name")

        try await eventually {
            model.items.first(where: { $0.id == saved.id })?.mediaItem.title
                == "My custom clip name"
        }
        let renamed = try #require(model.items.first { $0.id == saved.id })
        #expect(renamed.mediaItem.metadataStatus == .resolved)

        await model.bootstrapNow()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.items.first(where: { $0.id == saved.id })?.mediaItem.title == "My custom clip name")
    }

    @Test @MainActor func renameRetriesAfterAConcurrentMetadataUpdate() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = LibraryViewModel(
            libraryRepository: fixture.libraryRepository,
            downloadRepository: fixture.downloadRepository,
            legacyImporter: nil,
            legacyHistoryData: nil,
            metadataResolver: nil
        )
        await model.bootstrapNow()
        let saved = try savedItem(await model.addLink(
            URL(string: "https://example.com/concurrent-rename")!,
            destination: .libraryOnly
        ))
        model.destination = .library
        await model.reloadNow()
        let staleSummary = try #require(model.items.first { $0.id == saved.id })
        _ = try await fixture.libraryRepository.updateMedia(UpdateMediaCommand(
            id: saved.id,
            workspaceID: saved.workspaceID,
            expectedRevision: saved.version.revision,
            metadata: MediaMetadataUpdate(
                title: "Background metadata title",
                creator: "Metadata resolver",
                description: nil,
                durationSeconds: nil,
                thumbnailURL: nil,
                status: .resolved
            )
        ))

        model.rename(staleSummary, to: "User title wins")

        try await eventually {
            await model.reloadNow()
            return model.items.first(where: { $0.id == saved.id })?.mediaItem.title
                == "User title wins"
        }
        #expect(model.items.first(where: { $0.id == saved.id })?.mediaItem.creator
            == "Metadata resolver")
    }

    @Test @MainActor func clearingInboxKeepsTheItemInAllMediaAndUpdatesCounts() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()
        await model.bootstrapNow()
        let url = try #require(URL(string: "https://example.com/inbox-review"))
        let saved = try savedItem(await model.addLink(
            url,
            destination: .inbox,
            metadata: ResolvedMediaMetadata(
                title: "Review Later",
                creator: nil,
                durationSeconds: nil,
                thumbnailURL: nil,
                sourceLabel: "Generic"
            )
        ))
        try await eventually { model.items.contains { $0.id == saved.id } }
        let inboxItem = try #require(model.items.first { $0.id == saved.id })
        #expect(model.inboxCount == 1)
        #expect(model.libraryCount == 1)

        model.removeFromInbox(inboxItem)
        try await eventually {
            await model.reloadNow()
            return model.items.isEmpty && model.inboxCount == 0 && model.libraryCount == 1
        }

        model.destination = .library
        await model.reloadNow()
        #expect(model.items.map(\.id) == [saved.id])
    }

    @Test @MainActor func paginatesPastTheFirstHundredLibraryItems() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        for index in 0..<105 {
            _ = try await fixture.libraryRepository.saveLink(SaveLinkCommand(
                sourceURL: URL(string: "https://example.com/page-item-\(index)")!,
                destination: .libraryOnly
            ))
        }
        let model = LibraryViewModel(
            libraryRepository: fixture.libraryRepository,
            downloadRepository: fixture.downloadRepository,
            legacyImporter: nil,
            legacyHistoryData: nil,
            metadataResolver: nil
        )
        model.destination = .library
        await model.bootstrapNow()

        #expect(model.items.count == 100)
        #expect(model.totalCount == 105)
        #expect(model.canLoadMore)

        model.loadMore()
        try await eventually {
            model.items.count == 105 && !model.isLoadingMore
        }
        #expect(!model.canLoadMore)
    }

    @Test @MainActor func collectionDownloadSourceLoadsEveryPageAndIgnoresViewSearch() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let setupModel = fixture.makeModel()
        await setupModel.bootstrapNow()
        let collection = try #require(await setupModel.createCollection(named: "Batch"))
        for index in 0..<501 {
            _ = try await fixture.libraryRepository.saveLink(SaveLinkCommand(
                sourceURL: URL(string: "https://example.com/batch-item-\(index)")!,
                destination: .collection(collection.id)
            ))
        }
        let model = LibraryViewModel(
            libraryRepository: fixture.libraryRepository,
            downloadRepository: fixture.downloadRepository,
            legacyImporter: nil,
            legacyHistoryData: nil,
            metadataResolver: nil
        )
        await model.bootstrapNow()
        model.destination = .collection(collection.id)
        model.searchText = "does-not-match"
        await model.reloadNow()
        #expect(model.items.isEmpty)

        let allItems = try await model.allItemsInCurrentCollection()

        #expect(allItems.count == 501)
        #expect(Set(allItems.map(\.id)).count == 501)
    }

    @Test @MainActor func downloadCountsSeparateActiveCompletedAndAttentionStates() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let item = try await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/count-downloads")!,
            destination: .libraryOnly
        ))
        let media = try savedItem(item)
        let active = try await fixture.downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: media.id,
            mediaKind: .video,
            container: "mp4",
            requestJSON: #"{"format":"video"}"#,
            destinationBookmark: nil,
            destinationPath: "/tmp"
        ))
        let cancelled = try await fixture.downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: media.id,
            mediaKind: .video,
            container: "mp4",
            requestJSON: #"{"format":"video"}"#,
            destinationBookmark: nil,
            destinationPath: "/tmp"
        ))
        _ = try await fixture.downloadRepository.transitionJob(
            id: cancelled.id,
            from: .created,
            to: .cancelled
        )

        let model = fixture.makeModel()
        await model.bootstrapNow()

        #expect(model.activeDownloadCount == 1)
        #expect(model.completedDownloadCount == 0)
        #expect(model.failedDownloadCount == 1)
        #expect(active.state == .created)

        model.destination = .failedDownloads
        // Bootstrap also starts metadata repair. Its reload may legitimately
        // supersede this reload, so assert the observable settled state instead
        // of racing that independent background task.
        try await eventually {
            await model.reloadNow()
            return model.downloadJobs.map(\.id) == [cancelled.id]
        }

        model.clearDownloadHistory(.needsAttention)
        try await eventually {
            model.failedDownloadCount == 0 && model.downloadJobs.isEmpty
        }
    }

    @Test @MainActor func deletingTheOpenCollectionReturnsToAllMedia() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()
        await model.bootstrapNow()
        let saved = try savedItem(await model.addLink(
            URL(string: "https://example.com/collection-delete")!,
            destination: .libraryOnly
        ))
        let collection = try #require(await model.createCollection(named: "Temporary"))
        try await fixture.libraryRepository.setCollectionMembership(MembershipCommand(
            workspaceID: saved.workspaceID,
            mediaItemID: saved.id,
            collectionID: collection.id,
            isMember: true
        ))
        model.destination = .collection(collection.id)
        await model.reloadNow()

        model.deleteCollection(collection)
        try await eventually {
            model.destination == .library
                && !model.collections.contains { $0.id == collection.id }
                && model.items.map(\.id) == [saved.id]
        }
    }

    @Test func unresolvedSourceIsNeverPresentedAsTheMediaTitle() async throws {
        let fixture = try LibraryModelFixture()
        defer { fixture.remove() }
        let url = try #require(URL(string: "https://youtube.com/watch?v=presentation"))
        let result = try await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: url,
            destination: .libraryOnly
        ))
        let item = try savedItem(result)

        #expect(item.displayTitle == "Fetching video details…")
        #expect(item.displayTitle != item.sourceURL.host)
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        guard clock.now < deadline else {
            Issue.record("Condition was not met before the timeout")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func savedItem(
    _ result: SaveLinkResult
) throws -> MediaItem {
    switch result {
    case .saved(let item): item
    case .duplicate:
        throw LibraryModelTestError.expectedSaved
    }
}

private final class LibraryModelFixture: @unchecked Sendable {
    let rootURL: URL
    let database: LibraryDatabase
    let libraryRepository: GRDBLibraryRepository
    let downloadRepository: GRDBDownloadJobRepository

    init() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-library-model-tests-\(UUID().uuidString)", isDirectory: true)
        database = try LibraryDatabase(
            url: rootURL.appendingPathComponent("Library.sqlite"),
            configuration: LibraryDatabaseConfiguration(
                currentDeviceID: DeviceID(),
                deviceDisplayName: "Test Mac",
                now: { now }
            )
        )
        libraryRepository = GRDBLibraryRepository(database: database, now: { now })
        downloadRepository = GRDBDownloadJobRepository(database: database, now: { now })
    }

    @MainActor
    func makeModel() -> LibraryViewModel {
        LibraryViewModel(
            libraryRepository: libraryRepository,
            downloadRepository: downloadRepository,
            legacyImporter: nil,
            legacyHistoryData: nil,
            metadataResolver: FixedMetadataResolver()
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct FixedMetadataResolver: MediaMetadataResolving {
    func resolve(_ sourceURL: URL) async throws -> ResolvedMediaMetadata {
        ResolvedMediaMetadata(
            title: "Resolved Video",
            creator: "Etherman",
            durationSeconds: 95,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            sourceLabel: "Generic"
        )
    }
}

private enum LibraryModelTestError: Error {
    case expectedSaved
}
