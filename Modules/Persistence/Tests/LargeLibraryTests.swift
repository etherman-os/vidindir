import Foundation
import GRDB
import Testing
import VidindirDomain
@testable import VidindirPersistence

@Suite("Large local library")
struct LargeLibraryTests {
    @Test func tenThousandItemsRemainPaginatedAndSearchable() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let workspaceID = VidindirIdentity.personalWorkspace.description
        let deviceID = fixture.deviceID.description
        let baseTimestamp = fixture.now.sqliteMilliseconds

        try await fixture.database.pool.write { db in
            for index in 0..<10_000 {
                let id = MediaItemID().description
                let title: String
                if index == 9_999 {
                    title = "Needle9999 Architecture"
                } else if index == 42 {
                    title = "Future Provider FortyTwo"
                } else {
                    title = "Media Item \(index)"
                }
                try db.execute(
                    sql: """
                        INSERT INTO media_items (
                            id, workspace_id, source_url, canonical_url,
                            canonicalization_version, source_type, source_media_id,
                            title, metadata_status, revision, created_at, modified_at,
                            modified_by_device, deleted_at
                        ) VALUES (?, ?, ?, NULL, 1, ?, NULL, ?, 'resolved', 1, ?, ?, ?, NULL)
                        """,
                    arguments: [
                        id,
                        workspaceID,
                        "https://example.com/media/\(index)",
                        index == 42 ? "future_provider" : SourceType.generic.rawValue,
                        title,
                        baseTimestamp + Int64(index),
                        baseTimestamp + Int64(index),
                        deviceID,
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO media_search (
                            media_item_id, workspace_id, title, creator, source_url,
                            description, collection_names, tag_names
                        ) VALUES (?, ?, ?, '', ?, '', '', '')
                        """,
                    arguments: [
                        id, workspaceID, title, "https://example.com/media/\(index)",
                    ]
                )
            }
        }

        let page = try await fixture.repository.page(LibraryQuery(limit: 100, offset: 5_000))
        #expect(page.totalCount == 10_000)
        #expect(page.items.count == 100)

        let search = try await fixture.repository.page(LibraryQuery(
            searchText: "needle9999 arch",
            limit: 25
        ))
        #expect(search.totalCount == 1)
        #expect(search.items.first?.mediaItem.title == "Needle9999 Architecture")

        let futureValue = try await fixture.repository.page(LibraryQuery(
            searchText: "future provider fortytwo",
            limit: 25
        ))
        #expect(futureValue.items.first?.mediaItem.sourceType.rawValue == "future_provider")
    }
}
