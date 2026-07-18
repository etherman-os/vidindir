import Foundation
import GRDB
import Testing
import VidindirDomain
@testable import VidindirPersistence

@Suite("Durable download job repository")
struct DownloadJobRepositoryTests {
    @Test func completeLifecycleCreatesAvailableAssetAtomically() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()
        var job = try await fixture.makeDownloadJob(mediaItemID: item.id)

        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .created, to: .resolving
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .resolving, to: .ready
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .ready, to: .queued
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .queued, to: .downloading
        )
        job = try await fixture.downloadRepository.updateProgress(
            jobID: job.id,
            update: DownloadProgressUpdate(
                fraction: 0.75,
                downloadedBytes: 750,
                totalBytes: 1_000,
                speedBytesPerSecond: 125,
                estimatedRemainingSeconds: 2
            )
        )
        #expect(job.attemptCount == 1)
        #expect(job.progressFraction == 0.75)

        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .downloading, to: .postProcessing
        )
        let verifiedAt = fixture.now.addingTimeInterval(-1)
        job = try await fixture.downloadRepository.completeJob(
            id: job.id,
            asset: try VerifiedLocalAsset(
                fileBookmark: Data("security-scoped-bookmark".utf8),
                absolutePath: "/Users/test/Downloads/video.mp4",
                fileSizeBytes: 1_000,
                contentType: "video/mp4",
                container: "mp4",
                checksumSHA256: String(repeating: "a", count: 64),
                verifiedAt: verifiedAt
            )
        )

        #expect(job.state == .completed)
        #expect(job.progressFraction == 1)
        #expect(job.localAssetID != nil)
        #expect(job.completedAt == fixture.now)
        let assets = try await fixture.downloadRepository.localAssets(mediaItemID: item.id)
        #expect(assets.count == 1)
        #expect(assets.first?.id == job.localAssetID)
        #expect(assets.first?.status == .available)
        #expect(assets.first?.lastKnownPath == "/Users/test/Downloads/video.mp4")
        #expect(assets.first?.lastVerifiedAt == verifiedAt)

        let completedJobID = job.id.description
        let joined = try await fixture.database.pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM download_jobs j
                    JOIN local_assets a ON a.id = j.local_asset_id
                    WHERE j.id = ? AND j.state = 'completed' AND a.status = 'available'
                    """,
                arguments: [completedJobID]
            )
        }
        #expect(joined == 1)
    }

    @Test func invalidRequestsTransitionsAndProgressAreRejected() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()

        await #expect(throws: LibraryDomainError.invalidDownloadRequest) {
            try await fixture.downloadRepository.createJob(CreateDownloadJobCommand(
                mediaItemID: item.id,
                mediaKind: .video,
                container: "mp4",
                requestJSON: #"{"authorization":"Bearer secret"}"#,
                destinationBookmark: nil,
                destinationPath: "/Users/test/Downloads"
            ))
        }
        await #expect(throws: LibraryDomainError.invalidDownloadRequest) {
            try await fixture.downloadRepository.createJob(CreateDownloadJobCommand(
                mediaItemID: item.id,
                mediaKind: .video,
                container: "mp4",
                requestJSON: #"{"format":"video"}"#,
                destinationBookmark: nil,
                destinationPath: "relative/path"
            ))
        }

        let job = try await fixture.makeDownloadJob(mediaItemID: item.id)
        await #expect(throws: LibraryDomainError.invalidDownloadTransition) {
            try await fixture.downloadRepository.transitionJob(
                id: job.id, from: .created, to: .downloading
            )
        }
        await #expect(throws: LibraryDomainError.invalidDownloadTransition) {
            try await fixture.downloadRepository.updateProgress(
                jobID: job.id,
                update: DownloadProgressUpdate(
                    fraction: 0.5,
                    downloadedBytes: 1,
                    totalBytes: 2,
                    speedBytesPerSecond: 1,
                    estimatedRemainingSeconds: 1
                )
            )
        }

        _ = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .created, to: .resolving
        )
        _ = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .resolving, to: .ready
        )
        _ = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .ready, to: .queued
        )
        _ = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .queued, to: .downloading
        )
        await #expect(throws: LibraryDomainError.invalidProgress) {
            try await fixture.downloadRepository.updateProgress(
                jobID: job.id,
                update: DownloadProgressUpdate(
                    fraction: 1.1,
                    downloadedBytes: 11,
                    totalBytes: 10,
                    speedBytesPerSecond: .infinity,
                    estimatedRemainingSeconds: -1
                )
            )
        }
        await #expect(throws: LibraryDomainError.invalidDownloadTransition) {
            try await fixture.downloadRepository.completeJob(
                id: job.id,
                asset: try VerifiedLocalAsset(
                    fileBookmark: Data([1]),
                    absolutePath: "/tmp/video.mp4",
                    fileSizeBytes: 1
                )
            )
        }
    }

    @Test func failuresCanRetryButTerminalJobsCannotRestart() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()
        var job = try await fixture.makeDownloadJob(mediaItemID: item.id)
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .created, to: .resolving
        )
        job = try await fixture.downloadRepository.failJob(
            id: job.id,
            failure: DownloadFailure(
                category: "network",
                summary: "The connection was interrupted.",
                technicalDetail: "timeout",
                retryAfter: fixture.now.addingTimeInterval(60)
            )
        )
        #expect(job.state == .failed)
        #expect(job.errorCategory == "network")
        #expect(job.retryAfter == fixture.now.addingTimeInterval(60))

        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .failed, to: .queued
        )
        #expect(job.errorSummary == nil)
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .queued, to: .cancelled
        )
        await #expect(throws: LibraryDomainError.invalidDownloadTransition) {
            try await fixture.downloadRepository.transitionJob(
                id: job.id, from: .cancelled, to: .queued
            )
        }
    }

    @Test func launchRecoveryInterruptsOnlyWorkThatWasActuallyInFlight() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()
        var jobs: [DownloadJob] = []
        for _ in 0..<4 {
            jobs.append(try await fixture.makeDownloadJob(mediaItemID: item.id))
        }

        jobs[0] = try await fixture.downloadRepository.transitionJob(
            id: jobs[0].id, from: .created, to: .resolving
        )
        for index in 1...3 {
            jobs[index] = try await fixture.downloadRepository.transitionJob(
                id: jobs[index].id, from: .created, to: .resolving
            )
            jobs[index] = try await fixture.downloadRepository.transitionJob(
                id: jobs[index].id, from: .resolving, to: .ready
            )
            jobs[index] = try await fixture.downloadRepository.transitionJob(
                id: jobs[index].id, from: .ready, to: .queued
            )
        }
        jobs[1] = try await fixture.downloadRepository.transitionJob(
            id: jobs[1].id, from: .queued, to: .downloading
        )
        jobs[2] = try await fixture.downloadRepository.transitionJob(
            id: jobs[2].id, from: .queued, to: .downloading
        )
        jobs[2] = try await fixture.downloadRepository.transitionJob(
            id: jobs[2].id, from: .downloading, to: .postProcessing
        )

        #expect(try await fixture.downloadRepository.interruptActiveJobsAfterLaunch() == 3)
        let interrupted = try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.interrupted])
        )
        #expect(Set(interrupted.map(\.id)) == Set(jobs[0...2].map(\.id)))
        let queued = try await fixture.downloadRepository.jobs(
            DownloadJobQuery(states: [.queued])
        )
        #expect(queued.map(\.id) == [jobs[3].id])
    }

    @Test func databaseRejectsCompletedRowsWithoutMatchingAvailableAsset() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()
        let job = try await fixture.makeDownloadJob(mediaItemID: item.id)

        await #expect(throws: (any Error).self) {
            try await fixture.database.pool.write { db in
                try db.execute(
                    sql: "UPDATE download_jobs SET state = 'completed' WHERE id = ?",
                    arguments: [job.id.description]
                )
            }
        }
        let storedState = try await fixture.database.pool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT state FROM download_jobs WHERE id = ?",
                arguments: [job.id.description]
            )
        }
        #expect(storedState == DownloadJobState.created.rawValue)
    }

    @Test func localFileStatusChangesDoNotDeleteTheLibraryItem() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try await fixture.makeMediaItem()
        var job = try await fixture.makeDownloadJob(mediaItemID: item.id)
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .created, to: .resolving
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .resolving, to: .ready
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .ready, to: .queued
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .queued, to: .downloading
        )
        job = try await fixture.downloadRepository.transitionJob(
            id: job.id, from: .downloading, to: .postProcessing
        )
        job = try await fixture.downloadRepository.completeJob(
            id: job.id,
            asset: try VerifiedLocalAsset(
                fileBookmark: Data([1]),
                absolutePath: "/tmp/video.mp4",
                fileSizeBytes: 4
            )
        )
        let assetID = try #require(job.localAssetID)

        let missing = try await fixture.downloadRepository.markLocalAssetMissing(id: assetID)
        #expect(missing.status == .missing)
        let removed = try await fixture.downloadRepository.markLocalAssetRemoved(id: assetID)
        #expect(removed.status == .removed)
        #expect(removed.removedAt == fixture.now)
        #expect(try await fixture.repository.page(LibraryQuery()).items.map(\.id) == [item.id])
    }
}
