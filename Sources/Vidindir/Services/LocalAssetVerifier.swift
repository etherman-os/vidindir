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
}

enum LocalAssetVerificationError: LocalizedError, Equatable {
    case missingOutputFile

    var errorDescription: String? {
        "The downloaded file could not be verified on this Mac."
    }
}
