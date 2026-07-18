import Foundation
import GRDB
import VidindirDomain

public struct LibraryDatabaseConfiguration: Sendable {
    public let currentDeviceID: DeviceID
    public let deviceDisplayName: String
    public let appVersion: String?
    public let now: @Sendable () -> Date
    public let makeUUID: @Sendable () -> UUID

    public init(
        currentDeviceID: DeviceID,
        deviceDisplayName: String,
        appVersion: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.currentDeviceID = currentDeviceID
        self.deviceDisplayName = deviceDisplayName
        self.appVersion = appVersion
        self.now = now
        self.makeUUID = makeUUID
    }
}

public final class LibraryDatabase: Sendable {
    let pool: DatabasePool
    public let currentDeviceID: DeviceID
    public let databaseURL: URL

    public init(url: URL, configuration: LibraryDatabaseConfiguration) throws {
        databaseURL = url.standardizedFileURL
        currentDeviceID = configuration.currentDeviceID

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var databaseConfiguration = Configuration()
        databaseConfiguration.label = "Vidindir.Library"
        databaseConfiguration.foreignKeysEnabled = true
        databaseConfiguration.journalMode = .wal
        databaseConfiguration.busyMode = .timeout(5)
        databaseConfiguration.prepareDatabase { db in
            try db.execute(sql: """
                PRAGMA synchronous = NORMAL;
                PRAGMA busy_timeout = 5000;
                """)
        }

        pool = try DatabasePool(
            path: databaseURL.path,
            configuration: databaseConfiguration
        )
        try LibraryMigrations.migrator.migrate(pool)
        try bootstrap(configuration)
        try validateForeignKeys()
    }

    public static func defaultURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Vidindir", isDirectory: true)
            .appendingPathComponent("Library.sqlite", isDirectory: false)
    }

    private func bootstrap(_ configuration: LibraryDatabaseConfiguration) throws {
        let timestamp = configuration.now().sqliteMilliseconds
        let deviceID = configuration.currentDeviceID.description
        let workspaceID = VidindirIdentity.personalWorkspace.description
        let inboxID = VidindirIdentity.personalInbox.description

        try pool.write { db in
            try db.execute(
                sql: "UPDATE devices SET is_current = 0 WHERE is_current = 1 AND id <> ?",
                arguments: [deviceID]
            )
            try db.execute(
                sql: """
                    INSERT INTO devices (
                        id, display_name, platform, app_version,
                        created_at, last_seen_at, is_current
                    ) VALUES (?, ?, 'macos', ?, ?, ?, 1)
                    ON CONFLICT(id) DO UPDATE SET
                        display_name = excluded.display_name,
                        platform = excluded.platform,
                        app_version = excluded.app_version,
                        last_seen_at = excluded.last_seen_at,
                        is_current = 1
                    """,
                arguments: [
                    deviceID,
                    configuration.deviceDisplayName,
                    configuration.appVersion,
                    timestamp,
                    timestamp,
                ]
            )

            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO workspaces (
                        id, name, kind, revision, created_at, modified_at,
                        modified_by_device, deleted_at
                    ) VALUES (?, 'Personal Workspace', 'personal', 1, ?, ?, ?, NULL)
                    """,
                arguments: [workspaceID, timestamp, timestamp, deviceID]
            )
            if db.changesCount == 1 {
                try appendBootstrapChange(
                    db: db,
                    changeID: configuration.makeUUID(),
                    workspaceID: workspaceID,
                    entityType: "workspace",
                    entityID: workspaceID,
                    timestamp: timestamp
                )
            }

            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO collections (
                        id, workspace_id, name, kind, sort_order, color_token,
                        icon_name, revision, created_at, modified_at,
                        modified_by_device, deleted_at
                    ) VALUES (?, ?, 'Inbox', 'system_inbox', 0, NULL, 'tray', 1, ?, ?, ?, NULL)
                    """,
                arguments: [inboxID, workspaceID, timestamp, timestamp, deviceID]
            )
            if db.changesCount == 1 {
                try appendBootstrapChange(
                    db: db,
                    changeID: configuration.makeUUID(),
                    workspaceID: workspaceID,
                    entityType: "collection",
                    entityID: inboxID,
                    timestamp: timestamp
                )
            }
        }
    }

    private func validateForeignKeys() throws {
        try pool.read { db in
            let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard violations.isEmpty else {
                throw LibraryPersistenceError.foreignKeyViolation
            }
        }
    }

    private func appendBootstrapChange(
        db: Database,
        changeID: UUID,
        workspaceID: String,
        entityType: String,
        entityID: String,
        timestamp: Int64
    ) throws {
        let changeID = changeID.uuidString.lowercased()
        try db.execute(
            sql: """
                INSERT INTO change_journal (
                    change_id, workspace_id, entity_type, entity_id,
                    entity_revision, operation, origin, created_at
                ) VALUES (?, ?, ?, ?, 1, 'upsert', 'migration', ?)
                """,
            arguments: [changeID, workspaceID, entityType, entityID, timestamp]
        )
        try db.execute(
            sql: """
                INSERT INTO sync_outbox (endpoint_id, change_id, state, attempt_count)
                SELECT id, ?, 'pending', 0
                FROM sync_endpoints
                WHERE workspace_id = ? AND enabled = 1
                """,
            arguments: [changeID, workspaceID]
        )
    }
}

public enum LibraryPersistenceError: Error, Equatable, Sendable {
    case foreignKeyViolation
    case invalidStoredRecord
}

extension Date {
    var sqliteMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    init(sqliteMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(sqliteMilliseconds) / 1_000)
    }
}
