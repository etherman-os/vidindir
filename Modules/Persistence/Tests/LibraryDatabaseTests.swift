import Foundation
import GRDB
import Testing
import VidindirDomain
@testable import VidindirPersistence

@Suite("Library database bootstrap and migrations")
struct LibraryDatabaseTests {
    @Test func freshBootstrapCreatesThePersonalFoundationIdempotently() throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }

        try assertBootstrap(database: fixture.database)
        #expect(try fixture.database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM change_journal")
        } == 2)

        let reopened = try LibraryDatabase(
            url: fixture.database.databaseURL,
            configuration: LibraryDatabaseConfiguration(
                currentDeviceID: fixture.deviceID,
                deviceDisplayName: "Renamed Test Mac",
                appVersion: "1.0-test",
                now: { fixture.now.addingTimeInterval(60) }
            )
        )
        try assertBootstrap(database: reopened)
        #expect(try reopened.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM change_journal")
        } == 2)
        #expect(try reopened.pool.read { db in
            try String.fetchOne(db, sql: "SELECT display_name FROM devices WHERE is_current = 1")
        } == "Renamed Test Mac")
    }

    @Test func databaseConnectionsUseTheRequiredSafetyPragmas() throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }

        let values = try fixture.database.pool.read { db in
            (
                try String.fetchOne(db, sql: "PRAGMA journal_mode"),
                try Int.fetchOne(db, sql: "PRAGMA foreign_keys"),
                try Int.fetchOne(db, sql: "PRAGMA synchronous"),
                try Int.fetchOne(db, sql: "PRAGMA busy_timeout")
            )
        }
        #expect(values.0?.lowercased() == "wal")
        #expect(values.1 == 1)
        #expect(values.2 == 1)
        #expect(values.3 == 5_000)
    }

    @Test func initialSchemaIncludesLocalSyncAndSearchBoundaries() throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }

        let requiredTables: Set<String> = [
            "workspaces", "media_items", "collections", "collection_memberships",
            "tags", "media_item_tags", "favorites", "workspace_settings", "devices",
            "local_assets", "download_jobs", "change_journal", "sync_endpoints",
            "sync_outbox", "sync_cursors", "sync_inbox", "sync_record_state",
            "engine_installations", "migration_state", "media_search",
        ]
        let tables = try fixture.database.pool.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
            ))
        }
        #expect(requiredTables.isSubset(of: tables))
        #expect(try fixture.database.pool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty
        })
    }

    private func assertBootstrap(database: LibraryDatabase) throws {
        let values = try database.pool.read { db in
            (
                try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM devices WHERE is_current = 1"
                ),
                try String.fetchOne(
                db,
                sql: "SELECT id FROM workspaces WHERE kind = 'personal' AND deleted_at IS NULL"
                ),
                try String.fetchOne(
                db,
                sql: "SELECT id FROM collections WHERE kind = 'system_inbox' AND deleted_at IS NULL"
                )
            )
        }
        #expect(values.0 == 1)
        #expect(values.1 == VidindirIdentity.personalWorkspace.description)
        #expect(values.2 == VidindirIdentity.personalInbox.description)
    }
}
