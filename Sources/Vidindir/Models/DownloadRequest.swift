import Foundation

public struct DownloadRequest: Equatable, Hashable, Sendable {
    public let sourceURL: URL
    public let format: DownloadFormat
    public let quality: DownloadQuality
    public let destinationDirectory: URL

    public init(
        sourceURL: URL,
        format: DownloadFormat,
        quality: DownloadQuality = .best,
        destinationDirectory: URL
    ) {
        self.sourceURL = sourceURL
        self.format = format
        self.quality = quality
        self.destinationDirectory = destinationDirectory.standardizedFileURL
    }

    public init(
        urlString: String,
        format: DownloadFormat,
        quality: DownloadQuality = .best,
        destinationDirectory: URL
    ) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw ValidationError.invalidURL
        }

        self.init(
            sourceURL: url,
            format: format,
            quality: quality,
            destinationDirectory: destinationDirectory
        )
    }

    /// A stricter validation intended for the paste field. The command builder
    /// still treats every URL as an opaque argument and places it after `--`.
    public func validateForDownload() throws {
        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              sourceURL.host != nil else {
            throw ValidationError.invalidURL
        }

        guard destinationDirectory.isFileURL else {
            throw ValidationError.invalidDestination
        }
    }

    public enum ValidationError: LocalizedError, Equatable {
        case invalidURL
        case invalidDestination

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Enter a valid HTTP or HTTPS link."
            case .invalidDestination:
                return "Choose a valid download folder."
            }
        }
    }
}

public enum DownloadQuality: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case best
    case p1080
    case p720

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .best: "Best"
        case .p1080: "1080p"
        case .p720: "720p"
        }
    }

    var maximumHeight: Int? {
        switch self {
        case .best: nil
        case .p1080: 1_080
        case .p720: 720
        }
    }
}
