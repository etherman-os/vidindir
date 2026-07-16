import Foundation

/// Adapter from the product-level download contract to the yt-dlp
/// implementation. No view or feature model needs to import yt-dlp event types.
public final class YTDLPBackend: DownloadBackend, @unchecked Sendable {
    private let locator: BinaryLocator
    private let service: YTDLPDownloadService

    public init(
        locator: BinaryLocator = BinaryLocator(),
        service: YTDLPDownloadService = YTDLPDownloadService()
    ) {
        self.locator = locator
        self.service = service
    }

    public var isDownloading: Bool {
        service.isDownloading
    }

    @discardableResult
    public func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        let tools = locator.locateAll()
        return try await service.download(request, tools: tools) { event in
            onEvent(Self.translate(event))
        }
    }

    public func cancelCurrentDownload() {
        service.cancelCurrentDownload()
    }

    private static func translate(_ event: DownloadServiceEvent) -> DownloadBackendEvent {
        switch event {
        case .started(let record):
            return .started(record)
        case .progress(let progress):
            return .progress(DownloadBackendProgress(
                fractionCompleted: progress.fractionCompleted,
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes ?? progress.estimatedTotalBytes,
                speedBytesPerSecond: progress.speedBytesPerSecond,
                etaSeconds: progress.etaSeconds,
                suggestedFilename: progress.filename
            ))
        case .plannedArtifact(let url):
            return .plannedArtifact(url)
        case .postProcessing:
            return .postProcessing
        case .log(let line):
            return .log(line)
        case .completed(let record):
            return .completed(record)
        case .failed(let message):
            return .failed(message)
        case .cancelled:
            return .cancelled
        }
    }
}

public final class HomebrewDownloadEngineManager: DownloadEngineManaging, @unchecked Sendable {
    private let locator: BinaryLocator
    private let installer: ToolInstallService

    public init(
        locator: BinaryLocator = BinaryLocator(),
        installer: ToolInstallService = ToolInstallService()
    ) {
        self.locator = locator
        self.installer = installer
    }

    public var canPrepareAutomatically: Bool {
        installer.isHomebrewAvailable
    }

    public var setupGuideURL: URL? {
        URL(string: "https://brew.sh/")
    }

    public func currentStatus() -> DownloadEngineStatus {
        let availability = locator.locateAll()
        return DownloadEngineStatus(
            isReady: availability.canDownload,
            missingComponents: availability.missingRequiredTools.map(\.displayName)
        )
    }

    public func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {
        let availability = locator.locateAll()
        guard !availability.canDownload else { return }
        _ = try await installer.installMissing(from: availability, onOutput: onOutput)

        guard locator.locateAll().canDownload else {
            throw ToolInstallServiceError.installationFailed(
                exitCode: 0,
                message: "Some engine components are still missing."
            )
        }
    }
}
