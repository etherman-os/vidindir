import Foundation
import Testing
import VidindirDomain
@testable import Vidindir
@testable import VidindirPersistence

@Suite("Durable live download recording")
struct DurableDownloadRecorderTests {
    @Test func recordsTheFullLifecycleAndVerifiedLocalAsset() async throws {
        let fixture = try RecorderFixture()
        defer { fixture.remove() }
        let outputURL = fixture.rootURL.appendingPathComponent("video.mp4")
        let recorder = fixture.makeRecorder(outputURL: outputURL)
        let request = DownloadRequest(
            sourceURL: try #require(URL(string: "https://example.com/video")),
            format: .mp4,
            destinationDirectory: fixture.rootURL
        )

        try await recorder.begin(request)
        let active = try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.downloading])
        )
        #expect(active.count == 1)
        #expect(active.first?.attemptCount == 1)

        await recorder.recordProgress(DownloadBackendProgress(
            fractionCompleted: 0.5,
            downloadedBytes: 500,
            totalBytes: 1_000,
            speedBytesPerSecond: 100,
            etaSeconds: 5
        ))
        await recorder.recordPostProcessing()
        var record = DownloadRecord(
            sourceURL: request.sourceURL,
            format: .mp4,
            destinationDirectory: fixture.rootURL,
            status: .completed,
            startedAt: fixture.now
        )
        record.outputFileURL = outputURL
        record.finishedAt = fixture.now
        try await recorder.complete(record)

        let completed = try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.completed])
        )
        #expect(completed.count == 1)
        #expect(completed.first?.progressFraction == 1)
        let mediaID = try #require(completed.first?.mediaItemID)
        let assets = try await fixture.downloadRepository.localAssets(mediaItemID: mediaID)
        #expect(assets.map(\.status) == [.available])
        #expect(assets.map(\.lastKnownPath) == [outputURL.path])
        #expect(await recorder.activeJobID() == nil)
    }

    @Test func failuresAndCancellationLeaveRetryableDurableHistory() async throws {
        let fixture = try RecorderFixture()
        defer { fixture.remove() }
        let recorder = fixture.makeRecorder(
            outputURL: fixture.rootURL.appendingPathComponent("unused.mp4")
        )
        let request = DownloadRequest(
            sourceURL: try #require(URL(string: "https://example.com/failure")),
            format: .mp4,
            destinationDirectory: fixture.rootURL
        )

        try await recorder.begin(request)
        await recorder.fail(TestDownloadError.network)
        #expect(try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.failed])
        ).count == 1)

        try await recorder.begin(request)
        await recorder.cancel()
        #expect(try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.cancelled])
        ).count == 1)
        #expect(try await fixture.libraryRepository.page(LibraryQuery()).totalCount == 1)
    }

    @Test @MainActor func appModelPublishesCompletionOnlyAfterDurableCommit() async throws {
        let fixture = try RecorderFixture()
        defer { fixture.remove() }
        let suiteName = "vidindir-recorder-app-model-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let outputURL = fixture.rootURL.appendingPathComponent("model-video.mp4")
        let recorder = fixture.makeRecorder(outputURL: outputURL)
        let sourceURL = try #require(URL(string: "https://example.com/model-video"))
        let backend = ImmediateSuccessfulBackend(outputURL: outputURL)
        let model = AppModel(
            downloadBackend: backend,
            engineManager: AlwaysReadyEngineManager(),
            preferences: DownloadPreferencesStore(
                defaults: defaults,
                fallbackDirectory: fixture.rootURL
            ),
            historyStore: DownloadHistoryStore(defaults: defaults),
            defaults: defaults,
            engineUpdateSchedule: EngineUpdateSchedule(
                interval: .seconds(3_600),
                sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            ),
            durableDownloads: recorder
        )
        model.linkText = sourceURL.absoluteString

        model.startDownload()
        #expect(await eventually { model.phase == .completed })
        let jobs = try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.completed])
        )
        #expect(jobs.count == 1)
        #expect(model.history.first?.outputFileURL == outputURL)
    }

    @MainActor
    private func eventually(
        attempts: Int = 1_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

private final class RecorderFixture: @unchecked Sendable {
    let rootURL: URL
    let now: Date
    let database: LibraryDatabase
    let libraryRepository: GRDBLibraryRepository
    let downloadRepository: GRDBDownloadJobRepository

    init() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        now = fixedNow
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-recorder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        database = try LibraryDatabase(
            url: rootURL.appendingPathComponent("Library.sqlite"),
            configuration: LibraryDatabaseConfiguration(
                currentDeviceID: DeviceID(),
                deviceDisplayName: "Test Mac",
                now: { fixedNow }
            )
        )
        libraryRepository = GRDBLibraryRepository(database: database, now: { fixedNow })
        downloadRepository = GRDBDownloadJobRepository(database: database, now: { fixedNow })
    }

    func makeRecorder(outputURL: URL) -> DurableDownloadRecorder {
        DurableDownloadRecorder(
            libraryRepository: libraryRepository,
            downloadRepository: downloadRepository,
            verifyAsset: { url in
                guard url.standardizedFileURL == outputURL.standardizedFileURL else {
                    throw TestDownloadError.invalidOutput
                }
                return try VerifiedLocalAsset(
                    fileBookmark: Data("test-bookmark".utf8),
                    absolutePath: url.path,
                    fileSizeBytes: 1_000,
                    contentType: "video/mp4",
                    container: "mp4",
                    verifiedAt: self.now
                )
            }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private enum TestDownloadError: LocalizedError {
    case network
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .network: "The network connection was interrupted."
        case .invalidOutput: "The output did not match."
        }
    }
}

private final class ImmediateSuccessfulBackend: DownloadBackend, @unchecked Sendable {
    let outputURL: URL
    var isDownloading: Bool { false }

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        var record = DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            status: .preparing
        )
        onEvent(.started(record))
        onEvent(.progress(DownloadBackendProgress(
            fractionCompleted: 0.8,
            downloadedBytes: 800,
            totalBytes: 1_000,
            speedBytesPerSecond: 100,
            etaSeconds: 2
        )))
        onEvent(.postProcessing)
        record.status = .completed
        record.outputFileURL = outputURL
        record.finishedAt = Date()
        onEvent(.completed(record))
        return record
    }

    func cancelCurrentDownload() {}
}

private final class AlwaysReadyEngineManager: DownloadEngineManaging, @unchecked Sendable {
    var canPrepareAutomatically: Bool { true }
    var setupGuideURL: URL? { nil }
    func currentStatus() -> DownloadEngineStatus { DownloadEngineStatus(isReady: true) }
    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {}
    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        .upToDate(checkedAt: Date())
    }
}
