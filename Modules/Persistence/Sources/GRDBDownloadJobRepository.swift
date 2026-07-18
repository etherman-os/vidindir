import Foundation
import GRDB
import VidindirDomain

public actor GRDBDownloadJobRepository: DownloadJobRepository {
    private let pool: DatabasePool
    private let currentDeviceID: DeviceID
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

    public init(
        database: LibraryDatabase,
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        pool = database.pool
        currentDeviceID = database.currentDeviceID
        self.now = now
        self.makeUUID = makeUUID
    }

    public func createJob(_ command: CreateDownloadJobCommand) async throws -> DownloadJob {
        try Self.validateCreateCommand(command)
        let jobID = DownloadJobID(makeUUID())
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description

        return try await pool.write { db in
            guard let mediaExists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM media_items WHERE id = ? AND deleted_at IS NULL)",
                arguments: [command.mediaItemID.description]
            ), mediaExists else {
                throw LibraryDomainError.recordNotFound
            }

            if let parentJobID = command.parentJobID {
                guard let parent = try DownloadJobRecord.fetchOne(
                    db,
                    key: parentJobID.description
                ) else {
                    throw LibraryDomainError.recordNotFound
                }
                guard parent.deviceID == deviceID,
                      parent.mediaItemID == command.mediaItemID.description else {
                    throw LibraryDomainError.invalidDownloadRequest
                }
            }

            let record = DownloadJobRecord(
                id: jobID.description,
                mediaItemID: command.mediaItemID.description,
                deviceID: deviceID,
                parentJobID: command.parentJobID?.description,
                backendID: Self.normalizedOptional(command.backendID),
                engineVersion: Self.normalizedOptional(command.engineVersion),
                state: DownloadJobState.created.rawValue,
                mediaKind: command.mediaKind.rawValue,
                container: Self.normalizedOptional(command.container),
                qualityPreset: command.qualityPreset.rawValue,
                requestJSON: command.requestJSON,
                destinationBookmark: command.destinationBookmark,
                destinationPath: command.destinationPath,
                progressFraction: nil,
                downloadedBytes: nil,
                totalBytes: nil,
                speedBytesPerSecond: nil,
                estimatedRemainingSeconds: nil,
                attemptCount: 0,
                retryAfter: nil,
                errorCategory: nil,
                errorSummary: nil,
                technicalDetail: nil,
                backendResumeData: nil,
                localAssetID: nil,
                createdAt: timestamp,
                queuedAt: nil,
                startedAt: nil,
                completedAt: nil,
                modifiedAt: timestamp
            )
            try record.insert(db)
            return try record.domain()
        }
    }

    public func transitionJob(
        id: DownloadJobID,
        from expectedState: DownloadJobState,
        to newState: DownloadJobState
    ) async throws -> DownloadJob {
        guard Self.allowedTransitions[expectedState]?.contains(newState) == true,
              newState != .completed,
              newState != .failed else {
            throw LibraryDomainError.invalidDownloadTransition
        }

        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        return try await pool.write { db in
            let existing = try Self.requireJob(db: db, id: id, deviceID: deviceID)
            guard existing.state == expectedState.rawValue else {
                throw LibraryDomainError.invalidDownloadTransition
            }

            var assignments = ["state = ?", "modified_at = ?"]
            var arguments: StatementArguments = [newState.rawValue, timestamp]
            if newState == .queued {
                assignments += [
                    "queued_at = ?",
                    "retry_after = NULL",
                    "error_category = NULL",
                    "error_summary = NULL",
                    "technical_detail = NULL",
                ]
                arguments += [timestamp]
            }
            if newState == .downloading {
                assignments += [
                    "started_at = COALESCE(started_at, ?)",
                    "attempt_count = attempt_count + 1",
                ]
                arguments += [timestamp]
            }
            if newState == .cancelled || newState == .interrupted {
                assignments += ["speed_bytes_per_second = NULL", "estimated_remaining_sec = NULL"]
            }

            arguments += [id.description, deviceID, expectedState.rawValue]
            try db.execute(
                sql: """
                    UPDATE download_jobs
                    SET \(assignments.joined(separator: ", "))
                    WHERE id = ? AND device_id = ? AND state = ?
                    """,
                arguments: arguments
            )
            guard db.changesCount == 1 else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            return try Self.requireJob(db: db, id: id, deviceID: deviceID).domain()
        }
    }

    public func updateProgress(
        jobID: DownloadJobID,
        update: DownloadProgressUpdate
    ) async throws -> DownloadJob {
        try Self.validateProgress(update)
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description

        return try await pool.write { db in
            let existing = try Self.requireJob(db: db, id: jobID, deviceID: deviceID)
            let state = DownloadJobState(rawValue: existing.state)
            guard state == .downloading || state == .postProcessing else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            if let downloaded = update.downloadedBytes,
               let total = update.totalBytes,
               downloaded > total {
                throw LibraryDomainError.invalidProgress
            }
            try db.execute(
                sql: """
                    UPDATE download_jobs
                    SET progress_fraction = ?, downloaded_bytes = ?, total_bytes = ?,
                        speed_bytes_per_second = ?, estimated_remaining_sec = ?, modified_at = ?
                    WHERE id = ? AND device_id = ? AND state IN ('downloading', 'post_processing')
                    """,
                arguments: [
                    update.fraction,
                    update.downloadedBytes,
                    update.totalBytes,
                    update.speedBytesPerSecond,
                    update.estimatedRemainingSeconds,
                    timestamp,
                    jobID.description,
                    deviceID,
                ]
            )
            guard db.changesCount == 1 else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            return try Self.requireJob(db: db, id: jobID, deviceID: deviceID).domain()
        }
    }

    public func failJob(id: DownloadJobID, failure: DownloadFailure) async throws -> DownloadJob {
        let category = try Self.requiredBounded(failure.category, maximumUTF8Bytes: 128)
        let summary = try Self.requiredBounded(failure.summary, maximumUTF8Bytes: 512)
        let detail = try Self.optionalBounded(failure.technicalDetail, maximumUTF8Bytes: 16_384)
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description

        return try await pool.write { db in
            let existing = try Self.requireJob(db: db, id: id, deviceID: deviceID)
            let currentState = DownloadJobState(rawValue: existing.state)
            guard Self.allowedTransitions[currentState]?.contains(.failed) == true else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            try db.execute(
                sql: """
                    UPDATE download_jobs
                    SET state = 'failed', retry_after = ?, error_category = ?, error_summary = ?,
                        technical_detail = ?, speed_bytes_per_second = NULL,
                        estimated_remaining_sec = NULL, modified_at = ?
                    WHERE id = ? AND device_id = ? AND state = ?
                    """,
                arguments: [
                    failure.retryAfter?.sqliteMilliseconds,
                    category,
                    summary,
                    detail,
                    timestamp,
                    id.description,
                    deviceID,
                    existing.state,
                ]
            )
            guard db.changesCount == 1 else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            return try Self.requireJob(db: db, id: id, deviceID: deviceID).domain()
        }
    }

    public func completeJob(id: DownloadJobID, asset: VerifiedLocalAsset) async throws -> DownloadJob {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let assetID = LocalAssetID(makeUUID())

        return try await pool.write { db in
            let existing = try Self.requireJob(db: db, id: id, deviceID: deviceID)
            guard DownloadJobState(rawValue: existing.state) == .postProcessing else {
                throw LibraryDomainError.invalidDownloadTransition
            }

            let assetRecord = LocalAssetRecord(
                id: assetID.description,
                mediaItemID: existing.mediaItemID,
                deviceID: deviceID,
                fileBookmark: asset.fileBookmark,
                lastKnownPath: asset.absolutePath,
                fileSizeBytes: asset.fileSizeBytes,
                contentType: Self.normalizedOptional(asset.contentType),
                container: Self.normalizedOptional(asset.container),
                checksumSHA256: Self.normalizedOptional(asset.checksumSHA256),
                status: LocalAssetStatus.available.rawValue,
                downloadedAt: timestamp,
                lastVerifiedAt: asset.verifiedAt.sqliteMilliseconds,
                removedAt: nil,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            try assetRecord.insert(db)
            try db.execute(
                sql: """
                    UPDATE download_jobs
                    SET state = 'completed', progress_fraction = 1,
                        downloaded_bytes = COALESCE(downloaded_bytes, ?),
                        total_bytes = COALESCE(total_bytes, ?),
                        speed_bytes_per_second = NULL, estimated_remaining_sec = 0,
                        retry_after = NULL, error_category = NULL, error_summary = NULL,
                        technical_detail = NULL, local_asset_id = ?, completed_at = ?, modified_at = ?
                    WHERE id = ? AND device_id = ? AND state = 'post_processing'
                    """,
                arguments: [
                    asset.fileSizeBytes,
                    asset.fileSizeBytes,
                    assetID.description,
                    timestamp,
                    timestamp,
                    id.description,
                    deviceID,
                ]
            )
            guard db.changesCount == 1 else {
                throw LibraryDomainError.invalidDownloadTransition
            }
            return try Self.requireJob(db: db, id: id, deviceID: deviceID).domain()
        }
    }

    public func interruptActiveJobsAfterLaunch() async throws -> Int {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        return try await pool.write { db in
            try db.execute(
                sql: """
                    UPDATE download_jobs
                    SET state = 'interrupted', error_category = 'app_interrupted',
                        error_summary = 'The app closed before this download finished.',
                        technical_detail = NULL, speed_bytes_per_second = NULL,
                        estimated_remaining_sec = NULL, modified_at = ?
                    WHERE device_id = ?
                      AND state IN ('resolving', 'downloading', 'post_processing')
                    """,
                arguments: [timestamp, deviceID]
            )
            return db.changesCount
        }
    }

    public func jobs(_ query: DownloadJobQuery) async throws -> [DownloadJob] {
        guard (1...500).contains(query.limit), query.offset >= 0 else {
            throw LibraryDomainError.invalidPagination
        }
        let deviceID = currentDeviceID.description
        return try await pool.read { db in
            var conditions = ["device_id = ?"]
            var arguments: StatementArguments = [deviceID]
            if !query.states.isEmpty {
                let states = query.states.sorted().map(\.rawValue)
                conditions.append("state IN (\(Array(repeating: "?", count: states.count).joined(separator: ", ")))")
                arguments += StatementArguments(states)
            }
            arguments += [query.limit, query.offset]
            return try DownloadJobRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM download_jobs
                    WHERE \(conditions.joined(separator: " AND "))
                    ORDER BY created_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: arguments
            ).map { try $0.domain() }
        }
    }

    public func localAssets(mediaItemID: MediaItemID) async throws -> [LocalAsset] {
        let deviceID = currentDeviceID.description
        return try await pool.read { db in
            try LocalAssetRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_assets
                    WHERE media_item_id = ? AND device_id = ?
                    ORDER BY downloaded_at DESC, id DESC
                    """,
                arguments: [mediaItemID.description, deviceID]
            ).map { try $0.domain() }
        }
    }

    public func markLocalAssetMissing(id: LocalAssetID) async throws -> LocalAsset {
        try await setLocalAssetStatus(id: id, status: .missing)
    }

    public func markLocalAssetRemoved(id: LocalAssetID) async throws -> LocalAsset {
        try await setLocalAssetStatus(id: id, status: .removed)
    }

    private func setLocalAssetStatus(
        id: LocalAssetID,
        status: LocalAssetStatus
    ) async throws -> LocalAsset {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        return try await pool.write { db in
            guard let existing = try LocalAssetRecord.fetchOne(db, key: id.description),
                  existing.deviceID == deviceID else {
                throw LibraryDomainError.recordNotFound
            }
            let removedAt = status == .removed ? timestamp : nil
            try db.execute(
                sql: """
                    UPDATE local_assets
                    SET status = ?, removed_at = ?, modified_at = ?
                    WHERE id = ? AND device_id = ?
                    """,
                arguments: [status.rawValue, removedAt, timestamp, id.description, deviceID]
            )
            guard let updated = try LocalAssetRecord.fetchOne(db, key: id.description) else {
                throw LibraryPersistenceError.invalidStoredRecord
            }
            return try updated.domain()
        }
    }

    private static let allowedTransitions: [DownloadJobState: Set<DownloadJobState>] = [
        .created: [.resolving, .cancelled],
        .resolving: [.ready, .failed, .cancelled, .interrupted],
        .ready: [.queued, .cancelled],
        .queued: [.downloading, .paused, .failed, .cancelled, .interrupted],
        .downloading: [.paused, .postProcessing, .failed, .cancelled, .interrupted],
        .postProcessing: [.completed, .failed, .cancelled, .interrupted],
        .paused: [.queued, .cancelled],
        .failed: [.queued, .cancelled],
        .interrupted: [.queued, .cancelled],
        .completed: [],
        .cancelled: [],
    ]

    private static func requireJob(
        db: Database,
        id: DownloadJobID,
        deviceID: String
    ) throws -> DownloadJobRecord {
        guard let record = try DownloadJobRecord.fetchOne(db, key: id.description),
              record.deviceID == deviceID else {
            throw LibraryDomainError.recordNotFound
        }
        return record
    }

    private static func validateCreateCommand(_ command: CreateDownloadJobCommand) throws {
        guard !command.requestJSON.isEmpty,
              command.requestJSON.utf8.count <= 65_536,
              command.destinationPath.utf8.count <= 4_096,
              NSString(string: command.destinationPath).isAbsolutePath,
              !command.mediaKind.rawValue.isEmpty,
              command.mediaKind.rawValue.utf8.count <= 64,
              !command.qualityPreset.rawValue.isEmpty,
              command.qualityPreset.rawValue.utf8.count <= 64 else {
            throw LibraryDomainError.invalidDownloadRequest
        }
        _ = try optionalBounded(command.backendID, maximumUTF8Bytes: 128)
        _ = try optionalBounded(command.engineVersion, maximumUTF8Bytes: 128)
        _ = try optionalBounded(command.container, maximumUTF8Bytes: 64)

        guard let data = command.requestJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any],
              !containsCredential(object) else {
            throw LibraryDomainError.invalidDownloadRequest
        }
    }

    private static func containsCredential(_ value: Any) -> Bool {
        let forbiddenKeys = Set([
            "authorization", "cookie", "cookies", "password", "passwd", "secret",
            "token", "access_token", "refresh_token", "api_key", "apikey",
        ])
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
                if forbiddenKeys.contains(normalized) || containsCredential(nestedValue) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsCredential)
        }
        return false
    }

    private static func validateProgress(_ update: DownloadProgressUpdate) throws {
        if let value = update.fraction,
           !value.isFinite || !(0...1).contains(value) {
            throw LibraryDomainError.invalidProgress
        }
        if let value = update.downloadedBytes, value < 0 {
            throw LibraryDomainError.invalidProgress
        }
        if let value = update.totalBytes, value < 0 {
            throw LibraryDomainError.invalidProgress
        }
        if let value = update.speedBytesPerSecond, !value.isFinite || value < 0 {
            throw LibraryDomainError.invalidProgress
        }
        if let value = update.estimatedRemainingSeconds, !value.isFinite || value < 0 {
            throw LibraryDomainError.invalidProgress
        }
    }

    private static func requiredBounded(
        _ value: String,
        maximumUTF8Bytes: Int
    ) throws -> String {
        guard let value = try optionalBounded(value, maximumUTF8Bytes: maximumUTF8Bytes) else {
            throw LibraryDomainError.invalidDownloadRequest
        }
        return value
    }

    private static func optionalBounded(
        _ value: String?,
        maximumUTF8Bytes: Int
    ) throws -> String? {
        guard let normalized = normalizedOptional(value) else { return nil }
        guard normalized.utf8.count <= maximumUTF8Bytes else {
            throw LibraryDomainError.invalidDownloadRequest
        }
        return normalized
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
