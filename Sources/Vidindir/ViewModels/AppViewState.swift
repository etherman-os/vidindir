import Foundation

enum DownloadPhase: Equatable {
    case idle
    case preparing
    case downloading
    case postProcessing
    case completed
    case failed(String)
    case cancelled

    var isBusy: Bool {
        switch self {
        case .preparing, .downloading, .postProcessing:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Inspecting the link…"
        case .downloading:
            return "Downloading"
        case .postProcessing:
            return "Preparing the file…"
        case .completed:
            return "Download complete"
        case .failed:
            return "Download failed"
        case .cancelled:
            return "Download cancelled"
        }
    }
}

struct DownloadMetrics: Equatable {
    var fractionCompleted: Double?
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speedBytesPerSecond: Double?
    var etaSeconds: Double?

    static let empty = DownloadMetrics()
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: AppAlert, rhs: AppAlert) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}
