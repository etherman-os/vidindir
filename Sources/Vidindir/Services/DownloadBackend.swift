import Foundation

/// Product-level progress that is independent of any extractor or CLI backend.
public struct DownloadBackendProgress: Equatable, Sendable {
    public let fractionCompleted: Double?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let speedBytesPerSecond: Double?
    public let etaSeconds: Double?
    public let suggestedFilename: String?

    public init(
        fractionCompleted: Double? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil,
        suggestedFilename: String? = nil
    ) {
        self.fractionCompleted = fractionCompleted
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.suggestedFilename = suggestedFilename
    }
}

/// Events consumed by app state. Backend-specific output must be translated
/// before it crosses this boundary.
public enum DownloadBackendEvent: Equatable, Sendable {
    case started(DownloadRecord)
    case progress(DownloadBackendProgress)
    case plannedArtifact(URL)
    case postProcessing
    case log(String)
    case completed(DownloadRecord)
    case failed(String)
    case cancelled
}

public protocol DownloadBackend: AnyObject, Sendable {
    typealias EventHandler = @Sendable (DownloadBackendEvent) -> Void

    var isDownloading: Bool { get }

    @discardableResult
    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord

    func cancelCurrentDownload()
}

public struct DownloadEngineStatus: Equatable, Sendable {
    public let isReady: Bool
    public let missingComponents: [String]

    public init(isReady: Bool, missingComponents: [String] = []) {
        self.isReady = isReady
        self.missingComponents = missingComponents
    }
}

/// Engine acquisition is separate from downloads and from the UI. The current
/// developer preview uses Homebrew; public releases can replace it with a
/// verified, rollback-capable engine-pack implementation.
public protocol DownloadEngineManaging: AnyObject, Sendable {
    var canPrepareAutomatically: Bool { get }
    var setupGuideURL: URL? { get }

    func currentStatus() -> DownloadEngineStatus
    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws
}

public enum DownloadEngineError: LocalizedError, Equatable, Sendable {
    case componentsStillMissing

    public var errorDescription: String? {
        switch self {
        case .componentsStillMissing:
            return "Some download engine components are still missing."
        }
    }
}
