import Foundation

public struct CreateDownloadJobCommand: Equatable, Hashable, Sendable {
    public let mediaItemID: MediaItemID
    public let parentJobID: DownloadJobID?
    public let backendID: String?
    public let engineVersion: String?
    public let mediaKind: MediaKind
    public let container: String?
    public let qualityPreset: QualityPreset
    public let requestJSON: String
    public let destinationBookmark: Data?
    public let destinationPath: String

    public init(
        mediaItemID: MediaItemID,
        parentJobID: DownloadJobID? = nil,
        backendID: String? = nil,
        engineVersion: String? = nil,
        mediaKind: MediaKind,
        container: String?,
        qualityPreset: QualityPreset = .best,
        requestJSON: String,
        destinationBookmark: Data?,
        destinationPath: String
    ) {
        self.mediaItemID = mediaItemID
        self.parentJobID = parentJobID
        self.backendID = backendID
        self.engineVersion = engineVersion
        self.mediaKind = mediaKind
        self.container = container
        self.qualityPreset = qualityPreset
        self.requestJSON = requestJSON
        self.destinationBookmark = destinationBookmark
        self.destinationPath = destinationPath
    }
}

public struct DownloadProgressUpdate: Equatable, Hashable, Sendable {
    public let fraction: Double?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let speedBytesPerSecond: Double?
    public let estimatedRemainingSeconds: Double?

    public init(
        fraction: Double?,
        downloadedBytes: Int64?,
        totalBytes: Int64?,
        speedBytesPerSecond: Double?,
        estimatedRemainingSeconds: Double?
    ) {
        self.fraction = fraction
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
    }
}

public struct VerifiedLocalAsset: Equatable, Hashable, Sendable {
    public let fileBookmark: Data
    public let absolutePath: String
    public let fileSizeBytes: Int64
    public let contentType: String?
    public let container: String?
    public let checksumSHA256: String?
    public let verifiedAt: Date

    public init(
        fileBookmark: Data,
        absolutePath: String,
        fileSizeBytes: Int64,
        contentType: String? = nil,
        container: String? = nil,
        checksumSHA256: String? = nil,
        verifiedAt: Date = Date()
    ) throws {
        guard !fileBookmark.isEmpty,
              absolutePath.hasPrefix("/"),
              fileSizeBytes >= 0 else {
            throw LibraryDomainError.invalidLocalAsset
        }
        self.fileBookmark = fileBookmark
        self.absolutePath = absolutePath
        self.fileSizeBytes = fileSizeBytes
        self.contentType = contentType
        self.container = container
        self.checksumSHA256 = checksumSHA256
        self.verifiedAt = verifiedAt
    }
}

public struct DownloadFailure: Equatable, Hashable, Sendable {
    public let category: String
    public let summary: String
    public let technicalDetail: String?
    public let retryAfter: Date?

    public init(
        category: String,
        summary: String,
        technicalDetail: String? = nil,
        retryAfter: Date? = nil
    ) {
        self.category = category
        self.summary = summary
        self.technicalDetail = technicalDetail
        self.retryAfter = retryAfter
    }
}

public struct DownloadJobQuery: Equatable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let states: Set<DownloadJobState>
    public let searchText: String?
    public let limit: Int
    public let offset: Int

    public init(
        workspaceID: WorkspaceID = VidindirIdentity.personalWorkspace,
        states: Set<DownloadJobState> = [],
        searchText: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.workspaceID = workspaceID
        self.states = states
        self.searchText = searchText
        self.limit = limit
        self.offset = offset
    }
}

public enum DownloadHistoryScope: String, CaseIterable, Equatable, Hashable, Sendable {
    case completed
    case needsAttention
    case allTerminal

    public var states: Set<DownloadJobState> {
        switch self {
        case .completed:
            [.completed]
        case .needsAttention:
            [.failed, .cancelled, .interrupted]
        case .allTerminal:
            [.completed, .failed, .cancelled, .interrupted]
        }
    }
}

public struct ClearDownloadHistoryResult: Equatable, Hashable, Sendable {
    public let deletedCount: Int
    public let retainedReferencedCount: Int

    public init(deletedCount: Int, retainedReferencedCount: Int) {
        self.deletedCount = deletedCount
        self.retainedReferencedCount = retainedReferencedCount
    }
}

public protocol DownloadJobRepository: Sendable {
    func createJob(_ command: CreateDownloadJobCommand) async throws -> DownloadJob
    func transitionJob(
        id: DownloadJobID,
        from expectedState: DownloadJobState,
        to newState: DownloadJobState
    ) async throws -> DownloadJob
    func updateProgress(
        jobID: DownloadJobID,
        update: DownloadProgressUpdate
    ) async throws -> DownloadJob
    func failJob(id: DownloadJobID, failure: DownloadFailure) async throws -> DownloadJob
    func completeJob(id: DownloadJobID, asset: VerifiedLocalAsset) async throws -> DownloadJob
    func interruptActiveJobsAfterLaunch() async throws -> Int
    func jobs(_ query: DownloadJobQuery) async throws -> [DownloadJob]
    func jobCount(_ query: DownloadJobQuery) async throws -> Int
    func job(id: DownloadJobID) async throws -> DownloadJob
    func nextQueuedJob() async throws -> DownloadJob?
    func clearHistory(scope: DownloadHistoryScope) async throws -> ClearDownloadHistoryResult
    func localAssets(mediaItemID: MediaItemID) async throws -> [LocalAsset]
    func markLocalAssetMissing(id: LocalAssetID) async throws -> LocalAsset
    func markLocalAssetRemoved(id: LocalAssetID) async throws -> LocalAsset
}
