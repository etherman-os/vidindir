import Foundation
import VidindirDomain
@testable import VidindirPersistence

final class PersistenceFixture: Sendable {
    let rootURL: URL
    let database: LibraryDatabase
    let repository: GRDBLibraryRepository
    let downloadRepository: GRDBDownloadJobRepository
    let now: Date
    let deviceID: DeviceID

    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws {
        self.now = now
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        deviceID = DeviceID()
        database = try LibraryDatabase(
            url: rootURL.appendingPathComponent("Library.sqlite"),
            configuration: LibraryDatabaseConfiguration(
                currentDeviceID: deviceID,
                deviceDisplayName: "Test Mac",
                appVersion: "1.0-test",
                now: { now }
            )
        )
        repository = GRDBLibraryRepository(
            database: database,
            now: { now }
        )
        downloadRepository = GRDBDownloadJobRepository(
            database: database,
            now: { now }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

extension PersistenceFixture {
    func makeMediaItem(
        source: String = "https://example.com/video-\(UUID().uuidString)"
    ) async throws -> MediaItem {
        guard let url = URL(string: source) else {
            throw FixtureError.invalidURL
        }
        return try requireSaved(await repository.saveLink(
            SaveLinkCommand(sourceURL: url, destination: .libraryOnly)
        ))
    }

    func makeDownloadJob(
        mediaItemID: MediaItemID,
        requestJSON: String = #"{"format":"video","quality":"best"}"#
    ) async throws -> DownloadJob {
        try await downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: mediaItemID,
            mediaKind: .video,
            container: "mp4",
            requestJSON: requestJSON,
            destinationBookmark: Data("destination".utf8),
            destinationPath: "/Users/test/Downloads"
        ))
    }
}

func requireSaved(_ result: SaveLinkResult) throws -> MediaItem {
    guard case .saved(let item) = result else {
        throw FixtureError.expectedSavedItem
    }
    return item
}

enum FixtureError: Error {
    case expectedSavedItem
    case invalidURL
}
