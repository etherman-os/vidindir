import Foundation
import GRDB
import Testing
import VidindirDomain
@testable import VidindirPersistence

@Suite("Legacy UserDefaults history import")
struct LegacyHistoryImporterTests {
    @Test func importsValidEntriesSkipsBadOnesAndNeverInventsAFile() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let verifiedOutput = URL(fileURLWithPath: "/tmp/verified-video.mp4")
        let missingOutput = URL(fileURLWithPath: "/tmp/missing-video.mp4")
        let startedAt = fixture.now.addingTimeInterval(-120)
        let records = [
            LegacyHistoryRecord(
                id: UUID(),
                sourceURL: try #require(URL(
                    string: "https://youtube.com/shorts/OpeV9uFQcGg?si=legacy"
                )),
                format: "mp4",
                destinationDirectory: URL(fileURLWithPath: "/tmp"),
                outputFileURL: verifiedOutput,
                title: "Imported Short",
                status: "completed",
                startedAt: startedAt,
                finishedAt: fixture.now.addingTimeInterval(-60)
            ),
            LegacyHistoryRecord(
                id: UUID(),
                sourceURL: try #require(URL(
                    string: "https://www.youtube.com/watch?v=OpeV9uFQcGg&t=5"
                )),
                format: "mp4",
                destinationDirectory: URL(fileURLWithPath: "/tmp"),
                outputFileURL: missingOutput,
                title: "Same Video, Missing File",
                status: "completed",
                startedAt: startedAt,
                finishedAt: fixture.now.addingTimeInterval(-30)
            ),
            LegacyHistoryRecord(
                id: UUID(),
                sourceURL: try #require(URL(
                    string: "https://x.com/etherman/status/1234567890"
                )),
                format: "mp3",
                destinationDirectory: URL(fileURLWithPath: "/tmp"),
                outputFileURL: nil,
                title: "Interrupted Audio",
                status: "preparing",
                startedAt: startedAt,
                finishedAt: nil
            ),
            LegacyHistoryRecord(
                id: UUID(),
                sourceURL: try #require(URL(string: "ftp://example.com/not-supported")),
                format: "mp4",
                destinationDirectory: URL(fileURLWithPath: "/tmp"),
                outputFileURL: nil,
                title: nil,
                status: "failed",
                startedAt: startedAt,
                finishedAt: fixture.now
            ),
        ]
        let originalData = try legacyArrayData(records, addingMalformedEntry: true)
        let importer = LegacyHistoryImporter(
            database: fixture.database,
            now: { fixture.now },
            verifyLocalFile: { url in
                guard url.standardizedFileURL == verifiedOutput.standardizedFileURL else {
                    return nil
                }
                return LegacyVerifiedFile(
                    bookmark: Data("verified-bookmark".utf8),
                    path: url.path,
                    fileSizeBytes: 1_024
                )
            }
        )

        let result = try await importer.importHistoryData(originalData)
        #expect(result == LegacyHistoryImportResult(
            wasAlreadyImported: false,
            importedMediaItems: 2,
            reusedMediaItems: 1,
            importedJobs: 3,
            importedAssets: 1,
            skippedEntries: 2
        ))

        let jobs = try await fixture.downloadRepository.jobs(DownloadJobQuery())
        #expect(jobs.count == 3)
        #expect(jobs.filter { $0.state == .completed }.count == 1)
        #expect(jobs.filter { $0.state == .interrupted }.count == 2)
        #expect(jobs.first { $0.errorCategory == "legacy_file_missing" } != nil)
        #expect(jobs.first { $0.mediaKind == .audio }?.state == .interrupted)
        let outputPathWasRetained = jobs.contains { job in
            guard let data = job.requestJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let outputPath = object["outputPath"] as? String else {
                return false
            }
            return outputPath == "/tmp/missing-video.mp4"
        }
        #expect(outputPathWasRetained)

        let assetCount = try await fixture.database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_assets")
        }
        #expect(assetCount == 1)
        let library = try await fixture.repository.page(LibraryQuery())
        #expect(library.totalCount == 2)
        #expect(library.items.contains { $0.mediaItem.sourceType == .youtube })
        #expect(library.items.contains { $0.mediaItem.sourceType == .x })

        // The importer receives a copy and has no API that can delete the legacy value.
        let unchangedData = try legacyArrayData(records, addingMalformedEntry: true)
        #expect(originalData == unchangedData)
    }

    @Test func importMarkerMakesTheOperationIdempotentEvenWithDifferentInputLater() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let firstRecord = LegacyHistoryRecord(
            id: UUID(),
            sourceURL: try #require(URL(string: "https://example.com/first")),
            format: "mp4",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
            outputFileURL: nil,
            title: "First",
            status: "failed",
            startedAt: fixture.now,
            finishedAt: fixture.now
        )
        let secondRecord = LegacyHistoryRecord(
            id: UUID(),
            sourceURL: try #require(URL(string: "https://example.com/second")),
            format: "mp4",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
            outputFileURL: nil,
            title: "Second",
            status: "failed",
            startedAt: fixture.now,
            finishedAt: fixture.now
        )
        let importer = LegacyHistoryImporter(
            database: fixture.database,
            now: { fixture.now },
            verifyLocalFile: { _ in nil }
        )

        let first = try await importer.importHistoryData(legacyArrayData([firstRecord]))
        let second = try await importer.importHistoryData(legacyArrayData([secondRecord]))
        #expect(first.wasAlreadyImported == false)
        #expect(first.importedJobs == 1)
        #expect(second.wasAlreadyImported)
        #expect(second.importedJobs == first.importedJobs)
        #expect(try await fixture.repository.page(LibraryQuery()).items.map(
            \.mediaItem.title
        ) == ["First"])
        let markerCount = try await fixture.database.pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM migration_state WHERE key = ?",
                arguments: [LegacyHistoryImporter.migrationStateKey]
            )
        }
        #expect(markerCount == 1)
    }

    @Test func malformedTopLevelDataIsRecordedOnceWithoutDamagingTheDatabase() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let importer = LegacyHistoryImporter(
            database: fixture.database,
            now: { fixture.now },
            verifyLocalFile: { _ in nil }
        )

        let result = try await importer.importHistoryData(Data("not-json".utf8))
        #expect(result.skippedEntries == 1)
        #expect(result.importedJobs == 0)
        #expect(try await fixture.repository.page(LibraryQuery()).totalCount == 0)
        #expect(try await importer.importHistoryData(nil).wasAlreadyImported)
    }

    @Test func invalidVerifierEvidenceCannotCreateAnAvailableAsset() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let output = URL(fileURLWithPath: "/tmp/video.mp4")
        let record = LegacyHistoryRecord(
            id: UUID(),
            sourceURL: try #require(URL(string: "https://example.com/video")),
            format: "mp4",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
            outputFileURL: output,
            title: "Video",
            status: "completed",
            startedAt: fixture.now,
            finishedAt: fixture.now
        )
        let importer = LegacyHistoryImporter(
            database: fixture.database,
            now: { fixture.now },
            verifyLocalFile: { _ in
                LegacyVerifiedFile(
                    bookmark: Data(),
                    path: "/tmp/different.mp4",
                    fileSizeBytes: -1
                )
            }
        )

        let result = try await importer.importHistoryData(legacyArrayData([record]))
        #expect(result.importedAssets == 0)
        let jobs = try await fixture.downloadRepository.jobs(DownloadJobQuery())
        #expect(jobs.map(\.state) == [.interrupted])
        #expect(jobs.map(\.errorCategory) == ["legacy_file_missing"])
    }
}

private func legacyArrayData(
    _ records: [LegacyHistoryRecord],
    addingMalformedEntry: Bool = false
) throws -> Data {
    let encoder = JSONEncoder()
    var values = try records.map { record -> Any in
        let data = try encoder.encode(record)
        return try JSONSerialization.jsonObject(with: data)
    }
    if addingMalformedEntry {
        values.append(["id": "not-a-complete-record"])
    }
    return try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
}
