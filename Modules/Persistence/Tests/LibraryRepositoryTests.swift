import Foundation
import GRDB
import Testing
import VidindirDomain
@testable import VidindirPersistence

@Suite("GRDB library repository")
struct LibraryRepositoryTests {
    @Test func duplicateDetectionWarnsButConfirmedDuplicatesRemainPossible() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }

        let shortURL = try #require(URL(
            string: "https://youtube.com/shorts/OpeV9uFQcGg?si=DtvxWBZOFToIeZpd"
        ))
        let first = try requireSaved(await fixture.repository.saveLink(
            SaveLinkCommand(sourceURL: shortURL)
        ))
        let watchURL = try #require(URL(
            string: "https://www.youtube.com/watch?v=OpeV9uFQcGg&t=30"
        ))
        let duplicate = try await fixture.repository.saveLink(
            SaveLinkCommand(sourceURL: watchURL)
        )
        guard case .duplicate(let candidates) = duplicate else {
            Issue.record("Expected a duplicate warning")
            return
        }
        #expect(candidates.map(\.mediaItem.id) == [first.id])
        #expect(candidates.map(\.reason) == [.sourceIdentity])
        #expect(try await fixture.repository.page(LibraryQuery(scope: .inbox)).totalCount == 1)

        _ = try requireSaved(await fixture.repository.saveLink(
            SaveLinkCommand(sourceURL: watchURL, allowDuplicate: true)
        ))
        #expect(try await fixture.repository.page(LibraryQuery(scope: .inbox)).totalCount == 2)
        let journalCount = try await fixture.database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM change_journal")
        }
        #expect(journalCount == 6)
    }

    @Test func collectionsFavoritesMetadataAndSearchStayTransactionallyAligned() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let sourceURL = try #require(URL(string: "https://example.com/swift-video"))
        let item = try requireSaved(await fixture.repository.saveLink(
            SaveLinkCommand(sourceURL: sourceURL, destination: .libraryOnly)
        ))
        let updated = try await fixture.repository.updateMedia(UpdateMediaCommand(
            id: item.id,
            workspaceID: item.workspaceID,
            expectedRevision: item.version.revision,
            metadata: MediaMetadataUpdate(
                title: "İstanbul SwiftUI Architecture",
                creator: "Etherman Design",
                description: "Calm native interface research",
                durationSeconds: 93,
                thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
                status: .resolved
            )
        ))
        #expect(updated.version.revision == 2)

        let collection = try await fixture.repository.createCollection(
            CreateCollectionCommand(name: "Programming")
        )
        try await fixture.repository.setCollectionMembership(MembershipCommand(
            workspaceID: item.workspaceID,
            mediaItemID: item.id,
            collectionID: collection.id,
            isMember: true
        ))
        try await fixture.repository.setFavorite(
            mediaID: item.id,
            workspaceID: item.workspaceID,
            value: true
        )

        #expect(try await fixture.repository.page(
            LibraryQuery(scope: .collection(collection.id))
        ).items.map(\.id) == [item.id])
        #expect(try await fixture.repository.page(
            LibraryQuery(scope: .favorites)
        ).items.map(\.id) == [item.id])
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "swift arch")
        ).items.map(\.id) == [item.id])
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "ether design")
        ).items.map(\.id) == [item.id])
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "program")
        ).items.map(\.id) == [item.id])
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "istanbul")
        ).items.map(\.id) == [item.id])

        try await fixture.repository.setFavorite(
            mediaID: item.id,
            workspaceID: item.workspaceID,
            value: false
        )
        try await fixture.repository.setCollectionMembership(MembershipCommand(
            workspaceID: item.workspaceID,
            mediaItemID: item.id,
            collectionID: collection.id,
            isMember: false
        ))
        #expect(try await fixture.repository.page(LibraryQuery(scope: .favorites)).totalCount == 0)
        #expect(try await fixture.repository.page(
            LibraryQuery(scope: .collection(collection.id))
        ).totalCount == 0)
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "program")
        ).totalCount == 0)
    }

    @Test func organizingFromInboxIsAtomicEvenWhenOneTargetIsInvalid() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try requireSaved(await fixture.repository.saveLink(SaveLinkCommand(
            sourceURL: try #require(URL(string: "https://example.com/inbox-item"))
        )))
        let collection = try await fixture.repository.createCollection(
            CreateCollectionCommand(name: "Research")
        )
        let missingCollection = CollectionID()

        await #expect(throws: LibraryDomainError.recordNotFound) {
            try await fixture.repository.organizeFromInbox(
                mediaID: item.id,
                workspaceID: item.workspaceID,
                collectionIDs: [collection.id, missingCollection]
            )
        }
        #expect(try await fixture.repository.page(LibraryQuery(scope: .inbox)).totalCount == 1)
        #expect(try await fixture.repository.page(
            LibraryQuery(scope: .collection(collection.id))
        ).totalCount == 0)

        try await fixture.repository.organizeFromInbox(
            mediaID: item.id,
            workspaceID: item.workspaceID,
            collectionIDs: [collection.id]
        )
        #expect(try await fixture.repository.page(LibraryQuery(scope: .inbox)).totalCount == 0)
        #expect(try await fixture.repository.page(
            LibraryQuery(scope: .collection(collection.id))
        ).items.map(\.id) == [item.id])
    }

    @Test func crossWorkspaceRelationshipsAreRejectedBeforeSQLiteCanAcceptThem() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try requireSaved(await fixture.repository.saveLink(SaveLinkCommand(
            sourceURL: try #require(URL(string: "https://example.com/personal"))
        )))
        let otherWorkspaceID = WorkspaceID()
        let otherCollectionID = CollectionID()
        let timestamp = fixture.now.sqliteMilliseconds
        try await fixture.database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO workspaces (
                        id, name, kind, revision, created_at, modified_at,
                        modified_by_device, deleted_at
                    ) VALUES (?, 'Other', 'shared', 1, ?, ?, ?, NULL)
                    """,
                arguments: [
                    otherWorkspaceID.description, timestamp, timestamp,
                    fixture.deviceID.description,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO collections (
                        id, workspace_id, name, kind, sort_order, revision,
                        created_at, modified_at, modified_by_device, deleted_at
                    ) VALUES (?, ?, 'Other Collection', 'user', 0, 1, ?, ?, ?, NULL)
                    """,
                arguments: [
                    otherCollectionID.description, otherWorkspaceID.description,
                    timestamp, timestamp, fixture.deviceID.description,
                ]
            )
        }

        await #expect(throws: LibraryDomainError.crossWorkspaceRelationship) {
            try await fixture.repository.setCollectionMembership(MembershipCommand(
                workspaceID: item.workspaceID,
                mediaItemID: item.id,
                collectionID: otherCollectionID,
                isMember: true
            ))
        }
        let membershipCount = try await fixture.database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM collection_memberships")
        }
        #expect(membershipCount == 1)
    }

    @Test func tombstonesHonorOptimisticRevisionAndDisappearFromEveryLiveQuery() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let item = try requireSaved(await fixture.repository.saveLink(SaveLinkCommand(
            sourceURL: try #require(URL(string: "https://example.com/delete-me"))
        )))

        await #expect(throws: LibraryDomainError.concurrentModification) {
            try await fixture.repository.tombstoneMedia(
                id: item.id,
                workspaceID: item.workspaceID,
                expectedRevision: 99
            )
        }
        try await fixture.repository.tombstoneMedia(
            id: item.id,
            workspaceID: item.workspaceID,
            expectedRevision: item.version.revision
        )
        #expect(try await fixture.repository.page(LibraryQuery()).totalCount == 0)
        #expect(try await fixture.repository.page(
            LibraryQuery(searchText: "delete")
        ).totalCount == 0)
        let stored = try fixture.database.pool.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT revision, deleted_at FROM media_items WHERE id = ?",
                arguments: [item.id.description]
            )
        }
        let revision: Int64? = stored?["revision"]
        let deletedAt: Int64? = stored?["deleted_at"]
        #expect(revision == 2)
        #expect(deletedAt != nil)
    }

    @Test func localChangesEnterEveryEnabledEndpointOutboxInTheSameTransaction() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let endpointID = UUID().uuidString.lowercased()
        let timestamp = fixture.now.sqliteMilliseconds
        try await fixture.database.pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_endpoints (
                        id, workspace_id, provider_kind, enabled, created_at, modified_at
                    ) VALUES (?, ?, 'cloudkit', 1, ?, ?)
                    """,
                arguments: [
                    endpointID, VidindirIdentity.personalWorkspace.description,
                    timestamp, timestamp,
                ]
            )
        }

        _ = try await fixture.repository.createCollection(
            CreateCollectionCommand(name: "Synced Collection")
        )
        let pendingCount = try await fixture.database.pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_outbox WHERE endpoint_id = ? AND state = 'pending'",
                arguments: [endpointID]
            )
        }
        #expect(pendingCount == 1)
    }
}
