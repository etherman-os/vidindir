import Foundation
import VidindirDomain

enum LocalAssetVerifier {
    static func verify(_ url: URL) throws -> VerifiedLocalAsset {
        guard url.isFileURL,
              NSString(string: url.path).isAbsolutePath,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size >= 0,
              let bookmark = DownloadRequestSnapshot.bookmark(for: url),
              !bookmark.isEmpty else {
            throw LocalAssetVerificationError.missingOutputFile
        }
        return try VerifiedLocalAsset(
            fileBookmark: bookmark,
            absolutePath: url.standardizedFileURL.path,
            fileSizeBytes: Int64(size),
            contentType: nil,
            container: url.pathExtension.lowercased(),
            verifiedAt: Date()
        )
    }

    static func existingFileURL(for asset: LocalAsset) -> URL? {
        guard asset.status == .available else { return nil }

        var candidates: [URL] = []
        if let bookmark = asset.fileBookmark {
            var stale = false
            if let scoped = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                candidates.append(scoped)
            } else {
                stale = false
                if let unscoped = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    candidates.append(unscoped)
                }
            }
        }
        if NSString(string: asset.lastKnownPath).isAbsolutePath {
            candidates.append(URL(fileURLWithPath: asset.lastKnownPath))
        }

        return candidates.first { candidate in
            let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }?.standardizedFileURL
    }
}

enum LocalAssetVerificationError: LocalizedError, Equatable {
    case missingOutputFile

    var errorDescription: String? {
        "The downloaded file could not be verified on this Mac."
    }
}
