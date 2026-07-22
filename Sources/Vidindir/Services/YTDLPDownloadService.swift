import Foundation

public enum DownloadServiceEvent: Equatable, Sendable {
    case started(DownloadRecord)
    case progress(YTDLPProgress)
    case plannedArtifact(URL)
    case postProcessing
    case log(String)
    case completed(DownloadRecord)
    case failed(String)
    case cancelled
}

public final class YTDLPDownloadService: @unchecked Sendable {
    public typealias EventHandler = @Sendable (DownloadServiceEvent) -> Void

    private let commandBuilder: YTDLPCommandBuilder
    private let artifactResolver: ArtifactResolver
    private let processRunner: any ProcessRunning
    private let fileManager: FileManager
    private let activeLock = NSLock()
    private var activeDownload: ActiveDownload?

    public init(
        commandBuilder: YTDLPCommandBuilder = YTDLPCommandBuilder(),
        artifactResolver: ArtifactResolver = ArtifactResolver(),
        processRunner: any ProcessRunning = SubprocessRunner(),
        fileManager: FileManager = .default
    ) {
        self.commandBuilder = commandBuilder
        self.artifactResolver = artifactResolver
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public var isDownloading: Bool {
        activeLock.withDownloadLock { activeDownload != nil }
    }

    @discardableResult
    public func download(
        _ request: DownloadRequest,
        tools: ToolAvailability,
        onEvent: @escaping EventHandler = { _ in }
    ) async throws -> DownloadRecord {
        try Task.checkCancellation()
        try request.validateForDownload()
        let invocation = try commandBuilder.build(request, tools: tools)

        let record = DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            status: .preparing
        )
        let state = DownloadProcessState(
            destinationDirectory: request.destinationDirectory,
            artifactResolver: artifactResolver,
            eventHandler: onEvent
        )
        let active = ActiveDownload(state: state)

        guard claim(active) else {
            throw YTDLPDownloadServiceError.downloadAlreadyRunning
        }

        let accessedSecurityScope = request.destinationDirectory
            .startAccessingSecurityScopedResource()
        defer {
            release(active)
            if accessedSecurityScope {
                request.destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        state.emit(.started(record))
        let runnerTask = Task { [processRunner] in
            try await processRunner.run(invocation, timeout: nil) { stream, line in
                state.consume(line, from: stream)
            }
        }
        active.attach(runnerTask)

        let result: SubprocessResult
        do {
            result = try await withTaskCancellationHandler {
                try await runnerTask.value
            } onCancel: {
                active.cancel()
            }
        } catch is CancellationError {
            state.finish(with: .cancelled)
            throw CancellationError()
        } catch {
            let downloadError = Self.mapRunnerError(error)
            state.finish(with: .failed(downloadError.localizedDescription))
            throw downloadError
        }

        // Callback delivery is intentionally not a runner completion barrier.
        // Re-read the bounded captured stdout synchronously so a very fast
        // process cannot finish before its final artifact event is observed.
        state.reconcile(outputLines: result.standardOutput)

        if state.wasCancelled {
            state.finish(with: .cancelled)
            throw CancellationError()
        }

        if let processingError = state.processingError {
            let message = DiagnosticRedactor().redact(processingError.localizedDescription)
            state.finish(with: .failed(message))
            throw processingError
        }

        guard result.terminationReason == .exit, result.exitCode == 0 else {
            let error = YTDLPDownloadServiceError.processFailed(
                exitCode: result.exitCode,
                message: state.failureSummary(capturedStandardError: result.standardError)
            )
            state.finish(with: .failed(error.localizedDescription))
            throw error
        }

        guard let finalArtifact = state.finalArtifact else {
            let error = YTDLPDownloadServiceError.missingFinalArtifact
            state.finish(with: .failed(error.localizedDescription))
            throw error
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: finalArtifact.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            let error = YTDLPDownloadServiceError.finalArtifactNotFound(finalArtifact)
            state.finish(with: .failed(error.localizedDescription))
            throw error
        }

        var completedRecord = record
        completedRecord.status = .completed
        completedRecord.outputFileURL = finalArtifact
        completedRecord.finishedAt = Date()
        state.finish(with: .completed(completedRecord))
        return completedRecord
    }

    private static func mapRunnerError(_ error: Error) -> Error {
        if case SubprocessRunnerError.couldNotLaunch(let message) = error {
            return YTDLPDownloadServiceError.couldNotLaunch(message)
        }
        return error
    }

    public func cancelCurrentDownload() {
        let active = activeLock.withDownloadLock { activeDownload }
        guard let active else { return }
        cancel(active)
    }

    private func claim(_ active: ActiveDownload) -> Bool {
        activeLock.withDownloadLock {
            guard activeDownload == nil else { return false }
            activeDownload = active
            return true
        }
    }

    private func release(_ active: ActiveDownload) {
        activeLock.withDownloadLock {
            if activeDownload === active {
                activeDownload = nil
            }
        }
    }

    private func cancel(_ active: ActiveDownload) {
        active.cancel()
    }
}

public enum YTDLPDownloadServiceError: LocalizedError, Equatable, Sendable {
    case downloadAlreadyRunning
    case couldNotLaunch(String)
    case processFailed(exitCode: Int32, message: String?)
    case missingFinalArtifact
    case finalArtifactNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .downloadAlreadyRunning:
            return "Another download is already running."
        case .couldNotLaunch(let message):
            return "The downloader could not start: \(message)"
        case .processFailed(let exitCode, let message):
            let detail = message.map { " \($0)" } ?? ""
            return "The download failed (exit code \(exitCode)).\(detail)"
        case .missingFinalArtifact:
            return "The downloader finished without reporting the saved file."
        case .finalArtifactNotFound(let url):
            return "The downloader reported a file that does not exist: \(url.lastPathComponent)"
        }
    }
}

private final class ActiveDownload: @unchecked Sendable {
    let state: DownloadProcessState
    private let lock = NSLock()
    private var task: Task<SubprocessResult, Error>?
    private var wasCancelled = false

    init(state: DownloadProcessState) {
        self.state = state
    }

    func attach(_ task: Task<SubprocessResult, Error>) {
        let shouldCancel = lock.withDownloadLock {
            self.task = task
            return wasCancelled
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        state.markCancelled()
        let task = lock.withDownloadLock {
            wasCancelled = true
            return self.task
        }
        task?.cancel()
    }
}

private final class DownloadProcessState: @unchecked Sendable {
    private let eventQueue = DispatchQueue(label: "app.vidindir.downloader.events")

    private let lock = NSLock()
    private let decoder = YTDLPEventDecoder()
    private let redactor = DiagnosticRedactor()
    private let destinationDirectory: URL
    private let artifactResolver: ArtifactResolver
    private let eventHandler: YTDLPDownloadService.EventHandler
    private var recentLogs: [String] = []
    private var storedFinalArtifact: URL?
    private var storedProcessingError: Error?
    private var storedWasCancelled = false
    private var storedFinished = false

    init(
        destinationDirectory: URL,
        artifactResolver: ArtifactResolver,
        eventHandler: @escaping YTDLPDownloadService.EventHandler
    ) {
        self.destinationDirectory = destinationDirectory
        self.artifactResolver = artifactResolver
        self.eventHandler = eventHandler
    }

    func failureSummary(capturedStandardError: [String]) -> String? {
        let captured = capturedStandardError
            .suffix(4)
            .map { redactor.redact($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !captured.isEmpty { return captured }

        return lock.withDownloadLock {
            let recent = recentLogs.suffix(4).joined(separator: " ")
            return recent.isEmpty ? nil : recent
        }
    }

    var finalArtifact: URL? {
        lock.withDownloadLock { storedFinalArtifact }
    }

    var processingError: Error? {
        lock.withDownloadLock { storedProcessingError }
    }

    var wasCancelled: Bool {
        lock.withDownloadLock { storedWasCancelled }
    }

    func emit(_ event: DownloadServiceEvent) {
        lock.withDownloadLock {
            guard !storedFinished else { return }
            eventQueue.async { [eventHandler] in
                eventHandler(event)
            }
        }
    }

    func finish(with event: DownloadServiceEvent) {
        let shouldFinish = lock.withDownloadLock {
            guard !storedFinished else { return false }
            storedFinished = true
            return true
        }
        if shouldFinish {
            eventQueue.sync { [eventHandler] in
                eventHandler(event)
            }
        }
    }

    func markCancelled() {
        lock.withDownloadLock { storedWasCancelled = true }
    }

    func consume(_ line: String, from stream: SubprocessStream) {
        process(line, from: stream, emitsEvents: true)
    }

    func reconcile(outputLines: [String]) {
        for line in outputLines {
            process(line, from: .standardOutput, emitsEvents: false)
        }
    }

    private func process(
        _ line: String,
        from stream: SubprocessStream,
        emitsEvents: Bool
    ) {
        if stream == .standardError {
            let safeLine = redactor.redact(line)
            appendLog(safeLine)
            if emitsEvents { emit(.log(safeLine)) }
            return
        }

        switch decoder.decode(line: line) {
        case .log(let message):
            let safeMessage = redactor.redact(message)
            appendLog(safeMessage)
            if emitsEvents { emit(.log(safeMessage)) }

        case .malformed(let payload):
            let message = redactor.redact("Could not parse downloader event: \(payload)")
            appendLog(message)
            if emitsEvents { emit(.log(message)) }

        case .event(.progress(let progress)):
            if emitsEvents { emit(.progress(progress)) }

        case .event(.postProcessing):
            if emitsEvents { emit(.postProcessing) }

        case .event(.plannedArtifact(let path)):
            do {
                let url = try artifactResolver.resolve(
                    path: path,
                    inside: destinationDirectory
                )
                if emitsEvents { emit(.plannedArtifact(url)) }
            } catch {
                setProcessingError(error)
            }

        case .event(.artifact(let path)):
            do {
                let url = try artifactResolver.resolve(
                    path: path,
                    inside: destinationDirectory
                )
                lock.withDownloadLock { storedFinalArtifact = url }
            } catch {
                setProcessingError(error)
            }

        case .event(.unknown(let name, _)):
            if emitsEvents {
                emit(.log(redactor.redact("Ignoring unknown downloader event: \(name)")))
            }
        }
    }

    private func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        lock.withDownloadLock {
            recentLogs.append(line)
            if recentLogs.count > 50 {
                recentLogs.removeFirst(recentLogs.count - 50)
            }
        }
    }

    private func setProcessingError(_ error: Error) {
        lock.withDownloadLock {
            if storedProcessingError == nil { storedProcessingError = error }
        }
    }
}

private extension NSLock {
    func withDownloadLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
