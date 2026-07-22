import Foundation
import VidindirDomain

struct DownloadRequestSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let format: String
    let quality: String
    let source: String

    init(request: DownloadRequest) {
        schemaVersion = Self.currentSchemaVersion
        format = request.format.rawValue
        quality = request.quality.rawValue
        source = "library_media_item"
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, format, quality, source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        format = try values.decode(String.self, forKey: .format)
        quality = try values.decode(String.self, forKey: .quality)
        source = try values.decode(String.self, forKey: .source)
    }

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DownloadRequestSnapshotError.invalidEncoding
        }
        return json
    }

    static func request(job: DownloadJob, sourceURL: URL) throws -> DownloadRequest {
        guard let data = job.requestJSON.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.schemaVersion == 0 || snapshot.schemaVersion == currentSchemaVersion,
              snapshot.source == "library_media_item",
              let format = DownloadFormat(rawValue: snapshot.format),
              let quality = DownloadQuality(rawValue: snapshot.quality) else {
            throw DownloadRequestSnapshotError.unsupportedSnapshot
        }

        let destination = resolveDestination(
            bookmark: job.destinationBookmark,
            fallbackPath: job.destinationPath
        )
        let request = DownloadRequest(
            sourceURL: sourceURL,
            format: format,
            quality: quality,
            destinationDirectory: destination
        )
        try request.validateForDownload()
        return request
    }

    static func bookmark(for url: URL) -> Data? {
        if let scoped = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
            return nil
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveDestination(bookmark: Data?, fallbackPath: String) -> URL {
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url.standardizedFileURL
            }
            stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url.standardizedFileURL
            }
        }
        return URL(fileURLWithPath: fallbackPath, isDirectory: true).standardizedFileURL
    }
}

enum DownloadRequestSnapshotError: LocalizedError, Equatable {
    case invalidEncoding
    case unsupportedSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The download request could not be recorded."
        case .unsupportedSnapshot:
            "This queued download was created by an unsupported request version."
        }
    }
}
