import Foundation
import VidindirDomain

enum DownloadCoordinatorEvent: Sendable {
    case idle
    case queued(DownloadJobID)
    case started(DownloadJobID, DownloadRequest)
    case backend(DownloadJobID, DownloadBackendEvent)
    case completed(DownloadJobID, DownloadRecord)
    case failed(DownloadJobID, String)
    case cancelled(DownloadJobID)
    case queueUnavailable(String)
}

struct DownloadBatchEntry: Sendable {
    let request: DownloadRequest
    let mediaItemID: MediaItemID
}

struct DownloadBatchEnqueueFailure: Sendable {
    let mediaItemID: MediaItemID
    let summary: String
}

struct DownloadBatchEnqueueResult: Sendable {
    let queuedJobIDs: [DownloadJobID]
    let skippedMediaItemIDs: [MediaItemID]
    let failures: [DownloadBatchEnqueueFailure]
}

actor DownloadCoordinator {
    private let libraryRepository: any LibraryRepository
    private let downloadRepository: any DownloadJobRepository
    private let backend: any DownloadBackend
    private let metadataResolver: (any MediaMetadataResolving)?
    private let verifyAsset: @Sendable (URL) throws -> VerifiedLocalAsset
    private let now: @Sendable () -> Date

    private var subscribers: [UUID: AsyncStream<DownloadCoordinatorEvent>.Continuation] = [:]
    private var workerTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var activeJob: DownloadJob?
    private var lastProgressPersistenceAt: Date?
    private var queueGeneration: UInt64 = 0
    private var cancelledBatchRoots = Set<DownloadJobID>()
    private var didStart = false

    init(
        libraryRepository: any LibraryRepository,
        downloadRepository: any DownloadJobRepository,
        backend: any DownloadBackend,
        metadataResolver: (any MediaMetadataResolving)? = nil,
        verifyAsset: @escaping @Sendable (URL) throws -> VerifiedLocalAsset = LocalAssetVerifier.verify,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.libraryRepository = libraryRepository
        self.downloadRepository = downloadRepository
        self.backend = backend
        self.metadataResolver = metadataResolver
        self.verifyAsset = verifyAsset
        self.now = now
    }

    func events() -> AsyncStream<DownloadCoordinatorEvent> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation in
            subscribers[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(identifier) }
            }
        }
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        _ = try? await downloadRepository.interruptActiveJobsAfterLaunch()

        // A crash after preparation but before the worker wake is safe to
        // recover: ready jobs have a validated, durable request and no process
        // was launched yet.
        while let ready = try? await downloadRepository.jobs(DownloadJobQuery(
            states: [.ready],
            limit: 500
        )), !ready.isEmpty {
            var movedCount = 0
            for job in ready {
                if (try? await downloadRepository.transitionJob(
                    id: job.id,
                    from: .ready,
                    to: .queued
                )) != nil {
                    movedCount += 1
                }
            }
            if movedCount == 0 { break }
        }
        wakeWorker()
    }

    @discardableResult
    func enqueue(
        _ request: DownloadRequest,
        mediaItemID: MediaItemID? = nil,
        parentJobID: DownloadJobID? = nil
    ) async throws -> DownloadJobID {
        try request.validateForDownload()
        var mediaItem = try await resolveMediaItem(
            for: request,
            selectedID: mediaItemID
        )
        let snapshot = try DownloadRequestSnapshot(request: request).encoded()
        var job = try await downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: mediaItem.id,
            parentJobID: parentJobID,
            backendID: "yt-dlp",
            mediaKind: request.format == .mp3 ? .audio : .video,
            container: request.format.rawValue,
            qualityPreset: QualityPreset(rawValue: request.quality.rawValue),
            requestJSON: snapshot,
            destinationBookmark: DownloadRequestSnapshot.bookmark(
                for: request.destinationDirectory
            ),
            destinationPath: request.destinationDirectory.path
        ))

        do {
            job = try await transition(job, to: .resolving)
            if mediaItem.metadataStatus != .resolved,
               let metadataResolver,
               let metadata = try? await metadataResolver.resolve(request.sourceURL),
               let updated = try? await libraryRepository.updateMedia(UpdateMediaCommand(
                   id: mediaItem.id,
                   workspaceID: mediaItem.workspaceID,
                   expectedRevision: mediaItem.version.revision,
                   metadata: MediaMetadataUpdate(
                       title: metadata.title,
                       creator: metadata.creator,
                       description: mediaItem.description,
                       durationSeconds: metadata.durationSeconds,
                       thumbnailURL: metadata.thumbnailURL,
                       status: metadata.title == nil ? .failed : .resolved,
                       errorCode: metadata.title == nil ? "missing_title" : nil
                   )
               )) {
                mediaItem = updated
            }
            job = try await transition(job, to: .ready)
            job = try await transition(job, to: .queued)
        } catch {
            await recordPreparationFailure(jobID: job.id, error: error)
            throw error
        }

        publish(.queued(job.id))
        queueGeneration &+= 1
        wakeWorker()
        return job.id
    }

    func enqueueBatch(_ entries: [DownloadBatchEntry]) async -> DownloadBatchEnqueueResult {
        var queuedJobIDs: [DownloadJobID] = []
        var skippedMediaItemIDs: [MediaItemID] = []
        var failures: [DownloadBatchEnqueueFailure] = []
        var seenMediaItemIDs = Set<MediaItemID>()
        var rootJobID: DownloadJobID?

        for entry in entries where seenMediaItemIDs.insert(entry.mediaItemID).inserted {
            do {
                if let rootJobID {
                    if cancelledBatchRoots.contains(rootJobID) {
                        break
                    }
                    if try await downloadRepository.job(id: rootJobID).state == .cancelled {
                        break
                    }
                }
                if try await hasVerifiedLocalAsset(mediaItemID: entry.mediaItemID) {
                    skippedMediaItemIDs.append(entry.mediaItemID)
                    continue
                }
                let jobID = try await enqueue(
                    entry.request,
                    mediaItemID: entry.mediaItemID,
                    parentJobID: rootJobID
                )
                rootJobID = rootJobID ?? jobID
                queuedJobIDs.append(jobID)
            } catch {
                failures.append(DownloadBatchEnqueueFailure(
                    mediaItemID: entry.mediaItemID,
                    summary: Self.safeSummary(error)
                ))
            }
        }
        if let rootJobID {
            cancelledBatchRoots.remove(rootJobID)
        }
        return DownloadBatchEnqueueResult(
            queuedJobIDs: queuedJobIDs,
            skippedMediaItemIDs: skippedMediaItemIDs,
            failures: failures
        )
    }

    @discardableResult
    func retry(_ id: DownloadJobID) async throws -> DownloadJobID {
        let existing = try await downloadRepository.job(id: id)
        _ = try await request(for: existing)

        let queued: DownloadJob
        switch existing.state {
        case .failed, .interrupted, .paused, .ready:
            queued = try await transition(existing, to: .queued)
        case .cancelled:
            var clone = try await downloadRepository.createJob(CreateDownloadJobCommand(
                mediaItemID: existing.mediaItemID,
                parentJobID: existing.parentJobID,
                backendID: existing.backendID,
                engineVersion: existing.engineVersion,
                mediaKind: existing.mediaKind,
                container: existing.container,
                qualityPreset: existing.qualityPreset,
                requestJSON: existing.requestJSON,
                destinationBookmark: existing.destinationBookmark,
                destinationPath: existing.destinationPath
            ))
            clone = try await transition(clone, to: .resolving)
            clone = try await transition(clone, to: .ready)
            queued = try await transition(clone, to: .queued)
        case .queued:
            queued = existing
        default:
            throw DownloadCoordinatorError.jobIsNotRetryable
        }

        publish(.queued(queued.id))
        queueGeneration &+= 1
        wakeWorker()
        return queued.id
    }

    func cancel(_ id: DownloadJobID) async {
        guard let requestedJob = try? await downloadRepository.job(id: id) else { return }
        let rootJobID = requestedJob.parentJobID ?? requestedJob.id
        cancelledBatchRoots.insert(rootJobID)
        let family = (try? await cancellableJobs(rootJobID: rootJobID)) ?? [requestedJob]
        var cancelsActiveJob = false

        for job in family {
            if activeJob?.id == job.id {
                cancelsActiveJob = true
                continue
            }
            guard Self.cancellableStates.contains(job.state),
                  let cancelled = try? await transition(job, to: .cancelled) else {
                continue
            }
            publish(.cancelled(cancelled.id))
        }

        if cancelsActiveJob {
            backend.cancelCurrentDownload()
            executionTask?.cancel()
        }
    }

    func shutdown() {
        backend.cancelCurrentDownload()
        executionTask?.cancel()
        workerTask?.cancel()
        executionTask = nil
        workerTask = nil
    }

    private func wakeWorker() {
        guard didStart, workerTask == nil else { return }
        workerTask = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while !Task.isCancelled {
            let observedGeneration = queueGeneration
            let nextJob: DownloadJob?
            do {
                nextJob = try await downloadRepository.nextQueuedJob()
            } catch {
                publish(.queueUnavailable(Self.safeSummary(error)))
                workerTask = nil
                return
            }

            guard let nextJob else {
                if queueGeneration != observedGeneration { continue }
                publish(.idle)
                workerTask = nil
                return
            }

            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.execute(nextJob)
            }
            executionTask = task
            await task.value
            executionTask = nil
            activeJob = nil
            lastProgressPersistenceAt = nil
        }
        workerTask = nil
    }

    private func execute(_ queuedJob: DownloadJob) async {
        do {
            let request = try await request(for: queuedJob)
            var job = try await transition(queuedJob, to: .downloading)
            activeJob = job
            lastProgressPersistenceAt = nil
            publish(.started(job.id, request))

            let jobID = job.id
            let record = try await backend.download(request) { [weak self] event in
                Task { await self?.handleBackendEvent(event, jobID: jobID) }
            }
            try Task.checkCancellation()

            job = activeJob ?? job
            if job.state == .downloading {
                job = try await ensurePostProcessing(jobID: job.id)
                activeJob = job
            }
            guard job.state == .postProcessing,
                  let outputURL = record.outputFileURL else {
                throw DownloadCoordinatorError.missingOutputFile
            }
            let asset = try verifyAsset(outputURL)
            let completedJob = try await downloadRepository.completeJob(
                id: job.id,
                asset: asset
            )
            activeJob = completedJob
            publish(.completed(job.id, record))
        } catch is CancellationError {
            await Task.detached { [weak self] in
                await self?.finishCancellation(for: queuedJob.id)
            }.value
        } catch {
            await finishFailure(for: queuedJob.id, error: error)
        }
    }

    private func handleBackendEvent(
        _ event: DownloadBackendEvent,
        jobID: DownloadJobID
    ) async {
        guard var job = activeJob, job.id == jobID else { return }

        switch event {
        case .started, .completed, .failed, .cancelled:
            return
        case .progress(let progress):
            guard job.state == .downloading || job.state == .postProcessing else { return }
            let timestamp = now()
            let shouldPersist = lastProgressPersistenceAt.map {
                timestamp.timeIntervalSince($0) >= 1
            } ?? true
            if shouldPersist,
               let updated = try? await downloadRepository.updateProgress(
                   jobID: job.id,
                   update: DownloadProgressUpdate(
                       fraction: progress.fractionCompleted,
                       downloadedBytes: progress.downloadedBytes,
                       totalBytes: progress.totalBytes,
                       speedBytesPerSecond: progress.speedBytesPerSecond,
                       estimatedRemainingSeconds: progress.etaSeconds
                   )
               ) {
                job = updated
                activeJob = updated
                lastProgressPersistenceAt = timestamp
            }
            publish(.backend(jobID, .progress(progress)))
        case .postProcessing:
            guard job.state == .downloading || job.state == .postProcessing else { return }
            if job.state == .downloading,
               let updated = try? await ensurePostProcessing(jobID: job.id) {
                job = updated
                activeJob = updated
            }
            publish(.backend(jobID, .postProcessing))
        case .plannedArtifact, .log:
            publish(.backend(jobID, event))
        }
    }

    private func finishCancellation(for id: DownloadJobID) async {
        guard let job = try? await downloadRepository.job(id: id) else { return }
        if [.created, .resolving, .ready, .queued, .downloading, .postProcessing, .paused,
            .failed, .interrupted].contains(job.state) {
            if let cancelled = try? await transition(job, to: .cancelled) {
                activeJob = cancelled
            }
        }
        publish(.cancelled(id))
    }

    private func finishFailure(for id: DownloadJobID, error: Error) async {
        let summary = Self.safeSummary(error)
        if let job = try? await downloadRepository.job(id: id),
           [.resolving, .queued, .downloading, .postProcessing].contains(job.state) {
            activeJob = try? await downloadRepository.failJob(
                id: id,
                failure: DownloadFailure(category: "download_failed", summary: summary)
            )
        }
        publish(.failed(id, summary))
    }

    private func recordPreparationFailure(jobID: DownloadJobID, error: Error) async {
        guard let job = try? await downloadRepository.job(id: jobID) else { return }
        if [.resolving, .queued, .downloading, .postProcessing].contains(job.state) {
            _ = try? await downloadRepository.failJob(
                id: job.id,
                failure: DownloadFailure(
                    category: "queue_preparation_failed",
                    summary: Self.safeSummary(error)
                )
            )
        } else if [.created, .ready].contains(job.state) {
            _ = try? await transition(job, to: .cancelled)
        }
    }

    private func request(for job: DownloadJob) async throws -> DownloadRequest {
        let summaries = try await libraryRepository.summaries(
            mediaItemIDs: [job.mediaItemID],
            workspaceID: VidindirIdentity.personalWorkspace
        )
        guard let media = summaries.first?.mediaItem else {
            throw DownloadCoordinatorError.missingMediaItem
        }
        return try DownloadRequestSnapshot.request(
            job: job,
            sourceURL: media.sourceURL
        )
    }

    private func resolveMediaItem(
        for request: DownloadRequest,
        selectedID: MediaItemID?
    ) async throws -> MediaItem {
        if let selectedID {
            let summaries = try await libraryRepository.summaries(
                mediaItemIDs: [selectedID],
                workspaceID: VidindirIdentity.personalWorkspace
            )
            guard let item = summaries.first?.mediaItem else {
                throw DownloadCoordinatorError.missingMediaItem
            }
            return item
        }

        switch try await libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: request.sourceURL,
            destination: .libraryOnly
        )) {
        case .saved(let item):
            return item
        case .duplicate(let candidates):
            guard let item = candidates.first?.mediaItem else {
                throw DownloadCoordinatorError.missingMediaItem
            }
            return item
        }
    }

    private func hasVerifiedLocalAsset(mediaItemID: MediaItemID) async throws -> Bool {
        let assets = try await downloadRepository.localAssets(mediaItemID: mediaItemID)
        var foundExistingFile = false
        for asset in assets where asset.status == .available {
            if LocalAssetVerifier.existingFileURL(for: asset) != nil {
                foundExistingFile = true
            } else {
                _ = try await downloadRepository.markLocalAssetMissing(id: asset.id)
            }
        }
        return foundExistingFile
    }

    private func cancellableJobs(rootJobID: DownloadJobID) async throws -> [DownloadJob] {
        var candidates: [DownloadJob] = []
        var offset = 0
        while true {
            let page = try await downloadRepository.jobs(DownloadJobQuery(
                states: Self.cancellableStates,
                limit: 500,
                offset: offset
            ))
            candidates += page.filter {
                $0.id == rootJobID || $0.parentJobID == rootJobID
            }
            guard page.count == 500 else { break }
            offset += page.count
        }
        return candidates
    }

    private func transition(
        _ job: DownloadJob,
        to state: DownloadJobState
    ) async throws -> DownloadJob {
        try await downloadRepository.transitionJob(id: job.id, from: job.state, to: state)
    }

    private func ensurePostProcessing(jobID: DownloadJobID) async throws -> DownloadJob {
        var job = try await downloadRepository.job(id: jobID)
        if job.state == .postProcessing { return job }
        guard job.state == .downloading else {
            throw LibraryDomainError.invalidDownloadTransition
        }
        do {
            return try await transition(job, to: .postProcessing)
        } catch LibraryDomainError.invalidDownloadTransition {
            // The backend event callback and the final return can observe the
            // same phase boundary. Whichever wins persists it; the loser reads
            // back the authoritative state instead of turning success into a
            // false failure.
            job = try await downloadRepository.job(id: jobID)
            guard job.state == .postProcessing else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            return job
        }
    }

    private func publish(_ event: DownloadCoordinatorEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private static func safeSummary(_ error: Error) -> String {
        let value = DiagnosticRedactor().redact(
            error.localizedDescription,
            maximumLength: 400
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "The download could not be completed." : value
    }

    private static let cancellableStates: Set<DownloadJobState> = [
        .created, .resolving, .ready, .queued, .downloading, .postProcessing,
        .paused, .failed, .interrupted,
    ]
}

enum DownloadCoordinatorError: LocalizedError, Equatable {
    case missingMediaItem
    case missingOutputFile
    case jobIsNotRetryable

    var errorDescription: String? {
        switch self {
        case .missingMediaItem:
            "The saved media item could not be found."
        case .missingOutputFile:
            "The downloader finished without a verifiable output file."
        case .jobIsNotRetryable:
            "This download is not in a retryable state."
        }
    }
}
