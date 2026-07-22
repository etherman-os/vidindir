import Foundation
import Testing
import VidindirDomain
@testable import Vidindir
@testable import VidindirPersistence

@Suite("Persistent download coordinator")
struct DownloadCoordinatorTests {
    @Test func batchQueueContinuesPastAnInvalidItemAndPreservesFIFOOrder() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let first = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/batch-first")!,
            destination: .libraryOnly
        )))
        let invalid = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/batch-invalid")!,
            destination: .libraryOnly
        )))
        let third = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/batch-third")!,
            destination: .libraryOnly
        )))
        let backend = ImmediateCoordinatorBackend()
        let coordinator = fixture.makeCoordinator(backend: backend)
        let invalidRequest = DownloadRequest(
            sourceURL: URL(string: "ftp://example.com/not-downloadable")!,
            format: .mp4,
            destinationDirectory: fixture.rootURL
        )

        let result = await coordinator.enqueueBatch([
            DownloadBatchEntry(
                request: fixture.request(url: first.sourceURL),
                mediaItemID: first.id
            ),
            DownloadBatchEntry(request: invalidRequest, mediaItemID: invalid.id),
            DownloadBatchEntry(
                request: fixture.request(url: third.sourceURL),
                mediaItemID: third.id
            ),
        ])

        #expect(result.queuedJobIDs.count == 2)
        #expect(result.failures.map(\.mediaItemID) == [invalid.id])
        #expect(try await fixture.downloadRepository.job(
            id: result.queuedJobIDs[0]
        ).queuePosition == 1)
        #expect(try await fixture.downloadRepository.job(
            id: result.queuedJobIDs[1]
        ).queuePosition == 2)

        await coordinator.start()
        try await eventually {
            try await fixture.downloadRepository.jobCount(DownloadJobQuery(
                states: [.completed]
            )) == 2
        }
        #expect(backend.startedURLs == [first.sourceURL, third.sourceURL])
    }

    @Test func queuesInDurableFIFOOrderAndKeepsTheSelectedDuplicateIdentity() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let duplicateURL = URL(string: "https://example.com/duplicate")!
        _ = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: duplicateURL,
            destination: .libraryOnly
        )))
        let selectedDuplicate = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: duplicateURL,
            destination: .libraryOnly,
            allowDuplicate: true
        )))
        let other = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/other")!,
            destination: .libraryOnly
        )))
        let backend = ImmediateCoordinatorBackend()
        let coordinator = fixture.makeCoordinator(backend: backend)

        let firstID = try await coordinator.enqueue(
            fixture.request(url: duplicateURL),
            mediaItemID: selectedDuplicate.id
        )
        let secondID = try await coordinator.enqueue(
            fixture.request(url: other.sourceURL),
            mediaItemID: other.id
        )

        #expect(backend.startedURLs.isEmpty)
        let firstQueued = try await fixture.downloadRepository.job(id: firstID)
        let secondQueued = try await fixture.downloadRepository.job(id: secondID)
        #expect(firstQueued.mediaItemID == selectedDuplicate.id)
        #expect(firstQueued.queuePosition == 1)
        #expect(secondQueued.queuePosition == 2)

        await coordinator.start()
        try await eventually {
            try await fixture.downloadRepository.jobCount(DownloadJobQuery(
                states: [.completed]
            )) == 2
        }

        #expect(backend.startedURLs == [duplicateURL, other.sourceURL])
        #expect(backend.maximumConcurrentDownloads == 1)
        #expect(try await fixture.downloadRepository.job(id: firstID).attemptCount == 1)
        #expect(try await fixture.downloadRepository.job(id: secondID).attemptCount == 1)
    }

    @Test func drainsAQueuedJobAfterRelaunch() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let backend = ImmediateCoordinatorBackend()
        let originalCoordinator = fixture.makeCoordinator(backend: backend)
        let jobID = try await originalCoordinator.enqueue(
            fixture.request(url: URL(string: "https://example.com/relaunch")!)
        )
        #expect(try await fixture.downloadRepository.job(id: jobID).state == .queued)

        let relaunchedCoordinator = fixture.makeCoordinator(backend: backend)
        await relaunchedCoordinator.start()
        try await eventually {
            try await fixture.downloadRepository.job(id: jobID).state == .completed
        }

        #expect(backend.startedURLs == [URL(string: "https://example.com/relaunch")!])
    }

    @Test func retryReusesAFailedJobAndIncrementsItsAttempt() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let backend = FailOnceCoordinatorBackend()
        let coordinator = fixture.makeCoordinator(backend: backend)
        let jobID = try await coordinator.enqueue(
            fixture.request(url: URL(string: "https://example.com/retry")!)
        )
        await coordinator.start()
        try await eventually {
            try await fixture.downloadRepository.job(id: jobID).state == .failed
        }
        #expect(try await fixture.downloadRepository.job(id: jobID).state == .failed)

        let retriedID = try await coordinator.retry(jobID)
        #expect(retriedID == jobID)
        try await eventually {
            try await fixture.downloadRepository.job(id: jobID).state == .completed
        }
        let retriedJob = try await fixture.downloadRepository.job(id: jobID)
        #expect(retriedJob.state == .completed)
        #expect(retriedJob.errorSummary == nil)
        #expect(try await fixture.downloadRepository.job(id: jobID).attemptCount == 2)
    }

    @Test func cancellationStopsTheActiveBackendAndPersistsTheTerminalState() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let backend = BlockingCoordinatorBackend()
        let coordinator = fixture.makeCoordinator(backend: backend)
        let jobID = try await coordinator.enqueue(
            fixture.request(url: URL(string: "https://example.com/cancel")!)
        )
        await coordinator.start()
        try await eventually { backend.isDownloading }

        await coordinator.cancel(jobID)
        try await eventually {
            try await fixture.downloadRepository.job(id: jobID).state == .cancelled
        }

        let cancelledState = try await fixture.downloadRepository.job(id: jobID).state
        #expect(cancelledState == .cancelled)
        #expect(backend.cancelCount == 1)
        #expect(backend.observedTaskCancellation)
        #expect(!backend.isDownloading)
    }

    @Test func launchRecoveryInterruptsInflightWorkAndResumesReadyWork() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let readyMedia = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/ready")!,
            destination: .libraryOnly
        )))
        let interruptedMedia = try saved(await fixture.libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: URL(string: "https://example.com/interrupted")!,
            destination: .libraryOnly
        )))
        var ready = try await fixture.makeJob(mediaItemID: readyMedia.id)
        ready = try await fixture.downloadRepository.transitionJob(
            id: ready.id, from: .created, to: .resolving
        )
        ready = try await fixture.downloadRepository.transitionJob(
            id: ready.id, from: .resolving, to: .ready
        )
        var interrupted = try await fixture.makeJob(mediaItemID: interruptedMedia.id)
        interrupted = try await fixture.downloadRepository.transitionJob(
            id: interrupted.id, from: .created, to: .resolving
        )
        interrupted = try await fixture.downloadRepository.transitionJob(
            id: interrupted.id, from: .resolving, to: .ready
        )
        interrupted = try await fixture.downloadRepository.transitionJob(
            id: interrupted.id, from: .ready, to: .queued
        )
        interrupted = try await fixture.downloadRepository.transitionJob(
            id: interrupted.id, from: .queued, to: .downloading
        )
        let readyID = ready.id
        let interruptedID = interrupted.id

        let backend = ImmediateCoordinatorBackend()
        let coordinator = fixture.makeCoordinator(backend: backend)
        await coordinator.start()
        try await eventually {
            try await fixture.downloadRepository.job(id: readyID).state == .completed
        }

        #expect(try await fixture.downloadRepository.job(id: interruptedID).state == .interrupted)
        #expect(backend.startedURLs == [readyMedia.sourceURL])
    }
}

private final class CoordinatorFixture: @unchecked Sendable {
    let rootURL: URL
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let database: LibraryDatabase
    let libraryRepository: GRDBLibraryRepository
    let downloadRepository: GRDBDownloadJobRepository

    init() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-coordinator-tests-\(UUID().uuidString)")
        database = try LibraryDatabase(
            url: rootURL.appendingPathComponent("Library.sqlite"),
            configuration: LibraryDatabaseConfiguration(
                currentDeviceID: DeviceID(),
                deviceDisplayName: "Coordinator Test Mac",
                now: { fixedNow }
            )
        )
        libraryRepository = GRDBLibraryRepository(database: database, now: { fixedNow })
        downloadRepository = GRDBDownloadJobRepository(database: database, now: { fixedNow })
    }

    func makeCoordinator(backend: any DownloadBackend) -> DownloadCoordinator {
        DownloadCoordinator(
            libraryRepository: libraryRepository,
            downloadRepository: downloadRepository,
            backend: backend,
            verifyAsset: { url in
                try VerifiedLocalAsset(
                    fileBookmark: Data("bookmark".utf8),
                    absolutePath: url.path,
                    fileSizeBytes: 1,
                    container: url.pathExtension,
                    verifiedAt: self.now
                )
            },
            now: { self.now }
        )
    }

    func request(url: URL) -> DownloadRequest {
        DownloadRequest(
            sourceURL: url,
            format: .mp4,
            destinationDirectory: rootURL
        )
    }

    func makeJob(mediaItemID: MediaItemID) async throws -> DownloadJob {
        let sourceURL = try await sourceURL(for: mediaItemID)
        return try await downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: mediaItemID,
            backendID: "yt-dlp",
            mediaKind: .video,
            container: "mp4",
            requestJSON: try DownloadRequestSnapshot(request: request(url: sourceURL)).encoded(),
            destinationBookmark: nil,
            destinationPath: rootURL.path
        ))
    }

    private func sourceURL(for mediaItemID: MediaItemID) async throws -> URL {
        let summaries = try await libraryRepository.summaries(
            mediaItemIDs: [mediaItemID],
            workspaceID: VidindirIdentity.personalWorkspace
        )
        return try #require(summaries.first?.mediaItem.sourceURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class ImmediateCoordinatorBackend: DownloadBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var URLs: [URL] = []

    var isDownloading: Bool { lock.withLock { activeCount > 0 } }
    var startedURLs: [URL] { lock.withLock { URLs } }
    var maximumConcurrentDownloads: Int { lock.withLock { maximumActiveCount } }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        lock.withLock {
            activeCount += 1
            maximumActiveCount = max(maximumActiveCount, activeCount)
            URLs.append(request.sourceURL)
        }
        defer { lock.withLock { activeCount -= 1 } }
        onEvent(.progress(DownloadBackendProgress(fractionCompleted: 0.5)))
        onEvent(.postProcessing)
        try await Task.sleep(for: .milliseconds(5))
        var record = DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            status: .completed
        )
        record.outputFileURL = request.destinationDirectory
            .appendingPathComponent("\(request.sourceURL.lastPathComponent).mp4")
        record.finishedAt = Date()
        return record
    }

    func cancelCurrentDownload() {}
}

private final class FailOnceCoordinatorBackend: DownloadBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var attempt = 0
    var isDownloading: Bool { false }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        let currentAttempt = lock.withLock {
            attempt += 1
            return attempt
        }
        if currentAttempt == 1 {
            throw CoordinatorTestError.transient
        }
        onEvent(.postProcessing)
        var record = DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            status: .completed
        )
        record.outputFileURL = request.destinationDirectory.appendingPathComponent("retry.mp4")
        return record
    }

    func cancelCurrentDownload() {}
}

private final class BlockingCoordinatorBackend: DownloadBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var cancellations = 0
    private var taskCancellationObserved = false

    var isDownloading: Bool { lock.withLock { active } }
    var cancelCount: Int { lock.withLock { cancellations } }
    var observedTaskCancellation: Bool { lock.withLock { taskCancellationObserved } }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        lock.withLock { active = true }
        defer { lock.withLock { active = false } }
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            lock.withLock { taskCancellationObserved = true }
            throw error
        }
        return DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory
        )
    }

    func cancelCurrentDownload() {
        lock.withLock { cancellations += 1 }
    }
}

private func saved(_ result: SaveLinkResult) throws -> MediaItem {
    guard case .saved(let item) = result else {
        throw CoordinatorTestError.expectedSaved
    }
    return item
}

private func eventually(
    timeout: Duration = .seconds(3),
    condition: @escaping @Sendable () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while try await condition() == false {
        guard clock.now < deadline else {
            Issue.record("Condition was not met before timeout")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private enum CoordinatorTestError: LocalizedError {
    case transient
    case expectedSaved

    var errorDescription: String? {
        switch self {
        case .transient: "Temporary network failure"
        case .expectedSaved: "Expected a saved media item"
        }
    }
}
