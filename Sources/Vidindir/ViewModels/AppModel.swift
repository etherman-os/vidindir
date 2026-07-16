import AppKit
import Combine
import Foundation

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
    @Published private(set) var destinationDirectory: URL
    @Published private(set) var engineStatus: DownloadEngineStatus
    @Published private(set) var phase: DownloadPhase = .idle
    @Published private(set) var metrics: DownloadMetrics = .empty
    @Published private(set) var currentTitle = ""
    @Published private(set) var currentOutputURL: URL?
    @Published private(set) var history: [DownloadRecord]
    @Published private(set) var processLog = ""
    @Published private(set) var linkValidationMessage: String?
    @Published private(set) var isInstallingTools = false
    @Published private(set) var toolInstallStatus = "Checking required tools…"
    @Published var showsResponsibleUse: Bool
    @Published var alert: AppAlert?

    private let preferences: DownloadPreferencesStore
    private let downloadBackend: any DownloadBackend
    private let engineManager: any DownloadEngineManaging
    private let historyStore: DownloadHistoryStore
    private let defaults: UserDefaults
    private var downloadTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var activeRecord: DownloadRecord?
    private var didBootstrap = false

    private static let responsibleUseKey = "legal.responsibleUseAccepted"

    init(
        downloadBackend: any DownloadBackend,
        engineManager: any DownloadEngineManaging,
        preferences: DownloadPreferencesStore = DownloadPreferencesStore(),
        historyStore: DownloadHistoryStore = DownloadHistoryStore(),
        defaults: UserDefaults = .standard
    ) {
        self.downloadBackend = downloadBackend
        self.engineManager = engineManager
        self.preferences = preferences
        self.historyStore = historyStore
        self.defaults = defaults

        let format = preferences.selectedFormat
        selectedFormat = format
        destinationDirectory = preferences.destinationDirectory(for: format)
        engineStatus = engineManager.currentStatus()
        history = historyStore.load()
        showsResponsibleUse = !defaults.bool(forKey: Self.responsibleUseKey)
    }

    var canStartDownload: Bool {
        !phase.isBusy
            && !isInstallingTools
            && engineStatus.isReady
            && !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowToolSetup: Bool {
        isInstallingTools || !engineStatus.isReady
    }

    var canPrepareEngine: Bool {
        engineManager.canPrepareAutomatically
    }

    var missingToolsDescription: String {
        let names = engineStatus.missingComponents
        guard !names.isEmpty else { return "All required tools are ready." }
        let list = ListFormatter.localizedString(byJoining: names)
        return "Vidindir needs \(list) to download and convert media. The engine setup can prepare them for you."
    }

    var postProcessingLabel: String {
        selectedFormat == .mp3 ? "Converting audio to MP3…" : "Merging audio and video…"
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshEngineStatus()
    }

    func refreshEngineStatus() {
        engineStatus = engineManager.currentStatus()
    }

    func selectFormat(_ format: DownloadFormat) {
        guard !phase.isBusy, format != selectedFormat else { return }
        selectedFormat = format
        preferences.selectedFormat = format
        destinationDirectory = preferences.destinationDirectory(for: format)
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

    func startDownload() {
        guard !phase.isBusy else { return }
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

        phase = .preparing
        metrics = .empty
        currentTitle = request.sourceURL.host ?? "Media"
        currentOutputURL = nil
        processLog = ""
        linkValidationMessage = nil
        activeRecord = DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            title: currentTitle,
            status: .preparing
        )

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await downloadBackend.download(request) { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleDownloadEvent(event)
                    }
                }
            } catch is CancellationError {
                if self.phase.isBusy {
                    self.handleDownloadEvent(.cancelled)
                }
            } catch {
                if self.phase.isBusy {
                    self.finishFailure(error.localizedDescription)
                }
            }
            self.downloadTask = nil
        }
    }

    func cancelDownload() {
        guard phase.isBusy else { return }
        downloadBackend.cancelCurrentDownload()
        downloadTask?.cancel()
        phase = .cancelled
        finishActiveRecord(status: .cancelled)
    }

    func resetForNewDownload() {
        guard !phase.isBusy else { return }
        phase = .idle
        metrics = .empty
        currentTitle = ""
        currentOutputURL = nil
        processLog = ""
        linkText = ""
        activeRecord = nil
    }

    func revealCurrentDownload() {
        revealURL(currentOutputURL ?? destinationDirectory)
    }

    func reveal(_ record: DownloadRecord) {
        revealURL(record.outputFileURL ?? record.destinationDirectory)
    }

    func clearHistory() {
        history = []
        historyStore.clear()
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
        guard !isInstallingTools else { return }
        guard canPrepareEngine else {
            openEngineSetupGuide()
            return
        }

        isInstallingTools = true
        toolInstallStatus = "Homebrew is downloading the required packages…"
        processLog = ""
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await engineManager.prepare { [weak self] line in
                    Task { @MainActor [weak self] in
                        self?.appendLog(line)
                        self?.toolInstallStatus = Self.friendlyInstallStatus(for: line)
                    }
                }
                self.refreshEngineStatus()
                if self.engineStatus.isReady {
                    self.toolInstallStatus = "Tools are ready."
                } else {
                    throw DownloadEngineError.componentsStillMissing
                }
            } catch is CancellationError {
                self.toolInstallStatus = "Tool setup was cancelled."
            } catch {
                self.alert = AppAlert(
                    title: "Tool setup failed",
                    message: error.localizedDescription
                )
                self.toolInstallStatus = "Setup did not finish."
            }
            self.isInstallingTools = false
            self.installTask = nil
        }
    }

    func openEngineSetupGuide() {
        guard let url = engineManager.setupGuideURL else { return }
        NSWorkspace.shared.open(url)
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
        case .started(let record):
            activeRecord = record
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
            activeRecord?.title = currentTitle

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
            addToHistory(record)
            activeRecord = nil

        case .failed(let message):
            finishFailure(message)

        case .cancelled:
            if phase != .cancelled {
                phase = .cancelled
                finishActiveRecord(status: .cancelled)
            }
        }
    }

    private func finishFailure(_ rawMessage: String) {
        let message = friendlyDownloadError(rawMessage)
        phase = .failed(message)
        finishActiveRecord(status: .failed)
    }

    private func finishActiveRecord(status: DownloadStatus) {
        guard var record = activeRecord else { return }
        record.title = currentTitle
        record.status = status
        record.outputFileURL = currentOutputURL
        record.finishedAt = Date()
        addToHistory(record)
        activeRecord = nil
    }

    private func addToHistory(_ record: DownloadRecord) {
        history.removeAll { $0.id == record.id }
        history.insert(record, at: 0)
        history = Array(history.prefix(30))
        historyStore.save(history)
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
