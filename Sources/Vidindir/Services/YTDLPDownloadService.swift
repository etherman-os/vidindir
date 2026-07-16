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
    private let fileManager: FileManager
    private let activeLock = NSLock()
    private var activeDownload: ActiveDownload?

    public init(
        commandBuilder: YTDLPCommandBuilder = YTDLPCommandBuilder(),
        artifactResolver: ArtifactResolver = ArtifactResolver(),
        fileManager: FileManager = .default
    ) {
        self.commandBuilder = commandBuilder
        self.artifactResolver = artifactResolver
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

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

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
        let active = ActiveDownload(process: process, state: state)

        guard claim(active) else {
            throw YTDLPDownloadServiceError.downloadAlreadyRunning
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let accessedSecurityScope = request.destinationDirectory
                    .startAccessingSecurityScopedResource()

                do {
                    try process.run()
                } catch {
                    release(active)
                    if accessedSecurityScope {
                        request.destinationDirectory.stopAccessingSecurityScopedResource()
                    }
                    continuation.resume(throwing: YTDLPDownloadServiceError.couldNotLaunch(
                        error.localizedDescription
                    ))
                    return
                }

                state.emit(.started(record))
                if state.wasCancelled {
                    process.terminate()
                }

                let group = DispatchGroup()
                let ioQueue = DispatchQueue(
                    label: "app.vidindir.downloader.io",
                    qos: .utility,
                    attributes: .concurrent
                )

                group.enter()
                ioQueue.async {
                    Self.read(
                        standardOutput.fileHandleForReading,
                        stream: .standardOutput,
                        into: state
                    )
                    group.leave()
                }

                group.enter()
                ioQueue.async {
                    Self.read(
                        standardError.fileHandleForReading,
                        stream: .standardError,
                        into: state
                    )
                    group.leave()
                }

                group.enter()
                ioQueue.async {
                    process.waitUntilExit()
                    group.leave()
                }

                group.notify(queue: state.eventQueue) { [self] in
                    self.release(active)
                    defer {
                        if accessedSecurityScope {
                            request.destinationDirectory.stopAccessingSecurityScopedResource()
                        }
                    }

                    if state.wasCancelled {
                        state.callEventHandler(.cancelled)
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    if let processingError = state.processingError {
                        let message = processingError.localizedDescription
                        state.callEventHandler(.failed(message))
                        continuation.resume(throwing: processingError)
                        return
                    }

                    guard process.terminationReason == .exit,
                          process.terminationStatus == 0 else {
                        let error = YTDLPDownloadServiceError.processFailed(
                            exitCode: process.terminationStatus,
                            message: state.failureSummary
                        )
                        state.callEventHandler(.failed(error.localizedDescription))
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let finalArtifact = state.finalArtifact else {
                        let error = YTDLPDownloadServiceError.missingFinalArtifact
                        state.callEventHandler(.failed(error.localizedDescription))
                        continuation.resume(throwing: error)
                        return
                    }

                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(
                        atPath: finalArtifact.path,
                        isDirectory: &isDirectory
                    ), !isDirectory.boolValue else {
                        let error = YTDLPDownloadServiceError.finalArtifactNotFound(finalArtifact)
                        state.callEventHandler(.failed(error.localizedDescription))
                        continuation.resume(throwing: error)
                        return
                    }

                    var completedRecord = record
                    completedRecord.status = .completed
                    completedRecord.outputFileURL = finalArtifact
                    completedRecord.finishedAt = Date()
                    state.callEventHandler(.completed(completedRecord))
                    continuation.resume(returning: completedRecord)
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(active)
        }
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
        active.state.markCancelled()
        if active.process.isRunning {
            active.process.terminate()
        }
    }

    private static func read(
        _ handle: FileHandle,
        stream: DownloadProcessState.Stream,
        into state: DownloadProcessState
    ) {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            state.consume(data, from: stream)
        }
        state.finish(stream: stream)
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
    let process: Process
    let state: DownloadProcessState

    init(process: Process, state: DownloadProcessState) {
        self.process = process
        self.state = state
    }
}

private final class DownloadProcessState: @unchecked Sendable {
    enum Stream {
        case standardOutput
        case standardError
    }

    let eventQueue = DispatchQueue(label: "app.vidindir.downloader.events")

    private let lock = NSLock()
    private var outputFramer = ByteLineFramer()
    private var errorFramer = ByteLineFramer()
    private let decoder = YTDLPEventDecoder()
    private let destinationDirectory: URL
    private let artifactResolver: ArtifactResolver
    private let eventHandler: YTDLPDownloadService.EventHandler
    private var recentLogs: [String] = []
    private var storedFinalArtifact: URL?
    private var storedProcessingError: Error?
    private var storedWasCancelled = false

    init(
        destinationDirectory: URL,
        artifactResolver: ArtifactResolver,
        eventHandler: @escaping YTDLPDownloadService.EventHandler
    ) {
        self.destinationDirectory = destinationDirectory
        self.artifactResolver = artifactResolver
        self.eventHandler = eventHandler
    }

    var failureSummary: String? {
        lock.withDownloadLock {
            let summary = recentLogs.suffix(4).joined(separator: " ")
            return summary.isEmpty ? nil : summary
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
        eventQueue.async { [eventHandler] in
            eventHandler(event)
        }
    }

    func callEventHandler(_ event: DownloadServiceEvent) {
        dispatchPrecondition(condition: .onQueue(eventQueue))
        eventHandler(event)
    }

    func markCancelled() {
        lock.withDownloadLock { storedWasCancelled = true }
    }

    func consume(_ data: Data, from stream: Stream) {
        let lines: [String]
        do {
            lines = try lock.withDownloadLock {
                switch stream {
                case .standardOutput:
                    return try outputFramer.append(data)
                case .standardError:
                    return try errorFramer.append(data)
                }
            }
        } catch {
            setProcessingError(error)
            return
        }

        for line in lines {
            process(line, from: stream)
        }
    }

    func finish(stream: Stream) {
        let lines: [String]
        do {
            lines = try lock.withDownloadLock {
                switch stream {
                case .standardOutput:
                    return try outputFramer.finish()
                case .standardError:
                    return try errorFramer.finish()
                }
            }
        } catch {
            setProcessingError(error)
            return
        }

        for line in lines {
            process(line, from: stream)
        }
    }

    private func process(_ line: String, from stream: Stream) {
        if stream == .standardError {
            appendLog(line)
            emit(.log(line))
            return
        }

        switch decoder.decode(line: line) {
        case .log(let message):
            appendLog(message)
            emit(.log(message))

        case .malformed(let payload):
            let message = "Could not parse downloader event: \(payload)"
            appendLog(message)
            emit(.log(message))

        case .event(.progress(let progress)):
            emit(.progress(progress))

        case .event(.postProcessing):
            emit(.postProcessing)

        case .event(.plannedArtifact(let path)):
            do {
                let url = try artifactResolver.resolve(
                    path: path,
                    inside: destinationDirectory
                )
                emit(.plannedArtifact(url))
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
            emit(.log("Ignoring unknown downloader event: \(name)"))
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
