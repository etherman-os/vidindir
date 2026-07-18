import Foundation
import GRDB
import VidindirDomain

public actor GRDBLibraryRepository: LibraryRepository {
    private let pool: DatabasePool
    private let currentDeviceID: DeviceID
    private let canonicalizer: SourceCanonicalizer
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

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
    }

    public func saveLink(_ command: SaveLinkCommand) async throws -> SaveLinkResult {
        let source = try canonicalizer.canonicalize(command.sourceURL)
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let makeUUID = makeUUID

        return try await pool.write { db in
            let duplicates = try Self.duplicateCandidates(
                db: db,
                workspaceID: command.workspaceID,
                source: source
            )
            if !command.allowDuplicate, !duplicates.isEmpty {
                return .duplicate(duplicates)
            }

            let destinationCollectionID: CollectionID?
            switch command.destination {
            case .inbox:
                destinationCollectionID = VidindirIdentity.inboxCollection(
                    workspaceID: command.workspaceID
                )
            case .collection(let collectionID):
                destinationCollectionID = collectionID
            case .libraryOnly:
                destinationCollectionID = nil
            }
            if let destinationCollectionID {
                try Self.requireCollection(
                    db: db,
                    id: destinationCollectionID,
                    workspaceID: command.workspaceID
                )
            }
            try Self.requireWorkspace(db: db, id: command.workspaceID)

            let itemID = MediaItemID(makeUUID())
            let record = MediaItemRecord(
                id: itemID.description,
                workspaceID: command.workspaceID.description,
                sourceURL: source.sourceURL.absoluteString,
                canonicalURL: source.canonicalURL?.absoluteString,
                canonicalizationVersion: source.canonicalizationVersion,
                sourceType: source.sourceType.rawValue,
                sourceMediaID: source.sourceMediaID,
                title: nil,
                creator: nil,
                description: nil,
                durationSeconds: nil,
                thumbnailURL: nil,
                metadataStatus: MetadataStatus.unresolved.rawValue,
                metadataErrorCode: nil,
                revision: 1,
                createdAt: timestamp,
                modifiedAt: timestamp,
                modifiedByDevice: deviceID,
                deletedAt: nil
            )
            try record.insert(db)
            try Self.appendChange(
                db: db,
                changeID: makeUUID(),
                workspaceID: command.workspaceID,
                entityType: "media_item",
                entityID: itemID.description,
                revision: 1,
                operation: .upsert,
                timestamp: timestamp
            )

            if let destinationCollectionID {
                try Self.setMembership(
                    db: db,
                    workspaceID: command.workspaceID,
                    mediaItemID: itemID,
                    collectionID: destinationCollectionID,
                    isMember: true,
                    timestamp: timestamp,
                    deviceID: deviceID,
                    makeUUID: makeUUID
                )
            }
            try Self.refreshSearch(db: db, mediaItemID: itemID)
            return .saved(try record.domain())
        }
    }

    public func updateMedia(_ command: UpdateMediaCommand) async throws -> MediaItem {
        if let duration = command.metadata.durationSeconds,
           !duration.isFinite || duration < 0 {
            throw LibraryDomainError.invalidProgress
        }
        if let thumbnailURL = command.metadata.thumbnailURL,
           !Self.isHTTPURL(thumbnailURL) {
            throw LibraryDomainError.invalidSourceURL
        }
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let changeID = makeUUID()

        return try await pool.write { db in
            guard let existing = try MediaItemRecord.fetchOne(db, key: command.id.description),
                  existing.workspaceID == command.workspaceID.description,
                  existing.deletedAt == nil else {
                throw LibraryDomainError.recordNotFound
            }
            guard existing.revision == command.expectedRevision else {
                throw LibraryDomainError.concurrentModification
            }
            let revision = existing.revision + 1
            try db.execute(
                sql: """
                    UPDATE media_items
                    SET title = ?, creator = ?, description = ?, duration_seconds = ?,
                        thumbnail_url = ?, metadata_status = ?, metadata_error_code = ?,
                        revision = ?, modified_at = ?, modified_by_device = ?
                    WHERE id = ?
                    """,
                arguments: [
                    command.metadata.title,
                    command.metadata.creator,
                    command.metadata.description,
                    command.metadata.durationSeconds,
                    command.metadata.thumbnailURL?.absoluteString,
                    command.metadata.status.rawValue,
                    command.metadata.errorCode,
                    revision,
                    timestamp,
                    deviceID,
                    command.id.description,
                ]
            )
            try Self.appendChange(
                db: db,
                changeID: changeID,
                workspaceID: command.workspaceID,
                entityType: "media_item",
                entityID: command.id.description,
                revision: revision,
                operation: .upsert,
                timestamp: timestamp
            )
            try Self.refreshSearch(db: db, mediaItemID: command.id)
            guard let updated = try MediaItemRecord.fetchOne(db, key: command.id.description) else {
                throw LibraryPersistenceError.invalidStoredRecord
            }
            return try updated.domain()
        }
    }

    public func createCollection(_ command: CreateCollectionCommand) async throws -> Collection {
        let name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryDomainError.emptyName }
        guard command.sortOrder.isFinite else { throw LibraryDomainError.invalidProgress }

        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let collectionID = CollectionID(makeUUID())
        let changeID = makeUUID()
        let record = CollectionRecord(
            id: collectionID.description,
            workspaceID: command.workspaceID.description,
            name: name,
            kind: CollectionKind.user.rawValue,
            sortOrder: command.sortOrder,
            colorToken: command.colorToken,
            iconName: command.iconName,
            revision: 1,
            createdAt: timestamp,
            modifiedAt: timestamp,
            modifiedByDevice: deviceID,
            deletedAt: nil
        )

        return try await pool.write { db in
            try Self.requireWorkspace(db: db, id: command.workspaceID)
            try record.insert(db)
            try Self.appendChange(
                db: db,
                changeID: changeID,
                workspaceID: command.workspaceID,
                entityType: "collection",
                entityID: collectionID.description,
                revision: 1,
                operation: .upsert,
                timestamp: timestamp
            )
            return try record.domain()
        }
    }

    public func collections(workspaceID: WorkspaceID) async throws -> [Collection] {
        try await pool.read { db in
            try CollectionRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM collections
                    WHERE workspace_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order, name COLLATE NOCASE, id
                    """,
                arguments: [workspaceID.description]
            ).map { try $0.domain() }
        }
    }

    public func setFavorite(
        mediaID: MediaItemID,
        workspaceID: WorkspaceID,
        value: Bool
    ) async throws {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let changeID = makeUUID()

        try await pool.write { db in
            try Self.requireMedia(db: db, id: mediaID, workspaceID: workspaceID)
            let id = VidindirIdentity.favorite(
                workspaceID: workspaceID,
                mediaItemID: mediaID
            )
            let existing = try FavoriteRecord.fetchOne(
                db,
                key: id.description
            )
            if value {
                guard existing?.deletedAt != nil || existing == nil else { return }
                let revision = (existing?.revision ?? 0) + 1
                let createdAt = existing?.createdAt ?? timestamp
                try FavoriteRecord(
                    id: id.description,
                    workspaceID: workspaceID.description,
                    mediaItemID: mediaID.description,
                    revision: revision,
                    createdAt: createdAt,
                    modifiedAt: timestamp,
                    modifiedByDevice: deviceID,
                    deletedAt: nil
                ).save(db)
                try Self.appendChange(
                    db: db,
                    changeID: changeID,
                    workspaceID: workspaceID,
                    entityType: "favorite",
                    entityID: id.description,
                    revision: revision,
                    operation: .upsert,
                    timestamp: timestamp
                )
            } else {
                guard let existing, existing.deletedAt == nil else { return }
                let revision = existing.revision + 1
                try db.execute(
                    sql: """
                        UPDATE favorites
                        SET revision = ?, modified_at = ?, modified_by_device = ?, deleted_at = ?
                        WHERE id = ?
                        """,
                    arguments: [revision, timestamp, deviceID, timestamp, id.description]
                )
                try Self.appendChange(
                    db: db,
                    changeID: changeID,
                    workspaceID: workspaceID,
                    entityType: "favorite",
                    entityID: id.description,
                    revision: revision,
                    operation: .tombstone,
                    timestamp: timestamp
                )
            }
        }
    }

    public func setCollectionMembership(_ command: MembershipCommand) async throws {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let makeUUID = makeUUID
        try await pool.write { db in
            try Self.setMembership(
                db: db,
                workspaceID: command.workspaceID,
                mediaItemID: command.mediaItemID,
                collectionID: command.collectionID,
                isMember: command.isMember,
                timestamp: timestamp,
                deviceID: deviceID,
                makeUUID: makeUUID
            )
            try Self.refreshSearch(db: db, mediaItemID: command.mediaItemID)
        }
    }

    public func organizeFromInbox(
        mediaID: MediaItemID,
        workspaceID: WorkspaceID,
        collectionIDs: [CollectionID]
    ) async throws {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let makeUUID = makeUUID
        try await pool.write { db in
            for collectionID in Set(collectionIDs) {
                try Self.setMembership(
                    db: db,
                    workspaceID: workspaceID,
                    mediaItemID: mediaID,
                    collectionID: collectionID,
                    isMember: true,
                    timestamp: timestamp,
                    deviceID: deviceID,
                    makeUUID: makeUUID
                )
            }
            try Self.setMembership(
                db: db,
                workspaceID: workspaceID,
                mediaItemID: mediaID,
                collectionID: VidindirIdentity.inboxCollection(workspaceID: workspaceID),
                isMember: false,
                timestamp: timestamp,
                deviceID: deviceID,
                makeUUID: makeUUID
            )
            try Self.refreshSearch(db: db, mediaItemID: mediaID)
        }
    }

    public func tombstoneMedia(
        id: MediaItemID,
        workspaceID: WorkspaceID,
        expectedRevision: Int64
    ) async throws {
        let timestamp = now().sqliteMilliseconds
        let deviceID = currentDeviceID.description
        let changeID = makeUUID()
        try await pool.write { db in
            guard let record = try MediaItemRecord.fetchOne(db, key: id.description),
                  record.workspaceID == workspaceID.description,
                  record.deletedAt == nil else {
                throw LibraryDomainError.recordNotFound
            }
            guard record.revision == expectedRevision else {
                throw LibraryDomainError.concurrentModification
            }
            let revision = expectedRevision + 1
            try db.execute(
                sql: """
                    UPDATE media_items
                    SET revision = ?, modified_at = ?, modified_by_device = ?, deleted_at = ?
                    WHERE id = ?
                    """,
                arguments: [revision, timestamp, deviceID, timestamp, id.description]
            )
            try Self.appendChange(
                db: db,
                changeID: changeID,
                workspaceID: workspaceID,
                entityType: "media_item",
                entityID: id.description,
                revision: revision,
                operation: .tombstone,
                timestamp: timestamp
            )
            try db.execute(
                sql: "DELETE FROM media_search WHERE media_item_id = ?",
                arguments: [id.description]
            )
        }
    }

    public func page(_ query: LibraryQuery) async throws -> LibraryPage {
        guard (1...500).contains(query.limit), query.offset >= 0 else {
            throw LibraryDomainError.invalidPagination
        }
        let currentDeviceID = currentDeviceID.description

        return try await pool.read { db in
            var predicate = "m.workspace_id = ? AND m.deleted_at IS NULL"
            var arguments: StatementArguments = [query.workspaceID.description]
            switch query.scope {
            case .all:
                break
            case .inbox:
                predicate += "\n" + """
                    AND EXISTS (
                        SELECT 1 FROM collection_memberships cm
                        JOIN collections c ON c.id = cm.collection_id
                        WHERE cm.media_item_id = m.id
                          AND cm.collection_id = ?
                          AND cm.deleted_at IS NULL
                          AND c.deleted_at IS NULL
                    )
                    """
                arguments += [VidindirIdentity.inboxCollection(
                    workspaceID: query.workspaceID
                ).description]
            case .favorites:
                predicate += "\n" + """
                    AND EXISTS (
                        SELECT 1 FROM favorites f
                        WHERE f.media_item_id = m.id
                          AND f.workspace_id = m.workspace_id
                          AND f.deleted_at IS NULL
                    )
                    """
            case .collection(let collectionID):
                predicate += "\n" + """
                    AND EXISTS (
                        SELECT 1 FROM collection_memberships cm
                        JOIN collections c ON c.id = cm.collection_id
                        WHERE cm.media_item_id = m.id
                          AND cm.collection_id = ?
                          AND cm.deleted_at IS NULL
                          AND c.deleted_at IS NULL
                    )
                    """
                arguments += [collectionID.description]
            }

            if let searchText = query.searchText?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !searchText.isEmpty {
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: searchText) else {
                    return LibraryPage(items: [], totalCount: 0)
                }
                predicate += "\n" + """
                    AND m.id IN (
                        SELECT media_item_id FROM media_search
                        WHERE media_search MATCH ? AND workspace_id = ?
                    )
                    """
                arguments += [pattern, query.workspaceID.description]
            }

            let totalCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM media_items m WHERE \(predicate)",
                arguments: arguments
            ) ?? 0

            var pageArguments = arguments
            pageArguments += [query.limit, query.offset]
            let records = try MediaItemRecord.fetchAll(
                db,
                sql: """
                    SELECT m.* FROM media_items m
                    WHERE \(predicate)
                    ORDER BY m.created_at DESC, m.id
                    LIMIT ? OFFSET ?
                    """,
                arguments: pageArguments
            )
            let items = try records.map { record in
                let item = try record.domain()
                let favoriteCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM favorites
                        WHERE media_item_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [record.id]
                ) ?? 0
                let collectionStrings = try String.fetchAll(
                    db,
                    sql: """
                        SELECT cm.collection_id
                        FROM collection_memberships cm
                        JOIN collections c ON c.id = cm.collection_id
                        WHERE cm.media_item_id = ?
                          AND cm.deleted_at IS NULL
                          AND c.deleted_at IS NULL
                        ORDER BY c.sort_order, c.name COLLATE NOCASE, c.id
                        """,
                    arguments: [record.id]
                )
                let collectionIDs = try collectionStrings.map { value -> CollectionID in
                    guard let id = CollectionID(uuidString: value) else {
                        throw LibraryPersistenceError.invalidStoredRecord
                    }
                    return id
                }
                let localStatus = try String.fetchOne(
                    db,
                    sql: """
                        SELECT status FROM local_assets
                        WHERE media_item_id = ? AND device_id = ?
                        ORDER BY downloaded_at DESC, id DESC LIMIT 1
                        """,
                    arguments: [record.id, currentDeviceID]
                ).map { LocalAssetStatus(rawValue: $0) }
                let jobState = try String.fetchOne(
                    db,
                    sql: """
                        SELECT state FROM download_jobs
                        WHERE media_item_id = ? AND device_id = ?
                        ORDER BY created_at DESC, id DESC LIMIT 1
                        """,
                    arguments: [record.id, currentDeviceID]
                ).map { DownloadJobState(rawValue: $0) }
                return LibraryItemSummary(
                    mediaItem: item,
                    isFavorite: favoriteCount > 0,
                    collectionIDs: collectionIDs,
                    localAssetStatus: localStatus,
                    latestDownloadState: jobState
                )
            }
            return LibraryPage(items: items, totalCount: totalCount)
        }
    }

    private static func duplicateCandidates(
        db: Database,
        workspaceID: WorkspaceID,
        source: CanonicalizedSource
    ) throws -> [DuplicateCandidate] {
        let records = try MediaItemRecord.fetchAll(
            db,
            sql: """
                SELECT * FROM media_items
                WHERE workspace_id = ? AND deleted_at IS NULL AND (
                    (? IS NOT NULL AND source_type = ? AND source_media_id = ?)
                    OR (? IS NOT NULL AND canonical_url = ?)
                    OR source_url = ?
                )
                ORDER BY created_at DESC, id
                """,
            arguments: [
                workspaceID.description,
                source.sourceMediaID,
                source.sourceType.rawValue,
                source.sourceMediaID,
                source.canonicalURL?.absoluteString,
                source.canonicalURL?.absoluteString,
                source.sourceURL.absoluteString,
            ]
        )
        return try records.map { record in
            let reason: DuplicateReason
            if let sourceMediaID = source.sourceMediaID,
               record.sourceType == source.sourceType.rawValue,
               record.sourceMediaID == sourceMediaID {
                reason = .sourceIdentity
            } else if record.canonicalURL == source.canonicalURL?.absoluteString {
                reason = .canonicalURL
            } else {
                reason = .sourceURL
            }
            return DuplicateCandidate(mediaItem: try record.domain(), reason: reason)
        }.sorted { lhs, rhs in
            Self.duplicateRank(lhs.reason) < Self.duplicateRank(rhs.reason)
        }
    }

    private static func duplicateRank(_ reason: DuplicateReason) -> Int {
        switch reason {
        case .sourceIdentity: 0
        case .canonicalURL: 1
        case .sourceURL: 2
        }
    }

    private static func requireWorkspace(db: Database, id: WorkspaceID) throws {
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM workspaces WHERE id = ? AND deleted_at IS NULL",
            arguments: [id.description]
        ) ?? 0
        guard count == 1 else { throw LibraryDomainError.recordNotFound }
    }

    private static func requireMedia(
        db: Database,
        id: MediaItemID,
        workspaceID: WorkspaceID
    ) throws {
        let count = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM media_items
                WHERE id = ? AND workspace_id = ? AND deleted_at IS NULL
                """,
            arguments: [id.description, workspaceID.description]
        ) ?? 0
        guard count == 1 else {
            let existsElsewhere = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM media_items WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.description]
            ) ?? 0
            throw existsElsewhere > 0
                ? LibraryDomainError.crossWorkspaceRelationship
                : LibraryDomainError.recordNotFound
        }
    }

    private static func requireCollection(
        db: Database,
        id: CollectionID,
        workspaceID: WorkspaceID
    ) throws {
        let count = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM collections
                WHERE id = ? AND workspace_id = ? AND deleted_at IS NULL
                """,
            arguments: [id.description, workspaceID.description]
        ) ?? 0
        guard count == 1 else {
            let existsElsewhere = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM collections WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.description]
            ) ?? 0
            throw existsElsewhere > 0
                ? LibraryDomainError.crossWorkspaceRelationship
                : LibraryDomainError.recordNotFound
        }
    }

    private static func setMembership(
        db: Database,
        workspaceID: WorkspaceID,
        mediaItemID: MediaItemID,
        collectionID: CollectionID,
        isMember: Bool,
        timestamp: Int64,
        deviceID: String,
        makeUUID: @Sendable () -> UUID
    ) throws {
        try requireMedia(db: db, id: mediaItemID, workspaceID: workspaceID)
        try requireCollection(db: db, id: collectionID, workspaceID: workspaceID)
        let id = VidindirIdentity.collectionMembership(
            workspaceID: workspaceID,
            collectionID: collectionID,
            mediaItemID: mediaItemID
        )
        let existing = try CollectionMembershipRecord.fetchOne(db, key: id.description)
        if isMember {
            guard existing?.deletedAt != nil || existing == nil else { return }
            let revision = (existing?.revision ?? 0) + 1
            try CollectionMembershipRecord(
                id: id.description,
                workspaceID: workspaceID.description,
                collectionID: collectionID.description,
                mediaItemID: mediaItemID.description,
                sortOrder: existing?.sortOrder,
                revision: revision,
                createdAt: existing?.createdAt ?? timestamp,
                modifiedAt: timestamp,
                modifiedByDevice: deviceID,
                deletedAt: nil
            ).save(db)
            try appendChange(
                db: db,
                changeID: makeUUID(),
                workspaceID: workspaceID,
                entityType: "collection_membership",
                entityID: id.description,
                revision: revision,
                operation: .upsert,
                timestamp: timestamp
            )
        } else {
            guard let existing, existing.deletedAt == nil else { return }
            let revision = existing.revision + 1
            try db.execute(
                sql: """
                    UPDATE collection_memberships
                    SET revision = ?, modified_at = ?, modified_by_device = ?, deleted_at = ?
                    WHERE id = ?
                    """,
                arguments: [revision, timestamp, deviceID, timestamp, id.description]
            )
            try appendChange(
                db: db,
                changeID: makeUUID(),
                workspaceID: workspaceID,
                entityType: "collection_membership",
                entityID: id.description,
                revision: revision,
                operation: .tombstone,
                timestamp: timestamp
            )
        }
    }

    private static func appendChange(
        db: Database,
        changeID: UUID,
        workspaceID: WorkspaceID,
        entityType: String,
        entityID: String,
        revision: Int64,
        operation: ChangeOperation,
        timestamp: Int64
    ) throws {
        let changeID = changeID.uuidString.lowercased()
        try db.execute(
            sql: """
                INSERT INTO change_journal (
                    change_id, workspace_id, entity_type, entity_id,
                    entity_revision, operation, origin, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'local', ?)
                """,
            arguments: [
                changeID,
                workspaceID.description,
                entityType,
                entityID,
                revision,
                operation.rawValue,
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
            arguments: [changeID, workspaceID.description]
        )
    }

    private static func refreshSearch(db: Database, mediaItemID: MediaItemID) throws {
        try db.execute(
            sql: "DELETE FROM media_search WHERE media_item_id = ?",
            arguments: [mediaItemID.description]
        )
        try db.execute(
            sql: """
                INSERT INTO media_search (
                    media_item_id, workspace_id, title, creator, source_url,
                    description, collection_names, tag_names
                )
                SELECT
                    m.id,
                    m.workspace_id,
                    COALESCE(m.title, ''),
                    COALESCE(m.creator, ''),
                    m.source_url,
                    COALESCE(m.description, ''),
                    COALESCE((
                        SELECT group_concat(c.name, ' ')
                        FROM collection_memberships cm
                        JOIN collections c ON c.id = cm.collection_id
                        WHERE cm.media_item_id = m.id
                          AND cm.deleted_at IS NULL
                          AND c.deleted_at IS NULL
                    ), ''),
                    COALESCE((
                        SELECT group_concat(t.name, ' ')
                        FROM media_item_tags mit
                        JOIN tags t ON t.id = mit.tag_id
                        WHERE mit.media_item_id = m.id
                          AND mit.deleted_at IS NULL
                          AND t.deleted_at IS NULL
                    ), '')
                FROM media_items m
                WHERE m.id = ? AND m.deleted_at IS NULL
                """,
            arguments: [mediaItemID.description]
        )
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
