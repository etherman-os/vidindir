import Darwin
import Foundation

public enum SubprocessStream: Sendable {
    case standardOutput
    case standardError
}

public struct SubprocessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let terminationReason: Process.TerminationReason
    /// The newest complete stdout lines retained by `SubprocessRunner`'s
    /// configured per-stream line-count and UTF-8 byte limits.
    public let standardOutput: [String]
    /// The newest complete stderr lines retained by `SubprocessRunner`'s
    /// configured per-stream line-count and UTF-8 byte limits.
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

public protocol ProcessRunning: Sendable {
    func run(
        _ invocation: ProcessInvocation,
        timeout: Duration?,
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void
    ) async throws -> SubprocessResult
}

public final class SubprocessRunner: ProcessRunning, @unchecked Sendable {
    public typealias LineHandler = @Sendable (SubprocessStream, String) -> Void

    public static let defaultMaximumCapturedLineCountPerStream = 4_096
    public static let defaultMaximumCapturedUTF8BytesPerStream = 4 * 1_024 * 1_024
    public static let defaultMaximumPendingLineCallbackCount = 512
    public static let defaultMaximumPendingLineCallbackUTF8Bytes = 4 * 1_024 * 1_024

    private let timeoutTerminationGracePeriod: Duration
    private let maximumCapturedLineCountPerStream: Int
    private let maximumCapturedUTF8BytesPerStream: Int
    private let maximumPendingLineCallbackCount: Int
    private let maximumPendingLineCallbackUTF8Bytes: Int

    /// Creates a runner with deterministic capture limits for each output
    /// stream. The arrays returned in `SubprocessResult` are truncated to their
    /// newest complete lines. Callback delivery has separate count and byte
    /// bounds: a callback that cannot keep up receives a recent suffix instead
    /// of causing an unbounded queue of closures. Result delivery never waits
    /// for callback execution.
    public init(
        timeoutTerminationGracePeriod: Duration = .seconds(2),
        maximumCapturedLineCountPerStream: Int = SubprocessRunner.defaultMaximumCapturedLineCountPerStream,
        maximumCapturedUTF8BytesPerStream: Int = SubprocessRunner.defaultMaximumCapturedUTF8BytesPerStream,
        maximumPendingLineCallbackCount: Int = SubprocessRunner.defaultMaximumPendingLineCallbackCount,
        maximumPendingLineCallbackUTF8Bytes: Int = SubprocessRunner.defaultMaximumPendingLineCallbackUTF8Bytes
    ) {
        precondition(maximumCapturedLineCountPerStream > 0)
        precondition(maximumCapturedUTF8BytesPerStream > 0)
        precondition(maximumPendingLineCallbackCount > 0)
        precondition(maximumPendingLineCallbackUTF8Bytes > 0)
        self.timeoutTerminationGracePeriod = timeoutTerminationGracePeriod
        self.maximumCapturedLineCountPerStream = maximumCapturedLineCountPerStream
        self.maximumCapturedUTF8BytesPerStream = maximumCapturedUTF8BytesPerStream
        self.maximumPendingLineCallbackCount = maximumPendingLineCallbackCount
        self.maximumPendingLineCallbackUTF8Bytes = maximumPendingLineCallbackUTF8Bytes
    }

    public func run(
        _ invocation: ProcessInvocation,
        timeout: Duration? = nil,
        onLine: @escaping LineHandler = { _, _ in }
    ) async throws -> SubprocessResult {
        guard let timeout else {
            return try await runUntilExit(invocation, onLine: onLine)
        }

        return try await withThrowingTaskGroup(of: SubprocessResult.self) { group in
            group.addTask { [self] in
                try await runUntilExit(invocation, onLine: onLine)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                try Task.checkCancellation()
                throw SubprocessRunnerError.timedOut
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            return first
        }
    }

    private func runUntilExit(
        _ invocation: ProcessInvocation,
        onLine: @escaping LineHandler
    ) async throws -> SubprocessResult {
        try Task.checkCancellation()

        let state = SubprocessState(
            maximumCapturedLineCountPerStream: maximumCapturedLineCountPerStream,
            maximumCapturedUTF8BytesPerStream: maximumCapturedUTF8BytesPerStream,
            maximumPendingLineCallbackCount: maximumPendingLineCallbackCount,
            maximumPendingLineCallbackUTF8Bytes: maximumPendingLineCallbackUTF8Bytes,
            onLine: onLine
        )
        let terminationController = SubprocessTerminationController(
            gracePeriod: timeoutTerminationGracePeriod
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let subprocess: SpawnedSubprocess
                do {
                    subprocess = try Self.spawn(invocation)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                terminationController.processDidLaunch(processGroupID: subprocess.processIdentifier)

                let ioQueue = DispatchQueue(
                    label: "app.vidindir.subprocess.io",
                    qos: .utility,
                    attributes: .concurrent
                )
                let ioGroup = DispatchGroup()

                ioGroup.enter()
                ioQueue.async {
                    Self.read(
                        subprocess.standardOutput,
                        stream: .standardOutput,
                        state: state
                    )
                    ioGroup.leave()
                }

                ioGroup.enter()
                ioQueue.async {
                    Self.read(
                        subprocess.standardError,
                        stream: .standardError,
                        state: state
                    )
                    ioGroup.leave()
                }

                // Supervise the leader independently of pipe EOF. A descendant
                // can call setsid(2), escape the original process group, and
                // retain inherited output descriptors forever. Cancellation
                // asks each nonblocking reader to close its own descriptor, so
                // that escaped process cannot hold result delivery hostage.
                //
                // waitid(WNOWAIT) deliberately leaves the exited leader as a
                // zombie. Its PID (and therefore the original PGID) cannot be
                // reused while the TERM -> KILL escalation is being sealed.
                let supervisionQueue = DispatchQueue(
                    label: "app.vidindir.subprocess.supervision",
                    qos: .utility
                )
                supervisionQueue.async {
                    _ = Self.waitForExitWithoutReaping(
                        subprocess.processIdentifier
                    )
                    ioGroup.wait()
                    terminationController.sealTerminationAndWaitForEscalation()
                    // Always make the independent waitpid attempt, including if
                    // waitid itself reported an error, so an unusual observation
                    // failure cannot leave our direct child unreaped.
                    let waitResult = Self.wait(for: subprocess.processIdentifier)

                    // Output callbacks are deliberately not a completion
                    // barrier. A client callback may perform slow work (or
                    // block indefinitely), but it must never prevent timeout,
                    // cancellation, process reaping, or result delivery.
                    if state.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if let framingError = state.framingError {
                        continuation.resume(throwing: framingError)
                    } else {
                        continuation.resume(with: waitResult.map { termination in
                            SubprocessResult(
                                exitCode: termination.exitCode,
                                terminationReason: termination.reason,
                                standardOutput: state.standardOutput,
                                standardError: state.standardError
                            )
                        })
                    }
                }
            }
        } onCancel: {
            state.cancel()
            terminationController.requestTermination()
        }
    }

    /// Launches the executable directly, without a shell, in a new process group.
    /// The process group lets cancellation supervise descendants as well as the
    /// immediate child, including descendants that keep the output pipes open.
    private static func spawn(_ invocation: ProcessInvocation) throws -> SpawnedSubprocess {
        var outputDescriptors: [Int32] = [-1, -1]
        var errorDescriptors: [Int32] = [-1, -1]

        guard Darwin.pipe(&outputDescriptors) == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription())
        }

        guard Darwin.pipe(&errorDescriptors) == 0 else {
            closeIfOpen(outputDescriptors[0])
            closeIfOpen(outputDescriptors[1])
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription())
        }

        // A host process is allowed to start with stdout or stderr closed. In
        // that case pipe() may return descriptor 1 or 2; later close actions
        // would then close the stream we just redirected. Move every pipe end
        // above the standard descriptor range before building file actions.
        do {
            for index in outputDescriptors.indices {
                try moveAboveStandardStreams(&outputDescriptors[index])
            }
            for index in errorDescriptors.indices {
                try moveAboveStandardStreams(&errorDescriptors[index])
            }
            try makeNonblocking(outputDescriptors[0])
            try makeNonblocking(errorDescriptors[0])
        } catch {
            outputDescriptors.forEach(closeIfOpen)
            errorDescriptors.forEach(closeIfOpen)
            throw error
        }

        var descriptorsWereTransferred = false
        defer {
            if !descriptorsWereTransferred {
                outputDescriptors.forEach(closeIfOpen)
                errorDescriptors.forEach(closeIfOpen)
            }
        }

        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?

        var status = posix_spawn_file_actions_init(&fileActions)
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        status = posix_spawnattr_init(&attributes)
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }
        defer { posix_spawnattr_destroy(&attributes) }

        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        status = posix_spawnattr_setflags(&attributes, flags)
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }

        // A group ID of zero gives the child a process group whose ID is its PID.
        status = posix_spawnattr_setpgroup(&attributes, 0)
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }

        status = posix_spawn_file_actions_adddup2(
            &fileActions,
            outputDescriptors[1],
            STDOUT_FILENO
        )
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }

        status = posix_spawn_file_actions_adddup2(
            &fileActions,
            errorDescriptors[1],
            STDERR_FILENO
        )
        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }

        for descriptor in outputDescriptors + errorDescriptors {
            status = posix_spawn_file_actions_addclose(&fileActions, descriptor)
            guard status == 0 else {
                throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
            }
        }

        if let currentDirectoryURL = invocation.currentDirectoryURL {
            status = currentDirectoryURL.withUnsafeFileSystemRepresentation { path in
                guard let path else { return EINVAL }
                return posix_spawn_file_actions_addchdir_np(&fileActions, path)
            }
            guard status == 0 else {
                throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
            }
        }

        let arguments = [invocation.executableURL.path] + invocation.arguments
        let argumentVector = CStringVector(arguments)
        let environmentVector = invocation.environment.map {
            CStringVector($0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
        }
        var processIdentifier: pid_t = 0

        status = invocation.executableURL.withUnsafeFileSystemRepresentation { executablePath in
            guard let executablePath else { return EINVAL }
            return argumentVector.withUnsafeMutablePointer { arguments in
                if let environmentVector {
                    return environmentVector.withUnsafeMutablePointer { environment in
                        posix_spawn(
                            &processIdentifier,
                            executablePath,
                            &fileActions,
                            &attributes,
                            arguments,
                            environment
                        )
                    }
                }

                return posix_spawn(
                    &processIdentifier,
                    executablePath,
                    &fileActions,
                    &attributes,
                    arguments,
                    environ
                )
            }
        }

        guard status == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription(status))
        }

        // Only the child writes to these descriptors. Closing the parent's copies
        // ensures EOF arrives after the final descendant exits or is terminated.
        closeIfOpen(outputDescriptors[1])
        closeIfOpen(errorDescriptors[1])
        outputDescriptors[1] = -1
        errorDescriptors[1] = -1

        let subprocess = SpawnedSubprocess(
            processIdentifier: processIdentifier,
            standardOutput: outputDescriptors[0],
            standardError: errorDescriptors[0]
        )
        outputDescriptors[0] = -1
        errorDescriptors[0] = -1
        descriptorsWereTransferred = true
        return subprocess
    }

    private static func read(
        _ descriptor: Int32,
        stream: SubprocessStream,
        state: SubprocessState
    ) {
        // This queue owns the descriptor for its entire lifetime. Cancellation
        // is observed through state rather than closing the descriptor from a
        // different thread, which avoids a close/read race if the descriptor
        // number is reused by an unrelated process operation.
        defer { closeIfOpen(descriptor) }
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        var descriptorStatus = pollfd(
            fd: descriptor,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )

        while !state.shouldStopReading {
            descriptorStatus.revents = 0
            // A finite poll keeps cancellation bounded without closing a file
            // descriptor underneath an active read or waking continuously.
            let pollResult = Darwin.poll(&descriptorStatus, 1, 100)
            if pollResult == -1 {
                if errno == EINTR { continue }
                if !state.shouldStopReading {
                    state.setReadError(systemErrorDescription())
                }
                return
            }
            if pollResult == 0 { continue }

            while !state.shouldStopReading {
                let byteCount = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                }

                if byteCount > 0 {
                    state.consume(Data(buffer.prefix(byteCount)), stream: stream)
                } else if byteCount == 0 {
                    state.finish(stream: stream)
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                } else {
                    if !state.shouldStopReading {
                        state.setReadError(systemErrorDescription())
                    }
                    return
                }
            }
        }
    }

    private static func wait(for processIdentifier: pid_t) -> Result<SubprocessTermination, Error> {
        var waitStatus: Int32 = 0
        var result: pid_t

        repeat {
            result = Darwin.waitpid(processIdentifier, &waitStatus, 0)
        } while result == -1 && errno == EINTR

        guard result == processIdentifier else {
            return .failure(SubprocessRunnerError.couldNotWait(systemErrorDescription()))
        }

        let status = waitStatus & 0x7f
        if status == 0 {
            return .success(SubprocessTermination(
                exitCode: (waitStatus >> 8) & 0xff,
                reason: .exit
            ))
        }

        return .success(SubprocessTermination(exitCode: status, reason: .uncaughtSignal))
    }

    private static func waitForExitWithoutReaping(
        _ processIdentifier: pid_t
    ) -> Result<Void, Error> {
        var information = siginfo_t()
        var result: Int32

        repeat {
            result = Darwin.waitid(
                P_PID,
                id_t(processIdentifier),
                &information,
                WEXITED | WNOWAIT
            )
        } while result == -1 && errno == EINTR

        guard result == 0 else {
            return .failure(SubprocessRunnerError.couldNotWait(systemErrorDescription()))
        }
        return .success(())
    }

    private static func closeIfOpen(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = Darwin.close(descriptor)
    }

    private static func moveAboveStandardStreams(_ descriptor: inout Int32) throws {
        guard descriptor >= 0, descriptor <= STDERR_FILENO else { return }
        let movedDescriptor = Darwin.fcntl(
            descriptor,
            F_DUPFD_CLOEXEC,
            STDERR_FILENO + 1
        )
        guard movedDescriptor >= 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription())
        }
        closeIfOpen(descriptor)
        descriptor = movedDescriptor
    }

    private static func makeNonblocking(_ descriptor: Int32) throws {
        let currentFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard currentFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            throw SubprocessRunnerError.couldNotLaunch(systemErrorDescription())
        }
    }

    private static func systemErrorDescription(_ errorNumber: Int32 = errno) -> String {
        String(cString: strerror(errorNumber))
    }
}

public enum SubprocessRunnerError: LocalizedError, Equatable, Sendable {
    case couldNotLaunch(String)
    case couldNotRead(String)
    case couldNotWait(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .couldNotLaunch(let message):
            return "The process could not start: \(message)"
        case .couldNotRead(let message):
            return "The process output could not be read: \(message)"
        case .couldNotWait(let message):
            return "The process could not be supervised: \(message)"
        case .timedOut:
            return "The process did not finish in time."
        }
    }
}

private final class SubprocessTerminationController: @unchecked Sendable {
    private let gracePeriod: Duration
    private let lock = NSLock()
    private let escalationGroup = DispatchGroup()
    private var processGroupID: pid_t?
    private var terminationRequested = false
    private var terminationStarted = false
    private var terminationSealed = false

    init(gracePeriod: Duration) {
        self.gracePeriod = gracePeriod
    }

    func requestTermination() {
        let groupID = lock.withSubprocessLock { () -> pid_t? in
            terminationRequested = true
            return beginTerminationIfPossible()
        }
        startTermination(for: groupID)
    }

    func processDidLaunch(processGroupID: pid_t) {
        let groupID = lock.withSubprocessLock { () -> pid_t? in
            self.processGroupID = processGroupID
            return beginTerminationIfPossible()
        }
        startTermination(for: groupID)
    }

    /// Called only while `lock` is held. Marking termination as started in the
    /// same critical section as the request prevents sealing from slipping into
    /// the gap between a request flag and the first signal.
    private func beginTerminationIfPossible() -> pid_t? {
        guard terminationRequested,
              !terminationStarted,
              !terminationSealed,
              let processGroupID,
              processGroupID > 0 else { return nil }
        terminationStarted = true
        escalationGroup.enter()
        return processGroupID
    }

    private func startTermination(for groupID: pid_t?) {
        guard let groupID else { return }

        Self.signalProcessGroup(groupID, signal: SIGTERM)
        Task.detached { [self] in
            defer { escalationGroup.leave() }
            try? await Task.sleep(for: gracePeriod)
            Self.signalProcessGroup(groupID, signal: SIGKILL)
        }
    }

    func sealTerminationAndWaitForEscalation() {
        let shouldWait = lock.withSubprocessLock {
            terminationSealed = true
            return terminationStarted
        }
        if shouldWait {
            escalationGroup.wait()
        }
    }

    private static func signalProcessGroup(_ processGroupID: pid_t, signal: Int32) {
        // A negative PID addresses every process in the group. ESRCH is benign:
        // it means the group exited before the signal was sent.
        _ = Darwin.kill(-processGroupID, signal)
    }
}

private struct SpawnedSubprocess: Sendable {
    let processIdentifier: pid_t
    let standardOutput: Int32
    let standardError: Int32
}

private struct SubprocessTermination: Sendable {
    let exitCode: Int32
    let reason: Process.TerminationReason
}

private final class CStringVector {
    private var pointers: [UnsafeMutablePointer<CChar>?]

    init(_ strings: [String]) {
        pointers = strings.map { strdup($0) }
        pointers.append(nil)
    }

    deinit {
        for pointer in pointers.dropLast() {
            free(pointer)
        }
    }

    func withUnsafeMutablePointer<T>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T
    ) rethrows -> T {
        try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}

private final class SubprocessState: @unchecked Sendable {
    private let lock = NSLock()
    private let callbackDispatcher: BoundedLineCallbackDispatcher
    private var outputFramer = ByteLineFramer()
    private var errorFramer = ByteLineFramer()
    private var outputCapture: BoundedLineCapture
    private var errorCapture: BoundedLineCapture
    private var error: Error?
    private var cancelled = false

    init(
        maximumCapturedLineCountPerStream: Int,
        maximumCapturedUTF8BytesPerStream: Int,
        maximumPendingLineCallbackCount: Int,
        maximumPendingLineCallbackUTF8Bytes: Int,
        onLine: @escaping SubprocessRunner.LineHandler
    ) {
        outputCapture = BoundedLineCapture(
            maximumLineCount: maximumCapturedLineCountPerStream,
            maximumUTF8Bytes: maximumCapturedUTF8BytesPerStream
        )
        errorCapture = BoundedLineCapture(
            maximumLineCount: maximumCapturedLineCountPerStream,
            maximumUTF8Bytes: maximumCapturedUTF8BytesPerStream
        )
        callbackDispatcher = BoundedLineCallbackDispatcher(
            maximumPendingLineCount: maximumPendingLineCallbackCount,
            maximumPendingUTF8Bytes: maximumPendingLineCallbackUTF8Bytes,
            onLine: onLine
        )
    }

    var standardOutput: [String] {
        lock.withSubprocessLock { outputCapture.lines }
    }

    var standardError: [String] {
        lock.withSubprocessLock { errorCapture.lines }
    }

    var framingError: Error? {
        lock.withSubprocessLock { error }
    }

    var wasCancelled: Bool {
        lock.withSubprocessLock { cancelled }
    }

    var shouldStopReading: Bool {
        lock.withSubprocessLock { cancelled }
    }

    func cancel() {
        lock.withSubprocessLock { cancelled = true }
        callbackDispatcher.discardPending()
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

    func setReadError(_ message: String) {
        set(error: SubprocessRunnerError.couldNotRead(message))
    }

    private func publish(_ lines: [String], stream: SubprocessStream) {
        guard !lines.isEmpty else { return }
        let shouldPublishCallbacks = lock.withSubprocessLock { () -> Bool in
            switch stream {
            case .standardOutput: outputCapture.append(contentsOf: lines)
            case .standardError: errorCapture.append(contentsOf: lines)
            }
            return !cancelled
        }
        if shouldPublishCallbacks {
            callbackDispatcher.enqueue(lines, stream: stream)
        }
    }

    private func set(error newError: Error) {
        lock.withSubprocessLock {
            if error == nil { error = newError }
        }
    }
}

/// Delivers line events on a private serial queue without ever turning callback
/// work into a subprocess completion barrier. Only one drain closure is queued;
/// if the callback is slow or blocks, pending payload stays within both explicit
/// limits and is reduced to its newest suffix.
private final class BoundedLineCallbackDispatcher: @unchecked Sendable {
    private struct Event {
        let stream: SubprocessStream
        let line: String
        let utf8ByteCount: Int
    }

    private let callbackQueue = DispatchQueue(label: "app.vidindir.subprocess.events")
    private let lock = NSLock()
    private let maximumPendingLineCount: Int
    private let maximumPendingUTF8Bytes: Int
    private let onLine: SubprocessRunner.LineHandler

    private var storage: [Event?] = []
    private var firstPendingIndex = 0
    private var pendingUTF8Bytes = 0
    private var drainScheduled = false
    private var acceptsEvents = true

    init(
        maximumPendingLineCount: Int,
        maximumPendingUTF8Bytes: Int,
        onLine: @escaping SubprocessRunner.LineHandler
    ) {
        self.maximumPendingLineCount = maximumPendingLineCount
        self.maximumPendingUTF8Bytes = maximumPendingUTF8Bytes
        self.onLine = onLine
    }

    func enqueue(_ lines: [String], stream: SubprocessStream) {
        let shouldScheduleDrain = lock.withSubprocessLock { () -> Bool in
            guard acceptsEvents else { return false }
            for line in lines {
                append(Event(
                    stream: stream,
                    line: line,
                    utf8ByteCount: line.utf8.count
                ))
            }

            guard pendingCount > 0, !drainScheduled else { return false }
            drainScheduled = true
            return true
        }

        if shouldScheduleDrain {
            callbackQueue.async { [self] in drain() }
        }
    }

    func discardPending() {
        lock.withSubprocessLock {
            acceptsEvents = false
            storage.removeAll(keepingCapacity: false)
            firstPendingIndex = 0
            pendingUTF8Bytes = 0
        }
    }

    private func drain() {
        while let event = takeFirst() {
            onLine(event.stream, event.line)
        }
    }

    private func takeFirst() -> Event? {
        lock.withSubprocessLock {
            guard pendingCount > 0 else {
                drainScheduled = false
                return nil
            }

            guard let event = storage[firstPendingIndex] else {
                preconditionFailure("The pending callback range contained an empty entry.")
            }
            storage[firstPendingIndex] = nil
            firstPendingIndex += 1
            pendingUTF8Bytes -= event.utf8ByteCount
            compactDiscardedPrefixIfNeeded()
            return event
        }
    }

    private func append(_ event: Event) {
        guard event.utf8ByteCount <= maximumPendingUTF8Bytes else {
            // A single event that cannot fit is omitted without disturbing the
            // already queued suffix.
            return
        }

        while pendingCount >= maximumPendingLineCount
            || pendingUTF8Bytes > maximumPendingUTF8Bytes - event.utf8ByteCount {
            evictFirst()
        }

        storage.append(event)
        pendingUTF8Bytes += event.utf8ByteCount
        compactDiscardedPrefixIfNeeded()
    }

    private func evictFirst() {
        guard pendingCount > 0,
              let event = storage[firstPendingIndex] else {
            preconditionFailure("Cannot evict from an empty callback queue.")
        }
        storage[firstPendingIndex] = nil
        firstPendingIndex += 1
        pendingUTF8Bytes -= event.utf8ByteCount
    }

    private var pendingCount: Int {
        storage.count - firstPendingIndex
    }

    private func compactDiscardedPrefixIfNeeded() {
        let compactionThreshold = min(1_024, maximumPendingLineCount)
        guard firstPendingIndex >= compactionThreshold,
              firstPendingIndex * 2 >= storage.count else { return }
        storage.removeFirst(firstPendingIndex)
        firstPendingIndex = 0
    }
}

/// A suffix buffer whose retained payload has two explicit bounds. The stale
/// prefix is compacted incrementally so sustained output cannot make the
/// backing array grow with the lifetime total.
private struct BoundedLineCapture {
    private struct Entry {
        let line: String
        let utf8ByteCount: Int
    }

    let maximumLineCount: Int
    let maximumUTF8Bytes: Int

    private var storage: [Entry?] = []
    private var firstRetainedIndex = 0
    private var retainedUTF8Bytes = 0

    init(maximumLineCount: Int, maximumUTF8Bytes: Int) {
        self.maximumLineCount = maximumLineCount
        self.maximumUTF8Bytes = maximumUTF8Bytes
    }

    var lines: [String] {
        storage[firstRetainedIndex...].compactMap { $0?.line }
    }

    mutating func append(contentsOf lines: [String]) {
        for line in lines {
            append(line)
        }
    }

    private mutating func append(_ line: String) {
        let byteCount = line.utf8.count
        guard byteCount <= maximumUTF8Bytes else {
            // No complete representation of this line can fit. Clearing the
            // older suffix keeps subsequent captures anchored after it.
            storage.removeAll(keepingCapacity: true)
            firstRetainedIndex = 0
            retainedUTF8Bytes = 0
            return
        }

        while retainedCount >= maximumLineCount
            || retainedUTF8Bytes > maximumUTF8Bytes - byteCount {
            guard let evicted = storage[firstRetainedIndex] else {
                preconditionFailure("The retained capture range contained an empty entry.")
            }
            retainedUTF8Bytes -= evicted.utf8ByteCount
            // Release evicted line storage immediately. Compaction bounds the
            // number of empty array slots independently of payload size.
            storage[firstRetainedIndex] = nil
            firstRetainedIndex += 1
        }

        storage.append(Entry(line: line, utf8ByteCount: byteCount))
        retainedUTF8Bytes += byteCount
        compactDiscardedPrefixIfNeeded()
    }

    private var retainedCount: Int {
        storage.count - firstRetainedIndex
    }

    private mutating func compactDiscardedPrefixIfNeeded() {
        let compactionThreshold = min(1_024, maximumLineCount)
        guard firstRetainedIndex >= compactionThreshold,
              firstRetainedIndex * 2 >= storage.count else { return }
        storage.removeFirst(firstRetainedIndex)
        firstRetainedIndex = 0
    }
}

private extension NSLock {
    func withSubprocessLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
