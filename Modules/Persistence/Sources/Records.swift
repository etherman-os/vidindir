import Foundation
import GRDB
import VidindirDomain

struct WorkspaceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workspaces"

    let id: String
    let name: String
    let kind: String
    let revision: Int64
    let createdAt: Int64
    let modifiedAt: Int64
    let modifiedByDevice: String
    let deletedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, revision
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    func domain() throws -> Workspace {
        Workspace(
            id: try requireID(id, as: WorkspaceID.self),
            name: name,
            kind: WorkspaceKind(rawValue: kind),
            version: try versionStamp(
                revision: revision,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                modifiedByDevice: modifiedByDevice,
                deletedAt: deletedAt
            )
        )
    }
}

struct MediaItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_items"

    let id: String
    let workspaceID: String
    let sourceURL: String
    let canonicalURL: String?
    let canonicalizationVersion: Int
    let sourceType: String
    let sourceMediaID: String?
    let title: String?
    let creator: String?
    let description: String?
    let durationSeconds: Double?
    let thumbnailURL: String?
    let metadataStatus: String
    let metadataErrorCode: String?
    let revision: Int64
    let createdAt: Int64
    let modifiedAt: Int64
    let modifiedByDevice: String
    let deletedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, title, creator, description, revision
        case workspaceID = "workspace_id"
        case sourceURL = "source_url"
        case canonicalURL = "canonical_url"
        case canonicalizationVersion = "canonicalization_version"
        case sourceType = "source_type"
        case sourceMediaID = "source_media_id"
        case durationSeconds = "duration_seconds"
        case thumbnailURL = "thumbnail_url"
        case metadataStatus = "metadata_status"
        case metadataErrorCode = "metadata_error_code"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    func domain() throws -> MediaItem {
        guard let sourceURL = URL(string: sourceURL),
              let canonicalURL = try optionalURL(canonicalURL),
              let thumbnailURL = try optionalURL(thumbnailURL) else {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        if let durationSeconds,
           !durationSeconds.isFinite || durationSeconds < 0 {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        return MediaItem(
            id: try requireID(id, as: MediaItemID.self),
            workspaceID: try requireID(workspaceID, as: WorkspaceID.self),
            sourceURL: sourceURL,
            canonicalURL: canonicalURL,
            canonicalizationVersion: canonicalizationVersion,
            sourceType: SourceType(rawValue: sourceType),
            sourceMediaID: sourceMediaID,
            title: title,
            creator: creator,
            description: description,
            durationSeconds: durationSeconds,
            thumbnailURL: thumbnailURL,
            metadataStatus: MetadataStatus(rawValue: metadataStatus),
            metadataErrorCode: metadataErrorCode,
            version: try versionStamp(
                revision: revision,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                modifiedByDevice: modifiedByDevice,
                deletedAt: deletedAt
            )
        )
    }

    private func optionalURL(_ value: String?) throws -> URL?? {
        guard let value else { return .some(nil) }
        guard let url = URL(string: value) else {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        return .some(url)
    }
}

struct CollectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collections"

    let id: String
    let workspaceID: String
    let name: String
    let kind: String
    let sortOrder: Double
    let colorToken: String?
    let iconName: String?
    let revision: Int64
    let createdAt: Int64
    let modifiedAt: Int64
    let modifiedByDevice: String
    let deletedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, revision
        case workspaceID = "workspace_id"
        case sortOrder = "sort_order"
        case colorToken = "color_token"
        case iconName = "icon_name"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }

    func domain() throws -> Collection {
        guard sortOrder.isFinite else {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        return Collection(
            id: try requireID(id, as: CollectionID.self),
            workspaceID: try requireID(workspaceID, as: WorkspaceID.self),
            name: name,
            kind: CollectionKind(rawValue: kind),
            sortOrder: sortOrder,
            colorToken: colorToken,
            iconName: iconName,
            version: try versionStamp(
                revision: revision,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                modifiedByDevice: modifiedByDevice,
                deletedAt: deletedAt
            )
        )
    }
}

struct CollectionMembershipRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collection_memberships"

    let id: String
    let workspaceID: String
    let collectionID: String
    let mediaItemID: String
    let sortOrder: Double?
    let revision: Int64
    let createdAt: Int64
    let modifiedAt: Int64
    let modifiedByDevice: String
    let deletedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, revision
        case workspaceID = "workspace_id"
        case collectionID = "collection_id"
        case mediaItemID = "media_item_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }
}

struct FavoriteRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "favorites"

    let id: String
    let workspaceID: String
    let mediaItemID: String
    let revision: Int64
    let createdAt: Int64
    let modifiedAt: Int64
    let modifiedByDevice: String
    let deletedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, revision
        case workspaceID = "workspace_id"
        case mediaItemID = "media_item_id"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case modifiedByDevice = "modified_by_device"
        case deletedAt = "deleted_at"
    }
}

struct LocalAssetRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_assets"

    let id: String
    let mediaItemID: String
    let deviceID: String
    let fileBookmark: Data?
    let lastKnownPath: String
    let fileSizeBytes: Int64?
    let contentType: String?
    let container: String?
    let checksumSHA256: String?
    let status: String
    let downloadedAt: Int64
    let lastVerifiedAt: Int64?
    let removedAt: Int64?
    let createdAt: Int64
    let modifiedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, container, status
        case mediaItemID = "media_item_id"
        case deviceID = "device_id"
        case fileBookmark = "file_bookmark"
        case lastKnownPath = "last_known_path"
        case fileSizeBytes = "file_size_bytes"
        case contentType = "content_type"
        case checksumSHA256 = "checksum_sha256"
        case downloadedAt = "downloaded_at"
        case lastVerifiedAt = "last_verified_at"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    func domain() throws -> LocalAsset {
        if let fileSizeBytes, fileSizeBytes < 0 {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        return LocalAsset(
            id: try requireID(id, as: LocalAssetID.self),
            mediaItemID: try requireID(mediaItemID, as: MediaItemID.self),
            deviceID: try requireID(deviceID, as: DeviceID.self),
            fileBookmark: fileBookmark,
            lastKnownPath: lastKnownPath,
            fileSizeBytes: fileSizeBytes,
            contentType: contentType,
            container: container,
            checksumSHA256: checksumSHA256,
            status: LocalAssetStatus(rawValue: status),
            downloadedAt: Date(sqliteMilliseconds: downloadedAt),
            lastVerifiedAt: lastVerifiedAt.map(Date.init(sqliteMilliseconds:)),
            removedAt: removedAt.map(Date.init(sqliteMilliseconds:)),
            createdAt: Date(sqliteMilliseconds: createdAt),
            modifiedAt: Date(sqliteMilliseconds: modifiedAt)
        )
    }
}

struct DownloadJobRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download_jobs"

    let id: String
    let mediaItemID: String
    let deviceID: String
    let parentJobID: String?
    let backendID: String?
    let engineVersion: String?
    let state: String
    let mediaKind: String
    let container: String?
    let qualityPreset: String
    let requestJSON: String
    let destinationBookmark: Data?
    let destinationPath: String
    let progressFraction: Double?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let speedBytesPerSecond: Double?
    let estimatedRemainingSeconds: Double?
    let attemptCount: Int
    let retryAfter: Int64?
    let errorCategory: String?
    let errorSummary: String?
    let technicalDetail: String?
    let backendResumeData: Data?
    let localAssetID: String?
    let createdAt: Int64
    let queuedAt: Int64?
    let startedAt: Int64?
    let completedAt: Int64?
    let modifiedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, state, container
        case mediaItemID = "media_item_id"
        case deviceID = "device_id"
        case parentJobID = "parent_job_id"
        case backendID = "backend_id"
        case engineVersion = "engine_version"
        case mediaKind = "media_kind"
        case qualityPreset = "quality_preset"
        case requestJSON = "request_json"
        case destinationBookmark = "destination_bookmark"
        case destinationPath = "destination_path"
        case progressFraction = "progress_fraction"
        case downloadedBytes = "downloaded_bytes"
        case totalBytes = "total_bytes"
        case speedBytesPerSecond = "speed_bytes_per_second"
        case estimatedRemainingSeconds = "estimated_remaining_sec"
        case attemptCount = "attempt_count"
        case retryAfter = "retry_after"
        case errorCategory = "error_category"
        case errorSummary = "error_summary"
        case technicalDetail = "technical_detail"
        case backendResumeData = "backend_resume_data"
        case localAssetID = "local_asset_id"
        case createdAt = "created_at"
        case queuedAt = "queued_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case modifiedAt = "modified_at"
    }

    func domain() throws -> DownloadJob {
        try validateMetric(progressFraction, range: 0...1)
        try validateMetric(speedBytesPerSecond, range: 0...Double.greatestFiniteMagnitude)
        try validateMetric(estimatedRemainingSeconds, range: 0...Double.greatestFiniteMagnitude)
        guard attemptCount >= 0,
              downloadedBytes.map({ $0 >= 0 }) ?? true,
              totalBytes.map({ $0 >= 0 }) ?? true else {
            throw LibraryPersistenceError.invalidStoredRecord
        }
        return DownloadJob(
            id: try requireID(id, as: DownloadJobID.self),
            mediaItemID: try requireID(mediaItemID, as: MediaItemID.self),
            deviceID: try requireID(deviceID, as: DeviceID.self),
            parentJobID: try parentJobID.map { try requireID($0, as: DownloadJobID.self) },
            backendID: backendID,
            engineVersion: engineVersion,
            state: DownloadJobState(rawValue: state),
            mediaKind: MediaKind(rawValue: mediaKind),
            container: container,
            qualityPreset: QualityPreset(rawValue: qualityPreset),
            requestJSON: requestJSON,
            destinationBookmark: destinationBookmark,
            destinationPath: destinationPath,
            progressFraction: progressFraction,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speedBytesPerSecond: speedBytesPerSecond,
            estimatedRemainingSeconds: estimatedRemainingSeconds,
            attemptCount: attemptCount,
            retryAfter: retryAfter.map(Date.init(sqliteMilliseconds:)),
            errorCategory: errorCategory,
            errorSummary: errorSummary,
            technicalDetail: technicalDetail,
            backendResumeData: backendResumeData,
            localAssetID: try localAssetID.map { try requireID($0, as: LocalAssetID.self) },
            createdAt: Date(sqliteMilliseconds: createdAt),
            queuedAt: queuedAt.map(Date.init(sqliteMilliseconds:)),
            startedAt: startedAt.map(Date.init(sqliteMilliseconds:)),
            completedAt: completedAt.map(Date.init(sqliteMilliseconds:)),
            modifiedAt: Date(sqliteMilliseconds: modifiedAt)
        )
    }

    private func validateMetric(_ value: Double?, range: ClosedRange<Double>) throws {
        guard let value else { return }
        guard value.isFinite, range.contains(value) else {
            throw LibraryPersistenceError.invalidStoredRecord
        }
    }
}

private func versionStamp(
    revision: Int64,
    createdAt: Int64,
    modifiedAt: Int64,
    modifiedByDevice: String,
    deletedAt: Int64?
) throws -> VersionStamp {
    guard revision >= 1 else {
        throw LibraryPersistenceError.invalidStoredRecord
    }
    return VersionStamp(
        revision: revision,
        createdAt: Date(sqliteMilliseconds: createdAt),
        modifiedAt: Date(sqliteMilliseconds: modifiedAt),
        modifiedByDevice: try requireID(modifiedByDevice, as: DeviceID.self),
        deletedAt: deletedAt.map(Date.init(sqliteMilliseconds:))
    )
}

private func requireID<Scope>(
    _ value: String,
    as type: TypedID<Scope>.Type
) throws -> TypedID<Scope> {
    guard let id = TypedID<Scope>(uuidString: value) else {
        throw LibraryPersistenceError.invalidStoredRecord
    }
    return id
}
