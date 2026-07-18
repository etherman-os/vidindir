import Foundation
import GRDB
import VidindirDomain

public struct LegacyHistoryImportResult: Codable, Equatable, Sendable {
    public let wasAlreadyImported: Bool
    public let importedMediaItems: Int
    public let reusedMediaItems: Int
    public let importedJobs: Int
    public let importedAssets: Int
    public let skippedEntries: Int

    public init(
        wasAlreadyImported: Bool,
        importedMediaItems: Int,
        reusedMediaItems: Int,
        importedJobs: Int,
        importedAssets: Int,
        skippedEntries: Int
    ) {
        self.wasAlreadyImported = wasAlreadyImported
        self.importedMediaItems = importedMediaItems
        self.reusedMediaItems = reusedMediaItems
        self.importedJobs = importedJobs
        self.importedAssets = importedAssets
        self.skippedEntries = skippedEntries
    }

    func markedAlreadyImported() -> Self {
        Self(
            wasAlreadyImported: true,
            importedMediaItems: importedMediaItems,
            reusedMediaItems: reusedMediaItems,
            importedJobs: importedJobs,
            importedAssets: importedAssets,
            skippedEntries: skippedEntries
        )
    }
}

public actor LegacyHistoryImporter {
    public static let userDefaultsKey = "history.downloads"
    public static let migrationStateKey = "legacy_user_defaults_history_v1"

    private let pool: DatabasePool
    private let currentDeviceID: DeviceID
    private let canonicalizer: SourceCanonicalizer
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID
    private let verifyLocalFile: @Sendable (URL) -> LegacyVerifiedFile?

    public init(
        database: LibraryDatabase,
        canonicalizer: SourceCanonicalizer = SourceCanonicalizer(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        pool = database.pool
        currentDeviceID = database.currentDeviceID
        self.canonicalizer = canonicalizer
        self.now = now
        self.makeUUID = makeUUID
        verifyLocalFile = Self.verifyLocalFileOnDisk
    }

    init(
        database: LibraryDatabase,
        canonicalizer: SourceCanonicalizer = SourceCanonicalizer(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        verifyLocalFile: @escaping @Sendable (URL) -> LegacyVerifiedFile?
    ) {
        pool = database.pool
        currentDeviceID = database.currentDeviceID
        self.canonicalizer = canonicalizer
        self.now = now
        self.makeUUID = makeUUID
        self.verifyLocalFile = verifyLocalFile
    }

    /// Imports the prototype's raw UserDefaults value without changing or deleting it.
    public func importHistoryData(_ legacyHistoryData: Data?) async throws -> LegacyHistoryImportResult {
        let parsed = parse(legacyHistoryData)
        let timestamp = now()
        let prepared = parsed.records.compactMap { prepare($0, importedAt: timestamp) }
        let invalidPreparedCount = parsed.records.count - prepared.count
        let deviceID = currentDeviceID.description
        let makeUUID = makeUUID

        return try await pool.write { db in
            if let storedJSON = try String.fetchOne(
                db,
                sql: "SELECT value_json FROM migration_state WHERE key = ?",
                arguments: [Self.migrationStateKey]
            ), let data = storedJSON.data(using: .utf8),
               let result = try? JSONDecoder().decode(LegacyHistoryImportResult.self, from: data) {
                return result.markedAlreadyImported()
            }

            var importedMediaItems = 0
            var reusedMediaItems = 0
            var importedJobs = 0
            var importedAssets = 0

            for record in prepared {
                let mediaResolution = try Self.findOrCreateMediaItem(
                    db: db,
                    record: record,
                    deviceID: deviceID,
                    makeUUID: makeUUID
                )
                if mediaResolution.wasCreated {
                    importedMediaItems += 1
                } else {
                    reusedMediaItems += 1
                }

                var jobID = DownloadJobID(record.legacyID)
                if try DownloadJobRecord.fetchOne(db, key: jobID.description) != nil {
                    jobID = DownloadJobID(makeUUID())
                }

                let assetID: LocalAssetID?
                if let file = record.verifiedFile, record.state == .completed {
                    let newAssetID = LocalAssetID(makeUUID())
                    try LocalAssetRecord(
                        id: newAssetID.description,
                        mediaItemID: mediaResolution.mediaItemID.description,
                        deviceID: deviceID,
                        fileBookmark: file.bookmark,
                        lastKnownPath: file.path,
                        fileSizeBytes: file.fileSizeBytes,
                        contentType: nil,
                        container: record.container,
                        checksumSHA256: nil,
                        status: LocalAssetStatus.available.rawValue,
                        downloadedAt: record.finishedAt.sqliteMilliseconds,
                        lastVerifiedAt: timestamp.sqliteMilliseconds,
                        removedAt: nil,
                        createdAt: record.finishedAt.sqliteMilliseconds,
                        modifiedAt: timestamp.sqliteMilliseconds
                    ).insert(db)
                    assetID = newAssetID
                    importedAssets += 1
                } else {
                    assetID = nil
                }

                let error = Self.errorFields(for: record)
                let job = DownloadJobRecord(
                    id: jobID.description,
                    mediaItemID: mediaResolution.mediaItemID.description,
                    deviceID: deviceID,
                    parentJobID: nil,
                    backendID: "legacy-yt-dlp",
                    engineVersion: nil,
                    state: record.state.rawValue,
                    mediaKind: record.mediaKind.rawValue,
                    container: record.container,
                    qualityPreset: QualityPreset.best.rawValue,
                    requestJSON: record.requestJSON,
                    destinationBookmark: nil,
                    destinationPath: record.destinationPath,
                    progressFraction: record.state == .completed ? 1 : nil,
                    downloadedBytes: record.verifiedFile?.fileSizeBytes,
                    totalBytes: record.verifiedFile?.fileSizeBytes,
                    speedBytesPerSecond: nil,
                    estimatedRemainingSeconds: nil,
                    attemptCount: record.state == .queued ? 0 : 1,
                    retryAfter: nil,
                    errorCategory: error.category,
                    errorSummary: error.summary,
                    technicalDetail: nil,
                    backendResumeData: nil,
                    localAssetID: assetID?.description,
                    createdAt: record.startedAt.sqliteMilliseconds,
                    queuedAt: record.startedAt.sqliteMilliseconds,
                    startedAt: record.state == .queued ? nil : record.startedAt.sqliteMilliseconds,
                    completedAt: record.state == .completed ? record.finishedAt.sqliteMilliseconds : nil,
                    modifiedAt: record.finishedAt.sqliteMilliseconds
                )
                try job.insert(db)
                importedJobs += 1
            }

            let result = LegacyHistoryImportResult(
                wasAlreadyImported: false,
                importedMediaItems: importedMediaItems,
                reusedMediaItems: reusedMediaItems,
                importedJobs: importedJobs,
                importedAssets: importedAssets,
                skippedEntries: parsed.skippedEntries + invalidPreparedCount
            )
            let markerData = try JSONEncoder().encode(result)
            guard let markerJSON = String(data: markerData, encoding: .utf8) else {
                throw LibraryPersistenceError.invalidStoredRecord
            }
            try db.execute(
                sql: """
                    INSERT INTO migration_state (key, value_json, modified_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [Self.migrationStateKey, markerJSON, timestamp.sqliteMilliseconds]
            )
            return result
        }
    }

    private func parse(_ data: Data?) -> ParsedLegacyHistory {
        guard let data, !data.isEmpty else {
            return ParsedLegacyHistory(records: [], skippedEntries: 0)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let values = root as? [Any] else {
            return ParsedLegacyHistory(records: [], skippedEntries: 1)
        }

        var records: [LegacyHistoryRecord] = []
        var skipped = 0
        let decoder = JSONDecoder()
        for value in values {
            guard JSONSerialization.isValidJSONObject(value),
                  let itemData = try? JSONSerialization.data(withJSONObject: value),
                  let record = try? decoder.decode(LegacyHistoryRecord.self, from: itemData) else {
                skipped += 1
                continue
            }
            records.append(record)
        }
        return ParsedLegacyHistory(records: records, skippedEntries: skipped)
    }

    private func prepare(
        _ record: LegacyHistoryRecord,
        importedAt: Date
    ) -> PreparedLegacyRecord? {
        guard Self.isHTTPURL(record.sourceURL),
              record.destinationDirectory.isFileURL,
              NSString(string: record.destinationDirectory.path).isAbsolutePath,
              record.destinationDirectory.path.utf8.count <= 4_096,
              Self.validOutputURL(record.outputFileURL),
              Self.legacyStatuses.contains(record.status),
              Self.isSQLiteDate(record.startedAt),
              record.finishedAt.map(Self.isSQLiteDate) ?? true,
              let source = try? canonicalizer.canonicalize(record.sourceURL) else {
            return nil
        }

        let mediaKind: MediaKind
        let container: String
        switch record.format {
        case "mp4":
            mediaKind = .video
            container = "mp4"
        case "mp3":
            mediaKind = .audio
            container = "mp3"
        default:
            return nil
        }

        let finishedAt = max(record.finishedAt ?? importedAt, record.startedAt)
        var state = Self.mappedState(record.status)
        var verifiedFile: LegacyVerifiedFile?
        if state == .completed, let outputURL = record.outputFileURL {
            if let candidate = verifyLocalFile(outputURL),
               Self.isValidVerifiedFile(candidate, for: outputURL) {
                verifiedFile = candidate
            }
        }
        if state == .completed, verifiedFile == nil {
            state = .interrupted
        }

        let requestObject: [String: Any] = [
            "legacyImport": true,
            "format": record.format,
            "outputPath": record.outputFileURL?.path ?? "",
        ]
        guard let requestData = try? JSONSerialization.data(
            withJSONObject: requestObject,
            options: [.sortedKeys]
        ), let requestJSON = String(data: requestData, encoding: .utf8) else {
            return nil
        }

        let normalizedTitle: String?
        if let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title.utf8.count <= 4_096 {
            normalizedTitle = title
        } else {
            normalizedTitle = nil
        }

        return PreparedLegacyRecord(
            legacyID: record.id,
            source: source,
            mediaKind: mediaKind,
            container: container,
            title: normalizedTitle,
            state: state,
            startedAt: record.startedAt,
            finishedAt: finishedAt,
            destinationPath: record.destinationDirectory.standardizedFileURL.path,
            requestJSON: requestJSON,
            verifiedFile: verifiedFile,
            legacyStatus: record.status
        )
    }

    private static func findOrCreateMediaItem(
        db: Database,
        record: PreparedLegacyRecord,
        deviceID: String,
        makeUUID: @Sendable () -> UUID
    ) throws -> (mediaItemID: MediaItemID, wasCreated: Bool) {
        let workspaceID = VidindirIdentity.personalWorkspace
        if let existingID = try String.fetchOne(
            db,
            sql: """
                SELECT id FROM media_items
                WHERE workspace_id = ? AND deleted_at IS NULL AND (
                    (? IS NOT NULL AND source_type = ? AND source_media_id = ?)
                    OR (? IS NOT NULL AND canonical_url = ?)
                    OR source_url = ?
                )
                ORDER BY created_at, id LIMIT 1
                """,
            arguments: [
                workspaceID.description,
                record.source.sourceMediaID,
                record.source.sourceType.rawValue,
                record.source.sourceMediaID,
                record.source.canonicalURL?.absoluteString,
                record.source.canonicalURL?.absoluteString,
                record.source.sourceURL.absoluteString,
            ]
        ), let mediaItemID = MediaItemID(uuidString: existingID) {
            return (mediaItemID, false)
        }

        let mediaItemID = MediaItemID(makeUUID())
        let createdAt = record.startedAt.sqliteMilliseconds
        try MediaItemRecord(
            id: mediaItemID.description,
            workspaceID: workspaceID.description,
            sourceURL: record.source.sourceURL.absoluteString,
            canonicalURL: record.source.canonicalURL?.absoluteString,
            canonicalizationVersion: record.source.canonicalizationVersion,
            sourceType: record.source.sourceType.rawValue,
            sourceMediaID: record.source.sourceMediaID,
            title: record.title,
            creator: nil,
            description: nil,
            durationSeconds: nil,
            thumbnailURL: nil,
            metadataStatus: record.title == nil
                ? MetadataStatus.unresolved.rawValue
                : MetadataStatus.resolved.rawValue,
            metadataErrorCode: nil,
            revision: 1,
            createdAt: createdAt,
            modifiedAt: createdAt,
            modifiedByDevice: deviceID,
            deletedAt: nil
        ).insert(db)
        try appendMigrationChange(
            db: db,
            changeID: makeUUID(),
            entityID: mediaItemID,
            timestamp: createdAt
        )
        try refreshSearch(db: db, mediaItemID: mediaItemID)
        return (mediaItemID, true)
    }

    private static func appendMigrationChange(
        db: Database,
        changeID: UUID,
        entityID: MediaItemID,
        timestamp: Int64
    ) throws {
        let changeID = changeID.uuidString.lowercased()
        try db.execute(
            sql: """
                INSERT INTO change_journal (
                    change_id, workspace_id, entity_type, entity_id,
                    entity_revision, operation, origin, created_at
                ) VALUES (?, ?, 'media_item', ?, 1, 'upsert', 'migration', ?)
                """,
            arguments: [
                changeID,
                VidindirIdentity.personalWorkspace.description,
                entityID.description,
                timestamp,
            ]
        )
        try db.execute(
            sql: """
                INSERT INTO sync_outbox (endpoint_id, change_id, state, attempt_count)
                SELECT id, ?, 'pending', 0
                FROM sync_endpoints
                WHERE workspace_id = ? AND enabled = 1
                """,
            arguments: [changeID, VidindirIdentity.personalWorkspace.description]
        )
    }

    private static func refreshSearch(db: Database, mediaItemID: MediaItemID) throws {
        try db.execute(
            sql: """
                INSERT INTO media_search (
                    media_item_id, workspace_id, title, creator, source_url,
                    description, collection_names, tag_names
                )
                SELECT id, workspace_id, COALESCE(title, ''), '', source_url, '', '', ''
                FROM media_items WHERE id = ? AND deleted_at IS NULL
                """,
            arguments: [mediaItemID.description]
        )
    }

    private static func mappedState(_ legacyStatus: String) -> DownloadJobState {
        switch legacyStatus {
        case "queued": .queued
        case "failed": .failed
        case "cancelled": .cancelled
        case "completed": .completed
        case "preparing", "downloading", "postProcessing": .interrupted
        default: .interrupted
        }
    }

    private static let legacyStatuses = Set([
        "queued", "preparing", "downloading", "postProcessing",
        "completed", "failed", "cancelled",
    ])

    private static func validOutputURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.isFileURL
            && NSString(string: url.path).isAbsolutePath
            && url.path.utf8.count <= 4_096
    }

    private static func isValidVerifiedFile(
        _ file: LegacyVerifiedFile,
        for url: URL
    ) -> Bool {
        !file.bookmark.isEmpty
            && file.fileSizeBytes >= 0
            && NSString(string: file.path).isAbsolutePath
            && file.path.utf8.count <= 4_096
            && URL(fileURLWithPath: file.path).standardizedFileURL.path
                == url.standardizedFileURL.path
    }

    private static func errorFields(
        for record: PreparedLegacyRecord
    ) -> (category: String?, summary: String?) {
        if record.legacyStatus == "completed", record.state == .interrupted {
            return (
                "legacy_file_missing",
                "The earlier download is recorded, but its local file could not be verified."
            )
        }
        switch record.state {
        case .failed:
            return ("legacy_download_failed", "This earlier download failed.")
        case .interrupted:
            return (
                "legacy_download_interrupted",
                "The app closed before this earlier download finished."
            )
        default:
            return (nil, nil)
        }
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func isSQLiteDate(_ date: Date) -> Bool {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        return milliseconds.isFinite
            && milliseconds >= Double(Int64.min)
            && milliseconds <= Double(Int64.max)
    }

    private static func verifyLocalFileOnDisk(_ url: URL) -> LegacyVerifiedFile? {
        guard url.isFileURL,
              NSString(string: url.path).isAbsolutePath,
              url.path.utf8.count <= 4_096,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size >= 0 else {
            return nil
        }

        let bookmark: Data?
        if let scoped = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.isRegularFileKey],
            relativeTo: nil
        ) {
            bookmark = scoped
        } else if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            bookmark = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: [.isRegularFileKey],
                relativeTo: nil
            )
        } else {
            bookmark = nil
        }
        guard let bookmark, !bookmark.isEmpty else { return nil }
        return LegacyVerifiedFile(
            bookmark: bookmark,
            path: url.standardizedFileURL.path,
            fileSizeBytes: Int64(size)
        )
    }
}

struct LegacyVerifiedFile: Equatable, Sendable {
    let bookmark: Data
    let path: String
    let fileSizeBytes: Int64
}

private struct ParsedLegacyHistory {
    let records: [LegacyHistoryRecord]
    let skippedEntries: Int
}

struct LegacyHistoryRecord: Codable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let format: String
    let destinationDirectory: URL
    let outputFileURL: URL?
    let title: String?
    let status: String
    let startedAt: Date
    let finishedAt: Date?
}

private struct PreparedLegacyRecord: Sendable {
    let legacyID: UUID
    let source: CanonicalizedSource
    let mediaKind: MediaKind
    let container: String
    let title: String?
    let state: DownloadJobState
    let startedAt: Date
    let finishedAt: Date
    let destinationPath: String
    let requestJSON: String
    let verifiedFile: LegacyVerifiedFile?
    let legacyStatus: String
}
