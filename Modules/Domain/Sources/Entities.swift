import Foundation

public struct VersionStamp: Codable, Equatable, Hashable, Sendable {
    public let revision: Int64
    public let createdAt: Date
    public let modifiedAt: Date
    public let modifiedByDevice: DeviceID
    public let deletedAt: Date?

    public init(
        revision: Int64,
        createdAt: Date,
        modifiedAt: Date,
        modifiedByDevice: DeviceID,
        deletedAt: Date? = nil
    ) {
        self.revision = revision
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.modifiedByDevice = modifiedByDevice
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}

public struct Workspace: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: WorkspaceID
    public let name: String
    public let kind: WorkspaceKind
    public let version: VersionStamp

    public init(id: WorkspaceID, name: String, kind: WorkspaceKind, version: VersionStamp) {
        self.id = id
        self.name = name
        self.kind = kind
        self.version = version
    }
}

public struct MediaItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: MediaItemID
    public let workspaceID: WorkspaceID
    public let sourceURL: URL
    public let canonicalURL: URL?
    public let canonicalizationVersion: Int
    public let sourceType: SourceType
    public let sourceMediaID: String?
    public let title: String?
    public let creator: String?
    public let description: String?
    public let durationSeconds: Double?
    public let thumbnailURL: URL?
    public let metadataStatus: MetadataStatus
    public let metadataErrorCode: String?
    public let version: VersionStamp

    public init(
        id: MediaItemID,
        workspaceID: WorkspaceID,
        sourceURL: URL,
        canonicalURL: URL?,
        canonicalizationVersion: Int = 1,
        sourceType: SourceType,
        sourceMediaID: String?,
        title: String? = nil,
        creator: String? = nil,
        description: String? = nil,
        durationSeconds: Double? = nil,
        thumbnailURL: URL? = nil,
        metadataStatus: MetadataStatus = .unresolved,
        metadataErrorCode: String? = nil,
        version: VersionStamp
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.sourceURL = sourceURL
        self.canonicalURL = canonicalURL
        self.canonicalizationVersion = canonicalizationVersion
        self.sourceType = sourceType
        self.sourceMediaID = sourceMediaID
        self.title = title
        self.creator = creator
        self.description = description
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.metadataStatus = metadataStatus
        self.metadataErrorCode = metadataErrorCode
        self.version = version
    }
}

public struct Collection: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: CollectionID
    public let workspaceID: WorkspaceID
    public let name: String
    public let kind: CollectionKind
    public let sortOrder: Double
    public let colorToken: String?
    public let iconName: String?
    public let version: VersionStamp

    public init(
        id: CollectionID,
        workspaceID: WorkspaceID,
        name: String,
        kind: CollectionKind,
        sortOrder: Double = 0,
        colorToken: String? = nil,
        iconName: String? = nil,
        version: VersionStamp
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.colorToken = colorToken
        self.iconName = iconName
        self.version = version
    }
}

public struct CollectionMembership: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: CollectionMembershipID
    public let workspaceID: WorkspaceID
    public let collectionID: CollectionID
    public let mediaItemID: MediaItemID
    public let sortOrder: Double?
    public let version: VersionStamp
}

public struct Favorite: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: FavoriteID
    public let workspaceID: WorkspaceID
    public let mediaItemID: MediaItemID
    public let version: VersionStamp
}

public struct Device: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: DeviceID
    public let displayName: String
    public let platform: String
    public let appVersion: String?
    public let createdAt: Date
    public let lastSeenAt: Date
    public let isCurrent: Bool
}

public struct LocalAsset: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: LocalAssetID
    public let mediaItemID: MediaItemID
    public let deviceID: DeviceID
    public let fileBookmark: Data?
    public let lastKnownPath: String
    public let fileSizeBytes: Int64?
    public let contentType: String?
    public let container: String?
    public let checksumSHA256: String?
    public let status: LocalAssetStatus
    public let downloadedAt: Date
    public let lastVerifiedAt: Date?
    public let removedAt: Date?
    public let createdAt: Date
    public let modifiedAt: Date

    public init(
        id: LocalAssetID,
        mediaItemID: MediaItemID,
        deviceID: DeviceID,
        fileBookmark: Data?,
        lastKnownPath: String,
        fileSizeBytes: Int64?,
        contentType: String?,
        container: String?,
        checksumSHA256: String?,
        status: LocalAssetStatus,
        downloadedAt: Date,
        lastVerifiedAt: Date?,
        removedAt: Date?,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.deviceID = deviceID
        self.fileBookmark = fileBookmark
        self.lastKnownPath = lastKnownPath
        self.fileSizeBytes = fileSizeBytes
        self.contentType = contentType
        self.container = container
        self.checksumSHA256 = checksumSHA256
        self.status = status
        self.downloadedAt = downloadedAt
        self.lastVerifiedAt = lastVerifiedAt
        self.removedAt = removedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct DownloadJob: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: DownloadJobID
    public let mediaItemID: MediaItemID
    public let deviceID: DeviceID
    public let parentJobID: DownloadJobID?
    public let backendID: String?
    public let engineVersion: String?
    public let state: DownloadJobState
    public let queuePosition: Int64?
    public let mediaKind: MediaKind
    public let container: String?
    public let qualityPreset: QualityPreset
    public let requestJSON: String
    public let destinationBookmark: Data?
    public let destinationPath: String
    public let progressFraction: Double?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let speedBytesPerSecond: Double?
    public let estimatedRemainingSeconds: Double?
    public let attemptCount: Int
    public let retryAfter: Date?
    public let errorCategory: String?
    public let errorSummary: String?
    public let technicalDetail: String?
    public let backendResumeData: Data?
    public let localAssetID: LocalAssetID?
    public let createdAt: Date
    public let queuedAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let modifiedAt: Date

    public init(
        id: DownloadJobID,
        mediaItemID: MediaItemID,
        deviceID: DeviceID,
        parentJobID: DownloadJobID?,
        backendID: String?,
        engineVersion: String?,
        state: DownloadJobState,
        queuePosition: Int64? = nil,
        mediaKind: MediaKind,
        container: String?,
        qualityPreset: QualityPreset,
        requestJSON: String,
        destinationBookmark: Data?,
        destinationPath: String,
        progressFraction: Double?,
        downloadedBytes: Int64?,
        totalBytes: Int64?,
        speedBytesPerSecond: Double?,
        estimatedRemainingSeconds: Double?,
        attemptCount: Int,
        retryAfter: Date?,
        errorCategory: String?,
        errorSummary: String?,
        technicalDetail: String?,
        backendResumeData: Data?,
        localAssetID: LocalAssetID?,
        createdAt: Date,
        queuedAt: Date?,
        startedAt: Date?,
        completedAt: Date?,
        modifiedAt: Date
    ) {
        self.id = id
        self.mediaItemID = mediaItemID
        self.deviceID = deviceID
        self.parentJobID = parentJobID
        self.backendID = backendID
        self.engineVersion = engineVersion
        self.state = state
        self.queuePosition = queuePosition
        self.mediaKind = mediaKind
        self.container = container
        self.qualityPreset = qualityPreset
        self.requestJSON = requestJSON
        self.destinationBookmark = destinationBookmark
        self.destinationPath = destinationPath
        self.progressFraction = progressFraction
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.attemptCount = attemptCount
        self.retryAfter = retryAfter
        self.errorCategory = errorCategory
        self.errorSummary = errorSummary
        self.technicalDetail = technicalDetail
        self.backendResumeData = backendResumeData
        self.localAssetID = localAssetID
        self.createdAt = createdAt
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.modifiedAt = modifiedAt
    }
}

public enum LibraryDomainError: Error, Equatable, Sendable {
    case invalidSourceURL
    case emptyName
    case invalidPagination
    case recordNotFound
    case crossWorkspaceRelationship
    case concurrentModification
    case protectedCollection
    case invalidProgress
    case invalidDownloadTransition
    case invalidDownloadRequest
    case invalidLocalAsset
    case completedJobRequiresAvailableAsset
}
