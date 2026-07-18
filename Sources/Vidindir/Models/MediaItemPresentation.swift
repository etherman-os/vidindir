import Foundation
import VidindirDomain

extension MediaItem {
    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if metadataStatus == .unresolved || metadataStatus == .resolving {
            return "Fetching video details…"
        }
        return switch sourceType {
        case .youtube: "Untitled YouTube video"
        case .x: "Untitled X video"
        case .vimeo: "Untitled Vimeo video"
        default: "Untitled media"
        }
    }

    var sourceLabel: String {
        sourceType.displayName
    }
}

extension SourceType {
    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .x: "X"
        case .vimeo: "Vimeo"
        case .generic: "Web"
        default: rawValue.capitalized
        }
    }
}
