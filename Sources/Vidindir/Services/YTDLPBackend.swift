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
    private let updater: HomebrewEngineUpdateService
    private let operationGate = EngineOperationGate()
    private let healthStore: HomebrewEngineHealthStore

    public init(
        locator: BinaryLocator = BinaryLocator(),
        installer: ToolInstallService = ToolInstallService(),
        updater: HomebrewEngineUpdateService? = nil
    ) {
        self.locator = locator
        self.installer = installer
        let resolvedUpdater = updater ?? HomebrewEngineUpdateService(
            homebrewURL: installer.homebrewExecutableURL,
            locator: locator
        )
        self.updater = resolvedUpdater
        self.healthStore = resolvedUpdater.healthStore
    }

    public var canPrepareAutomatically: Bool {
        installer.isHomebrewAvailable || healthStore.state().requiresAssessment
    }

    public var setupGuideURL: URL? {
        URL(string: "https://github.com/etherman-os/vidindir#troubleshooting-the-preview")
    }

    public func currentStatus() -> DownloadEngineStatus {
        let healthState = healthStore.state()
        switch healthState {
        case .mutationPending:
            return DownloadEngineStatus(
                isReady: false,
                missingComponents: ToolBinary.allCases.map(\.displayName),
                recoveryKind: .assessInterruptedMutation
            )
        case .unhealthy(let components):
            return DownloadEngineStatus(
                isReady: false,
                missingComponents: components.map(\.displayName),
                recoveryKind: .repairUnhealthyComponents
            )
        case .ready:
            break
        }

        let availability = locator.locateAll()
        return DownloadEngineStatus(
            isReady: availability.canDownload,
            missingComponents: availability.missingRequiredTools.map(\.displayName)
        )
    }

    public func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard await operationGate.begin() else {
            throw DownloadEngineError.operationInProgress
        }

        do {
            try await updater.prepareEngine(
                using: installer,
                onOutput: onOutput
            )
            await operationGate.end()
        } catch {
            await operationGate.end()
            throw error
        }
    }

    public func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        guard await operationGate.begin() else { return .busy }
        let result = await updater.checkForUpdates(force: force)
        await operationGate.end()
        return result
    }
}

private actor EngineOperationGate {
    private var isRunning = false

    func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    func end() {
        isRunning = false
    }
}
