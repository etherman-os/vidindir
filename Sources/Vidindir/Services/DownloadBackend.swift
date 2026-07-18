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

public enum DownloadEngineRecoveryKind: Equatable, Sendable {
    case installMissingComponents
    case assessInterruptedMutation
    case repairUnhealthyComponents
}

public struct DownloadEngineStatus: Equatable, Sendable {
    public let isReady: Bool
    public let missingComponents: [String]
    public let recoveryKind: DownloadEngineRecoveryKind?

    public init(
        isReady: Bool,
        missingComponents: [String] = [],
        recoveryKind: DownloadEngineRecoveryKind? = nil
    ) {
        self.isReady = isReady
        self.missingComponents = missingComponents
        self.recoveryKind = isReady
            ? nil
            : (recoveryKind ?? .installMissingComponents)
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
    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult
}

/// A user-facing, backend-neutral result for an engine update check. Raw
/// Homebrew output and failures deliberately stay behind the engine boundary.
public enum DownloadEngineUpdateResult: Equatable, Sendable {
    case skipped(nextCheck: Date)
    case recovered(checkedAt: Date)
    case upToDate(checkedAt: Date)
    case updated(components: [ToolBinary], checkedAt: Date)
    case partiallyManaged(
        managedComponents: [ToolBinary],
        updatedComponents: [ToolBinary],
        checkedAt: Date
    )
    case updatesBlocked(components: [ToolBinary], checkedAt: Date)
    case updatedWithBlockedComponents(
        updatedComponents: [ToolBinary],
        blockedComponents: [ToolBinary],
        checkedAt: Date
    )
    case partiallyManagedWithBlockedUpdates(
        managedComponents: [ToolBinary],
        updatedComponents: [ToolBinary],
        blockedComponents: [ToolBinary],
        checkedAt: Date
    )
    case notManaged(checkedAt: Date)
    case unavailable(retryAfter: Date)
    case unhealthy(components: [ToolBinary], retryAfter: Date)
    case busy
    case failed(retryAfter: Date)

    public var message: String {
        switch self {
        case .skipped:
            return "Automatic engine updates are scheduled."
        case .recovered:
            return "The download engine passed its health check and is ready."
        case .upToDate:
            return "The download engine is up to date."
        case .updated(let components, _):
            let names = components.map(\.displayName)
            let list = ListFormatter.localizedString(byJoining: names)
            return "Updated \(list)."
        case .partiallyManaged(let managedComponents, let updatedComponents, _):
            let managed = ListFormatter.localizedString(
                byJoining: managedComponents.map(\.displayName)
            )
            if updatedComponents.isEmpty {
                return "Homebrew-managed components (\(managed)) are up to date. Other engine tools must be updated separately."
            }
            let updated = ListFormatter.localizedString(
                byJoining: updatedComponents.map(\.displayName)
            )
            return "Updated \(updated). Other engine tools are not managed by Homebrew."
        case .updatesBlocked(let components, _):
            let names = ListFormatter.localizedString(
                byJoining: components.map(\.displayName)
            )
            return "Updates are available for \(names), but the Homebrew formula is pinned."
        case .updatedWithBlockedComponents(let updatedComponents, let blockedComponents, _):
            let updated = ListFormatter.localizedString(
                byJoining: updatedComponents.map(\.displayName)
            )
            let blocked = ListFormatter.localizedString(
                byJoining: blockedComponents.map(\.displayName)
            )
            return "Updated \(updated). \(blocked) remains pinned in Homebrew."
        case .partiallyManagedWithBlockedUpdates(
            let managedComponents,
            let updatedComponents,
            let blockedComponents,
            _
        ):
            let managed = ListFormatter.localizedString(
                byJoining: managedComponents.map(\.displayName)
            )
            let blocked = ListFormatter.localizedString(
                byJoining: blockedComponents.map(\.displayName)
            )
            if updatedComponents.isEmpty {
                return "Homebrew manages \(managed), but \(blocked) remains pinned. Other engine tools must be updated separately."
            }
            let updated = ListFormatter.localizedString(
                byJoining: updatedComponents.map(\.displayName)
            )
            return "Updated \(updated); \(blocked) remains pinned. Other engine tools are not managed by Homebrew."
        case .notManaged:
            return "The installed download tools are not managed by Homebrew."
        case .unavailable:
            return "Automatic engine updates need Homebrew in this developer preview."
        case .unhealthy(let components, _):
            let names = ListFormatter.localizedString(
                byJoining: components.map(\.displayName)
            )
            return "The engine update did not pass its health check (\(names)). Downloads are disabled until the engine is repaired."
        case .busy:
            return "Another download engine operation is already running."
        case .failed:
            return "Vidindir could not check for engine updates. It will try again later."
        }
    }
}

public enum DownloadEngineError: LocalizedError, Equatable, Sendable {
    case componentsStillMissing
    case operationInProgress
    case manualRepairRequired(components: [String])
    case automaticRepairFailed(components: [String])

    public var errorDescription: String? {
        switch self {
        case .componentsStillMissing:
            return "Some download engine components are still missing."
        case .operationInProgress:
            return "Another download engine operation is already running."
        case .manualRepairRequired(let components):
            let names = ListFormatter.localizedString(byJoining: components)
            return "Vidindir cannot repair \(names) automatically because it is not managed by Homebrew. Reinstall it using the setup guide, then try again."
        case .automaticRepairFailed(let components):
            let names = ListFormatter.localizedString(byJoining: components)
            return "Homebrew could not repair \(names). Open the setup guide, repair the listed component, then try again."
        }
    }
}
