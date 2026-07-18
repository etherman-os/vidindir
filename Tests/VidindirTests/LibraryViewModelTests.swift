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
        #expect(model.items.map(\.id) == [saved.id])
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
            destination: .inbox
        ))

        let model = fixture.makeModel()
        await model.bootstrapNow()

        try await eventually {
            model.items.first?.mediaItem.title == "Resolved Video"
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
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
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
