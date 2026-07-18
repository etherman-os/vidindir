import Foundation
import VidindirDomain

actor DurableDownloadRecorder {
    private let libraryRepository: any LibraryRepository
    private let downloadRepository: any DownloadJobRepository
    private let verifyAsset: @Sendable (URL) throws -> VerifiedLocalAsset
    private let metadataResolver: (any MediaMetadataResolving)?
    private var activeJob: DownloadJob?

    init(
        libraryRepository: any LibraryRepository,
        downloadRepository: any DownloadJobRepository,
        metadataResolver: (any MediaMetadataResolving)? = nil,
        verifyAsset: @escaping @Sendable (URL) throws -> VerifiedLocalAsset = DurableDownloadRecorder.verifiedAsset
    ) {
        self.libraryRepository = libraryRepository
        self.downloadRepository = downloadRepository
        self.metadataResolver = metadataResolver
        self.verifyAsset = verifyAsset
    }

    func begin(_ request: DownloadRequest) async throws {
        guard activeJob == nil else {
            throw DurableDownloadRecorderError.sessionAlreadyActive
        }

        let saveResult = try await libraryRepository.saveLink(SaveLinkCommand(
            sourceURL: request.sourceURL,
            destination: .libraryOnly
        ))
        var mediaItem: MediaItem
        switch saveResult {
        case .saved(let saved):
            mediaItem = saved
        case .duplicate(let candidates):
            guard let existing = candidates.first?.mediaItem else {
                throw DurableDownloadRecorderError.missingMediaItem
            }
            mediaItem = existing
        }

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
                   description: nil,
                   durationSeconds: metadata.durationSeconds,
                   thumbnailURL: metadata.thumbnailURL,
                   status: .resolved
               )
           )) {
            mediaItem = updated
        }

        let requestJSON = try Self.requestJSON(for: request)
        var job = try await downloadRepository.createJob(CreateDownloadJobCommand(
            mediaItemID: mediaItem.id,
            backendID: "yt-dlp",
            mediaKind: request.format == .mp3 ? .audio : .video,
            container: request.format.rawValue,
            qualityPreset: QualityPreset(rawValue: request.quality.rawValue),
            requestJSON: requestJSON,
            destinationBookmark: Self.bookmark(for: request.destinationDirectory),
            destinationPath: request.destinationDirectory.path
        ))
        activeJob = job

        do {
            job = try await transition(job, to: .resolving)
            job = try await transition(job, to: .ready)
            job = try await transition(job, to: .queued)
            job = try await transition(job, to: .downloading)
            activeJob = job
        } catch {
            await failAfterPreparationError(error)
            throw error
        }
    }

    func recordProgress(_ progress: DownloadBackendProgress) async {
        guard let job = activeJob,
              job.state == .downloading || job.state == .postProcessing else { return }
        do {
            activeJob = try await downloadRepository.updateProgress(
                jobID: job.id,
                update: DownloadProgressUpdate(
                    fraction: progress.fractionCompleted,
                    downloadedBytes: progress.downloadedBytes,
                    totalBytes: progress.totalBytes,
                    speedBytesPerSecond: progress.speedBytesPerSecond,
                    estimatedRemainingSeconds: progress.etaSeconds
                )
            )
        } catch {
            // Progress is advisory. The terminal transition still records the
            // authoritative result, so a malformed backend sample cannot stop it.
        }
    }

    func recordPostProcessing() async {
        guard let job = activeJob, job.state == .downloading else { return }
        if let updated = try? await downloadRepository.transitionJob(
            id: job.id,
            from: .downloading,
            to: .postProcessing
        ) {
            activeJob = updated
        }
    }

    func complete(_ record: DownloadRecord) async throws {
        guard var job = activeJob else {
            throw DurableDownloadRecorderError.noActiveSession
        }
        if job.state == .downloading {
            job = try await transition(job, to: .postProcessing)
        }
        guard job.state == .postProcessing,
              let outputURL = record.outputFileURL else {
            throw DurableDownloadRecorderError.missingOutputFile
        }

        do {
            let asset = try verifyAsset(outputURL)
            _ = try await downloadRepository.completeJob(id: job.id, asset: asset)
            activeJob = nil
        } catch {
            let failure = DownloadFailure(
                category: "local_asset_unverified",
                summary: "The file was created, but Vidindir could not verify its local record.",
                technicalDetail: nil
            )
            _ = try? await downloadRepository.failJob(id: job.id, failure: failure)
            activeJob = nil
            throw error
        }
    }

    func fail(_ error: Error) async {
        guard let job = activeJob else { return }
        let summary = Self.safeFailureSummary(error)
        _ = try? await downloadRepository.failJob(
            id: job.id,
            failure: DownloadFailure(
                category: "download_failed",
                summary: summary
            )
        )
        activeJob = nil
    }

    func cancel() async {
        guard let job = activeJob else { return }
        _ = try? await downloadRepository.transitionJob(
            id: job.id,
            from: job.state,
            to: .cancelled
        )
        activeJob = nil
    }

    func activeJobID() -> DownloadJobID? {
        activeJob?.id
    }

    private func transition(
        _ job: DownloadJob,
        to state: DownloadJobState
    ) async throws -> DownloadJob {
        try await downloadRepository.transitionJob(id: job.id, from: job.state, to: state)
    }

    private func failAfterPreparationError(_ error: Error) async {
        guard let job = activeJob else { return }
        if [.resolving, .queued, .downloading, .postProcessing].contains(job.state) {
            _ = try? await downloadRepository.failJob(
                id: job.id,
                failure: DownloadFailure(
                    category: "queue_preparation_failed",
                    summary: Self.safeFailureSummary(error)
                )
            )
        } else if [.created, .ready].contains(job.state) {
            _ = try? await downloadRepository.transitionJob(
                id: job.id,
                from: job.state,
                to: .cancelled
            )
        }
        activeJob = nil
    }

    private static func requestJSON(for request: DownloadRequest) throws -> String {
        let object: [String: Any] = [
            "format": request.format.rawValue,
            "quality": request.quality.rawValue,
            "source": "library_media_item",
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw DurableDownloadRecorderError.invalidRequest
        }
        return json
    }

    private static func verifiedAsset(_ url: URL) throws -> VerifiedLocalAsset {
        guard url.isFileURL,
              NSString(string: url.path).isAbsolutePath,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size >= 0,
              let bookmark = bookmark(for: url),
              !bookmark.isEmpty else {
            throw DurableDownloadRecorderError.missingOutputFile
        }
        return try VerifiedLocalAsset(
            fileBookmark: bookmark,
            absolutePath: url.standardizedFileURL.path,
            fileSizeBytes: Int64(size),
            contentType: nil,
            container: url.pathExtension.lowercased(),
            verifiedAt: Date()
        )
    }

    private static func bookmark(for url: URL) -> Data? {
        if let scoped = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
            return nil
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func safeFailureSummary(_ error: Error) -> String {
        let description = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return "The download could not be completed." }
        return String(description.prefix(400))
    }
}

enum DurableDownloadRecorderError: LocalizedError, Equatable {
    case sessionAlreadyActive
    case noActiveSession
    case missingMediaItem
    case missingOutputFile
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            "Another download is already active."
        case .noActiveSession:
            "The persistent download session could not be found."
        case .missingMediaItem:
            "The media item could not be saved before downloading."
        case .missingOutputFile:
            "The downloaded file could not be verified on this Mac."
        case .invalidRequest:
            "The download request could not be recorded safely."
        }
    }
}
