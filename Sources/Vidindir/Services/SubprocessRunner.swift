import Foundation

public enum SubprocessStream: Sendable {
    case standardOutput
    case standardError
}

public struct SubprocessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let terminationReason: Process.TerminationReason
    public let standardOutput: [String]
    public let standardError: [String]

    public init(
        exitCode: Int32,
        terminationReason: Process.TerminationReason,
        standardOutput: [String],
        standardError: [String]
    ) {
        self.exitCode = exitCode
        self.terminationReason = terminationReason
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public final class SubprocessRunner: @unchecked Sendable {
    public typealias LineHandler = @Sendable (SubprocessStream, String) -> Void

    public init() {}

    public func run(
        _ invocation: ProcessInvocation,
        onLine: @escaping LineHandler = { _, _ in }
    ) async throws -> SubprocessResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let state = SubprocessState(onLine: onLine)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: SubprocessRunnerError.couldNotLaunch(
                        error.localizedDescription
                    ))
                    return
                }

                if state.wasCancelled {
                    process.terminate()
                }

                let queue = DispatchQueue(
                    label: "app.vidindir.subprocess.io",
                    qos: .utility,
                    attributes: .concurrent
                )
                let group = DispatchGroup()

                group.enter()
                queue.async {
                    Self.read(outputPipe.fileHandleForReading, stream: .standardOutput, state: state)
                    group.leave()
                }

                group.enter()
                queue.async {
                    Self.read(errorPipe.fileHandleForReading, stream: .standardError, state: state)
                    group.leave()
                }

                group.enter()
                queue.async {
                    process.waitUntilExit()
                    group.leave()
                }

                group.notify(queue: state.callbackQueue) {
                    if state.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if let framingError = state.framingError {
                        continuation.resume(throwing: framingError)
                    } else {
                        continuation.resume(returning: SubprocessResult(
                            exitCode: process.terminationStatus,
                            terminationReason: process.terminationReason,
                            standardOutput: state.standardOutput,
                            standardError: state.standardError
                        ))
                    }
                }
            }
        } onCancel: {
            state.cancel()
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func read(
        _ handle: FileHandle,
        stream: SubprocessStream,
        state: SubprocessState
    ) {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            state.consume(data, stream: stream)
        }
        state.finish(stream: stream)
    }
}

public enum SubprocessRunnerError: LocalizedError, Equatable, Sendable {
    case couldNotLaunch(String)

    public var errorDescription: String? {
        switch self {
        case .couldNotLaunch(let message):
            return "The process could not start: \(message)"
        }
    }
}

private final class SubprocessState: @unchecked Sendable {
    let callbackQueue = DispatchQueue(label: "app.vidindir.subprocess.events")

    private let lock = NSLock()
    private let onLine: SubprocessRunner.LineHandler
    private var outputFramer = ByteLineFramer()
    private var errorFramer = ByteLineFramer()
    private var outputLines: [String] = []
    private var errorLines: [String] = []
    private var error: Error?
    private var cancelled = false

    init(onLine: @escaping SubprocessRunner.LineHandler) {
        self.onLine = onLine
    }

    var standardOutput: [String] {
        lock.withSubprocessLock { outputLines }
    }

    var standardError: [String] {
        lock.withSubprocessLock { errorLines }
    }

    var framingError: Error? {
        lock.withSubprocessLock { error }
    }

    var wasCancelled: Bool {
        lock.withSubprocessLock { cancelled }
    }

    func cancel() {
        lock.withSubprocessLock { cancelled = true }
    }

    func consume(_ data: Data, stream: SubprocessStream) {
        do {
            let lines = try lock.withSubprocessLock {
                switch stream {
                case .standardOutput: return try outputFramer.append(data)
                case .standardError: return try errorFramer.append(data)
                }
            }
            publish(lines, stream: stream)
        } catch {
            set(error: error)
        }
    }

    func finish(stream: SubprocessStream) {
        do {
            let lines = try lock.withSubprocessLock {
                switch stream {
                case .standardOutput: return try outputFramer.finish()
                case .standardError: return try errorFramer.finish()
                }
            }
            publish(lines, stream: stream)
        } catch {
            set(error: error)
        }
    }

    private func publish(_ lines: [String], stream: SubprocessStream) {
        guard !lines.isEmpty else { return }
        lock.withSubprocessLock {
            switch stream {
            case .standardOutput: outputLines.append(contentsOf: lines)
            case .standardError: errorLines.append(contentsOf: lines)
            }
        }
        for line in lines {
            callbackQueue.async { [onLine] in onLine(stream, line) }
        }
    }

    private func set(error newError: Error) {
        lock.withSubprocessLock {
            if error == nil { error = newError }
        }
    }
}

private extension NSLock {
    func withSubprocessLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
