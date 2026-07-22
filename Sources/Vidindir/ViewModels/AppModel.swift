import AppKit
import Combine
import Foundation
import VidindirDomain

struct EngineUpdateSchedule: Sendable {
    let interval: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static let hourly = EngineUpdateSchedule(interval: .seconds(3_600)) { duration in
        try await Task.sleep(for: duration)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var linkText = "" {
        didSet {
            if linkValidationMessage != nil {
                linkValidationMessage = nil
            }
        }
    }
    @Published private(set) var selectedFormat: DownloadFormat
    @Published private(set) var selectedQuality: DownloadQuality
    @Published private(set) var destinationDirectory: URL
    @Published private(set) var engineStatus: DownloadEngineStatus
    @Published private(set) var phase: DownloadPhase = .idle
    @Published private(set) var metrics: DownloadMetrics = .empty
    @Published private(set) var currentTitle = ""
    @Published private(set) var currentOutputURL: URL?
    @Published private(set) var processLog = ""
    @Published private(set) var linkValidationMessage: String?
    @Published private(set) var isInstallingTools = false
    @Published private(set) var toolInstallStatus = "Checking required tools…"
    @Published private(set) var isCheckingEngineUpdates = false
    @Published private(set) var engineUpdateResult: DownloadEngineUpdateResult?
    @Published private(set) var requiresManualEngineRepair = false
    @Published private(set) var isDownloadOperationActive = false
    @Published private(set) var isEnqueuingDownload = false
    @Published private(set) var hasPendingDownloads = false
    @Published private(set) var downloadActivityRevision: UInt64 = 0
    @Published var showsResponsibleUse: Bool
    @Published var alert: AppAlert?

    private let preferences: DownloadPreferencesStore
    private let downloadBackend: any DownloadBackend
    private let engineManager: any DownloadEngineManaging
    private let defaults: UserDefaults
    private let engineUpdateSchedule: EngineUpdateSchedule
    private let downloadCoordinator: DownloadCoordinator?
    private var downloadTask: Task<Void, Never>?
    private var enqueueTask: Task<Void, Never>?
    private var coordinatorEventsTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var installOperationID: UUID?
    private var engineUpdateTask: Task<Void, Never>?
    private var engineUpdateSchedulerTask: Task<Void, Never>?
    private var didBootstrap = false
    private var currentDownloadJobID: DownloadJobID?

    private static let responsibleUseKey = "legal.responsibleUseAccepted"

    init(
        downloadBackend: any DownloadBackend,
        engineManager: any DownloadEngineManaging,
        preferences: DownloadPreferencesStore = DownloadPreferencesStore(),
        defaults: UserDefaults = .standard,
        engineUpdateSchedule: EngineUpdateSchedule = .hourly,
        downloadCoordinator: DownloadCoordinator? = nil
    ) {
        self.downloadBackend = downloadBackend
        self.engineManager = engineManager
        self.preferences = preferences
        self.defaults = defaults
        self.engineUpdateSchedule = engineUpdateSchedule
        self.downloadCoordinator = downloadCoordinator

        let format = preferences.selectedFormat
        selectedFormat = format
        selectedQuality = preferences.quality(for: format)
        destinationDirectory = preferences.destinationDirectory(for: format)
        engineStatus = engineManager.currentStatus()
        showsResponsibleUse = !defaults.bool(forKey: Self.responsibleUseKey)
    }

    deinit {
        downloadTask?.cancel()
        enqueueTask?.cancel()
        coordinatorEventsTask?.cancel()
        installTask?.cancel()
        engineUpdateTask?.cancel()
        engineUpdateSchedulerTask?.cancel()
    }

    var canStartDownload: Bool {
        !isEnqueuingDownload
            && (downloadCoordinator != nil || !phase.isBusy)
            && !isInstallingTools
            && !isCheckingEngineUpdates
            && engineStatus.isReady
            && !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowToolSetup: Bool {
        isInstallingTools || !engineStatus.isReady
    }

    var canPrepareEngine: Bool {
        engineManager.canPrepareAutomatically
            && !phase.isBusy
            && !downloadBackend.isDownloading
            && !hasPendingDownloads
            && !isInstallingTools
            && !isCheckingEngineUpdates
    }

    var missingToolsDescription: String {
        let names = engineStatus.missingComponents
        guard !names.isEmpty else { return "All required tools are ready." }
        let list = ListFormatter.localizedString(byJoining: names)
        if requiresManualEngineRepair {
            return "\(list) still needs manual repair. Open the setup guide, repair the listed component, then refresh the engine status."
        }
        switch engineStatus.recoveryKind {
        case .assessInterruptedMutation:
            return "A previous engine change was interrupted. Vidindir must verify \(list) before downloads can continue."
        case .repairUnhealthyComponents:
            return "\(list) did not pass its health check. Vidindir can repair Homebrew-managed components without touching your downloads."
        case .installMissingComponents, nil:
            return "Vidindir needs \(list) to download and convert media. The engine setup can prepare them for you."
        }
    }

    var engineSetupTitle: String {
        if isInstallingTools { return "Preparing engine…" }
        switch engineStatus.recoveryKind {
        case .assessInterruptedMutation, .repairUnhealthyComponents:
            return "Engine repair"
        case .installMissingComponents, nil:
            return "One-time setup"
        }
    }

    var engineSetupActionLabel: String {
        guard canPrepareEngine else { return "Open Setup Guide" }
        if requiresManualEngineRepair { return "Recheck Engine" }
        switch engineStatus.recoveryKind {
        case .assessInterruptedMutation, .repairUnhealthyComponents:
            return "Repair Engine"
        case .installMissingComponents, nil:
            return "Prepare Engine"
        }
    }

    var engineUpdateMessage: String {
        if isCheckingEngineUpdates {
            return "Checking for download engine updates…"
        }
        return engineUpdateResult?.message ?? "Automatic engine updates are enabled."
    }

    var postProcessingLabel: String {
        selectedFormat == .mp3 ? "Converting audio to MP3…" : "Merging audio and video…"
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshEngineStatus()
        startDownloadCoordinator()
        startEngineUpdateScheduler()
    }

    func refreshEngineStatus() {
        engineStatus = engineManager.currentStatus()
        if engineStatus.isReady
            || engineStatus.recoveryKind != .repairUnhealthyComponents {
            requiresManualEngineRepair = false
        }
    }

    func selectFormat(_ format: DownloadFormat) {
        guard !phase.isBusy, format != selectedFormat else { return }
        selectedFormat = format
        preferences.selectedFormat = format
        selectedQuality = preferences.quality(for: format)
        destinationDirectory = preferences.destinationDirectory(for: format)
    }

    func selectQuality(_ quality: DownloadQuality) {
        guard !phase.isBusy, quality != selectedQuality else { return }
        selectedQuality = quality
        preferences.setQuality(quality, for: selectedFormat)
    }

    func pasteFromClipboard() {
        guard !phase.isBusy else { return }
        guard let string = NSPasteboard.general.string(forType: .string) else {
            alert = AppAlert(title: "Nothing to paste", message: "Copy a media link, then try again.")
            return
        }
        linkText = string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func chooseDestinationDirectory() {
        guard !phase.isBusy else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose a download folder"
        panel.prompt = "Choose"
        panel.message = "Vidindir will remember this folder for \(selectedFormat.displayName) downloads."
        panel.directoryURL = destinationDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let directory = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.setDestinationDirectory(directory)
            }
        }
    }

    func startDownload(mediaItemID: MediaItemID? = nil) {
        guard !isEnqueuingDownload,
              (downloadCoordinator != nil || !phase.isBusy),
              !isCheckingEngineUpdates else { return }
        guard engineStatus.isReady else {
            alert = AppAlert(
                title: "Tools are not ready",
                message: "Prepare the missing tools before starting a download."
            )
            return
        }

        let request: DownloadRequest
        do {
            request = try DownloadRequest(
                urlString: linkText,
                format: selectedFormat,
                quality: selectedQuality,
                destinationDirectory: destinationDirectory
            )
            try request.validateForDownload()
        } catch {
            linkValidationMessage = "Enter a valid http or https link."
            return
        }

        guard FileManager.default.isWritableFile(atPath: destinationDirectory.path) else {
            alert = AppAlert(
                title: "Folder is not writable",
                message: "Choose another download folder and try again."
            )
            return
        }

        _ = try? preferences.remember(
            format: selectedFormat,
            destinationDirectory: destinationDirectory
        )

        if let downloadCoordinator {
            enqueue(
                request,
                mediaItemID: mediaItemID,
                using: downloadCoordinator
            )
            return
        }

        isDownloadOperationActive = true
        phase = .preparing
        metrics = .empty
        currentTitle = request.sourceURL.host ?? "Media"
        currentOutputURL = nil
        processLog = ""
        linkValidationMessage = nil
        let backend = downloadBackend
        downloadTask = Task { [weak self, backend] in
            do {
                _ = try await backend.download(request) { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleDownloadEvent(event)
                    }
                }
            } catch is CancellationError {
                guard let self else { return }
                if self.phase.isBusy {
                    self.handleDownloadEvent(.cancelled)
                }
            } catch {
                guard let self else { return }
                if self.phase.isBusy {
                    self.finishFailure(error.localizedDescription)
                }
            }
            guard let self else { return }
            self.downloadTask = nil
            self.isDownloadOperationActive = false
        }
    }

    func cancelDownload() {
        guard phase.isBusy else { return }
        if let downloadCoordinator, let currentDownloadJobID {
            Task { await downloadCoordinator.cancel(currentDownloadJobID) }
            phase = .cancelled
            return
        }
        downloadBackend.cancelCurrentDownload()
        downloadTask?.cancel()
        phase = .cancelled
    }

    func retryDownload(_ id: DownloadJobID) {
        guard let downloadCoordinator else { return }
        Task { [weak self, downloadCoordinator] in
            do {
                _ = try await downloadCoordinator.retry(id)
            } catch {
                self?.alert = AppAlert(
                    title: "Could not retry the download",
                    message: error.localizedDescription
                )
            }
        }
    }

    func startDownloads(_ items: [LibraryItemSummary]) {
        guard !items.isEmpty,
              !isEnqueuingDownload,
              !isCheckingEngineUpdates else { return }
        guard engineStatus.isReady else {
            alert = AppAlert(
                title: "Tools are not ready",
                message: "Prepare the missing tools before queueing this collection."
            )
            return
        }
        guard let downloadCoordinator else {
            alert = AppAlert(
                title: "Download queue is unavailable",
                message: "The library database must be available to download a collection."
            )
            return
        }
        guard FileManager.default.isWritableFile(atPath: destinationDirectory.path) else {
            alert = AppAlert(
                title: "Folder is not writable",
                message: "Choose another download folder and try again."
            )
            return
        }

        _ = try? preferences.remember(
            format: selectedFormat,
            destinationDirectory: destinationDirectory
        )
        let entries = items.map { item in
            DownloadBatchEntry(
                request: DownloadRequest(
                    sourceURL: item.mediaItem.sourceURL,
                    format: selectedFormat,
                    quality: selectedQuality,
                    destinationDirectory: destinationDirectory
                ),
                mediaItemID: item.id
            )
        }

        isEnqueuingDownload = true
        enqueueTask = Task { [weak self, downloadCoordinator] in
            let result = await downloadCoordinator.enqueueBatch(entries)
            guard let self else { return }
            let queuedCount = result.queuedJobIDs.count
            let skippedCount = result.skippedMediaItemIDs.count
            let failedCount = result.failures.count
            if skippedCount > 0 || failedCount > 0 {
                var details = ["Queued \(queuedCount)", "already downloaded \(skippedCount)"]
                if failedCount > 0 {
                    details.append("could not queue \(failedCount)")
                }
                var message = details.joined(separator: "; ") + "."
                if let firstFailure = result.failures.first?.summary {
                    message += " \(firstFailure)"
                }
                self.alert = AppAlert(
                    title: queuedCount == 0
                        ? "No new downloads queued"
                        : "Collection queued",
                    message: message
                )
            }
            self.isEnqueuingDownload = false
            self.enqueueTask = nil
        }
    }

    func resetForNewDownload() {
        guard !phase.isBusy else { return }
        phase = .idle
        metrics = .empty
        currentTitle = ""
        currentOutputURL = nil
        processLog = ""
        linkText = ""
    }

    func revealCurrentDownload() {
        revealURL(currentOutputURL ?? destinationDirectory)
    }

    func copyProcessLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(processLog, forType: .string)
    }

    func acceptResponsibleUse() {
        defaults.set(true, forKey: Self.responsibleUseKey)
        showsResponsibleUse = false
    }

    func prepareEngine() {
        guard !phase.isBusy,
              !downloadBackend.isDownloading,
              !hasPendingDownloads,
              !isInstallingTools,
              !isCheckingEngineUpdates else { return }
        guard engineManager.canPrepareAutomatically else {
            openEngineSetupGuide()
            return
        }

        isInstallingTools = true
        toolInstallStatus = engineStatus.recoveryKind == .installMissingComponents
            ? "Homebrew is downloading the required packages…"
            : "Checking the download engine…"
        processLog = ""
        let operationID = UUID()
        installOperationID = operationID
        let manager = engineManager
        installTask = Task { [weak self, manager] in
            do {
                try await manager.prepare { [weak self] line in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.installOperationID == operationID,
                              self.isInstallingTools else { return }
                        self.appendLog(line)
                        self.toolInstallStatus = Self.friendlyInstallStatus(for: line)
                    }
                }
                guard let self,
                      self.installOperationID == operationID else { return }
                self.refreshEngineStatus()
                if self.engineStatus.isReady {
                    self.toolInstallStatus = "Tools are ready."
                } else {
                    throw DownloadEngineError.componentsStillMissing
                }
            } catch is CancellationError {
                guard let self,
                      self.installOperationID == operationID else { return }
                self.toolInstallStatus = "Tool setup was cancelled."
            } catch {
                guard let self,
                      self.installOperationID == operationID else { return }
                self.refreshEngineStatus()
                if let engineError = error as? DownloadEngineError {
                    switch engineError {
                    case .manualRepairRequired, .automaticRepairFailed:
                        self.requiresManualEngineRepair = true
                    case .componentsStillMissing, .operationInProgress:
                        break
                    }
                }
                self.alert = AppAlert(
                    title: "Tool setup failed",
                    message: error.localizedDescription
                )
                self.toolInstallStatus = "Setup did not finish."
            }
            guard let self,
                  self.installOperationID == operationID else { return }
            self.installOperationID = nil
            self.isInstallingTools = false
            self.installTask = nil
        }
    }

    /// Runs the same updater used by the background schedule, bypassing its
    /// daily cadence when explicitly requested by the user.
    func updateEngineNow() {
        checkForEngineUpdates(force: true)
    }

    func openEngineSetupGuide() {
        guard let url = engineManager.setupGuideURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func enqueue(
        _ request: DownloadRequest,
        mediaItemID: MediaItemID?,
        using coordinator: DownloadCoordinator
    ) {
        isEnqueuingDownload = true
        linkValidationMessage = nil
        enqueueTask = Task { [weak self, coordinator] in
            do {
                _ = try await coordinator.enqueue(
                    request,
                    mediaItemID: mediaItemID
                )
                guard let self else { return }
                self.linkText = ""
            } catch {
                guard let self else { return }
                self.alert = AppAlert(
                    title: "Could not queue the download",
                    message: error.localizedDescription
                )
            }
            guard let self else { return }
            self.isEnqueuingDownload = false
            self.enqueueTask = nil
        }
    }

    private func startDownloadCoordinator() {
        guard coordinatorEventsTask == nil,
              let downloadCoordinator else { return }
        coordinatorEventsTask = Task { @MainActor [weak self, downloadCoordinator] in
            let events = await downloadCoordinator.events()
            await downloadCoordinator.start()
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handleCoordinatorEvent(event)
            }
        }
    }

    private func handleCoordinatorEvent(_ event: DownloadCoordinatorEvent) {
        switch event {
        case .idle:
            hasPendingDownloads = false

        case .queued:
            hasPendingDownloads = true
            downloadActivityRevision &+= 1

        case .started(let jobID, let request):
            currentDownloadJobID = jobID
            hasPendingDownloads = true
            isDownloadOperationActive = true
            phase = .preparing
            metrics = .empty
            currentTitle = request.sourceURL.host ?? "Media"
            currentOutputURL = nil
            processLog = ""
            downloadActivityRevision &+= 1

        case .backend(let jobID, let backendEvent):
            guard currentDownloadJobID == jobID else { return }
            handleDownloadEvent(backendEvent)

        case .completed(let jobID, let record):
            guard currentDownloadJobID == jobID else { return }
            handleDownloadEvent(.completed(record))
            currentDownloadJobID = nil
            isDownloadOperationActive = false
            downloadActivityRevision &+= 1

        case .failed(let jobID, let message):
            guard currentDownloadJobID == jobID || currentDownloadJobID == nil else { return }
            finishFailure(message)
            if currentDownloadJobID == jobID {
                currentDownloadJobID = nil
                isDownloadOperationActive = false
            }
            downloadActivityRevision &+= 1

        case .cancelled(let jobID):
            if currentDownloadJobID == jobID {
                handleDownloadEvent(.cancelled)
                currentDownloadJobID = nil
                isDownloadOperationActive = false
            }
            downloadActivityRevision &+= 1

        case .queueUnavailable(let message):
            hasPendingDownloads = false
            alert = AppAlert(
                title: "Download queue is unavailable",
                message: message
            )
        }
    }

    private func startEngineUpdateScheduler() {
        guard engineUpdateSchedulerTask == nil else { return }
        let schedule = engineUpdateSchedule
        engineUpdateSchedulerTask = Task { @MainActor [weak self] in
            defer {
                self?.engineUpdateSchedulerTask = nil
            }
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.checkForEngineUpdates(force: false)

                do {
                    // The persistent policy performs real Homebrew work at
                    // most daily. Hourly wakeups also cover apps left open for
                    // several days and retry transient failures after six hours.
                    try await schedule.sleep(schedule.interval)
                } catch {
                    return
                }
            }
        }
    }

    private func checkForEngineUpdates(force: Bool) {
        guard engineUpdateTask == nil,
              !phase.isBusy,
              !downloadBackend.isDownloading,
              !hasPendingDownloads,
              !isInstallingTools else { return }

        isCheckingEngineUpdates = true
        let manager = engineManager
        engineUpdateTask = Task { [weak self, manager] in
            let result = await manager.checkForUpdates(force: force)
            guard !Task.isCancelled, let self else { return }

            self.engineUpdateResult = result
            // Readiness can change even when the high-level result is a
            // failure (for example, cancellation after a package mutation
            // leaves a persisted health check pending). Always re-read the
            // manager after a completed check.
            self.refreshEngineStatus()
            self.isCheckingEngineUpdates = false
            self.engineUpdateTask = nil
        }
    }

    private func setDestinationDirectory(_ directory: URL) {
        do {
            try preferences.setDestinationDirectory(directory, for: selectedFormat)
            destinationDirectory = directory.standardizedFileURL
        } catch {
            alert = AppAlert(title: "Could not remember this folder", message: error.localizedDescription)
        }
    }

    private func handleDownloadEvent(_ event: DownloadBackendEvent) {
        switch event {
        case .started:
            phase = .preparing

        case .progress(let progress):
            phase = .downloading
            metrics = DownloadMetrics(
                fractionCompleted: progress.fractionCompleted,
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes,
                speedBytesPerSecond: progress.speedBytesPerSecond,
                etaSeconds: progress.etaSeconds
            )
            if let filename = progress.suggestedFilename, !filename.isEmpty {
                currentTitle = URL(fileURLWithPath: filename)
                    .deletingPathExtension()
                    .lastPathComponent
            }

        case .plannedArtifact(let url):
            currentTitle = url.deletingPathExtension().lastPathComponent

        case .postProcessing:
            phase = .postProcessing
            metrics.fractionCompleted = nil

        case .log(let line):
            appendLog(line)
            if line.hasPrefix("[Merger]") || line.hasPrefix("[ExtractAudio]") || line.hasPrefix("[VideoRemuxer]") {
                phase = .postProcessing
                metrics.fractionCompleted = nil
            }

        case .completed(var record):
            record.title = currentTitle
            currentOutputURL = record.outputFileURL
            phase = .completed
            metrics.fractionCompleted = 1

        case .failed(let message):
            finishFailure(message)

        case .cancelled:
            if phase != .cancelled {
                phase = .cancelled
            }
        }
    }

    private func finishFailure(_ rawMessage: String) {
        let message = friendlyDownloadError(rawMessage)
        phase = .failed(message)
    }

    private func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        let combined = processLog.isEmpty ? line : processLog + "\n" + line
        processLog = String(combined.suffix(60_000))
    }

    private func revealURL(_ url: URL) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func friendlyDownloadError(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("unsupported url") {
            return "This link is not supported by the current yt-dlp version."
        }
        if lowercased.contains("private") || lowercased.contains("sign in") || lowercased.contains("login") {
            return "This content requires an account or is not publicly accessible."
        }
        if lowercased.contains("video unavailable") || lowercased.contains("not available") {
            return "This media is unavailable or restricted in your region."
        }
        if lowercased.contains("no space left") {
            return "There is not enough free disk space in the selected destination."
        }
        if lowercased.contains("failed to resolve") || lowercased.contains("network") {
            return "Vidindir could not reach the media service. Check your internet connection and try again."
        }
        return "The download could not be completed. Open Process Details for more information."
    }

    private static func friendlyInstallStatus(for line: String) -> String {
        if line.contains("Downloading") { return "Downloading packages…" }
        if line.contains("Installing") { return "Installing packages…" }
        if line.contains("Pouring") { return "Finishing installation…" }
        return "Homebrew is working…"
    }
}

extension AppModel: AppUpdateActivityProviding {
    var shouldDeferAppUpdateInstallation: Bool {
        isDownloadOperationActive
            || downloadBackend.isDownloading
            || isInstallingTools
            || isCheckingEngineUpdates
    }

    var appUpdateActivityChanges: AnyPublisher<Void, Never> {
        Publishers.CombineLatest3(
            $isDownloadOperationActive,
            $isInstallingTools,
            $isCheckingEngineUpdates
        )
        .map { downloadActive, engineInstallActive, engineUpdateActive in
            downloadActive || engineInstallActive || engineUpdateActive
        }
        .removeDuplicates()
        .map { _ in () }
        .eraseToAnyPublisher()
    }
}
