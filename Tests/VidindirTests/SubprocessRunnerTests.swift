import Darwin
import Foundation
import Testing
@testable import Vidindir

@Suite("Subprocess execution")
struct SubprocessRunnerTests {
    @Test func drainsStdoutAndStderrIncludingFinalNewlineLessText() async throws {
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out\\nlast'; printf 'warning\\nend' >&2"]
        )
        let result = try await SubprocessRunner().run(invocation)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == ["out", "last"])
        #expect(result.standardError == ["warning", "end"])
    }

    @Test func returnsNonzeroExitCodeWithoutDiscardingOutput() async throws {
        let result = try await SubprocessRunner().run(ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf failure >&2; exit 7"]
        ))

        #expect(result.exitCode == 7)
        #expect(result.standardError == ["failure"])
    }

    @Test func timeoutCancelsAndBoundsAnUncooperativeProcess() async {
        let runner = SubprocessRunner(
            timeoutTerminationGracePeriod: .milliseconds(50)
        )
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do :; done"]
        )
        let startedAt = Date()

        do {
            _ = try await runner.run(invocation, timeout: .milliseconds(50))
            Issue.record("Expected the process to time out")
        } catch let error as SubprocessRunnerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected timeout error: \(error)")
        }

        // A loaded Intel CI runner can delay task resumption even after the
        // process group has already been killed. Keep this a boundedness check,
        // not a scheduler-latency benchmark.
        #expect(Date().timeIntervalSince(startedAt) < 3)
    }

    @Test func timeoutDoesNotWaitForABlockingLineCallback() async {
        let runner = SubprocessRunner(
            timeoutTerminationGracePeriod: .milliseconds(50)
        )
        let releaseCallback = DispatchSemaphore(value: 0)
        let observation = LineObservation()
        let task = Task {
            try await runner.run(
                ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo ready; trap '' TERM; while :; do :; done"]
                ),
                timeout: .seconds(1)
            ) { stream, line in
                observation.record(stream: stream, line: line)
                releaseCallback.wait()
            }
        }

        let callbackStarted = await waitUntil(timeout: .seconds(5)) {
            observation.standardOutput == ["ready"]
        }
        guard callbackStarted else {
            task.cancel()
            releaseCallback.signal()
            Issue.record("Expected the output callback to start")
            return
        }

        // Always release the deliberately blocked callback, including if a
        // regression makes result delivery wait behind it. The delayed release
        // keeps the test itself bounded while the elapsed-time assertion fails.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            releaseCallback.signal()
        }
        let startedWaitingAt = Date()

        do {
            _ = try await task.value
            Issue.record("Expected the process to time out")
        } catch let error as SubprocessRunnerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected blocking-callback timeout error: \(error)")
        }

        #expect(Date().timeIntervalSince(startedWaitingAt) < 2)
        releaseCallback.signal()
    }

    @Test func successfulCompletionDoesNotWaitForABlockingLineCallback() async throws {
        let releaseCallback = DispatchSemaphore(value: 0)
        let observation = LineObservation()
        let task = Task {
            try await SubprocessRunner().run(ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo ready"]
            )) { stream, line in
                observation.record(stream: stream, line: line)
                releaseCallback.wait()
            }
        }

        let callbackStarted = await waitUntil(timeout: .seconds(5)) {
            observation.standardOutput == ["ready"]
        }
        guard callbackStarted else {
            task.cancel()
            releaseCallback.signal()
            Issue.record("Expected the output callback to start")
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            releaseCallback.signal()
        }
        let startedWaitingAt = Date()
        let result = try await task.value

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == ["ready"])
        #expect(Date().timeIntervalSince(startedWaitingAt) < 0.75)
        releaseCallback.signal()
    }

    @Test func boundsCapturedOutputWithoutDroppingStreamedLines() async throws {
        let runner = SubprocessRunner(
            maximumCapturedLineCountPerStream: 3,
            maximumCapturedUTF8BytesPerStream: 11
        )
        let observation = LineObservation()
        let result = try await runner.run(ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "printf 'one\\ntwo\\nthree\\nfour\\n'; printf 'alpha\\nbeta\\ngamma\\n' >&2",
            ]
        )) { stream, line in
            observation.record(stream: stream, line: line)
        }

        // Capture is a newest-lines suffix. The byte cap is independent for
        // stdout and stderr; this small stream fits entirely within the
        // separate callback-delivery limits even when capture evicts lines.
        #expect(result.standardOutput == ["three", "four"])
        #expect(result.standardError == ["beta", "gamma"])

        let receivedEveryCallback = await waitUntil(timeout: .seconds(5)) {
            observation.standardOutput == ["one", "two", "three", "four"]
                && observation.standardError == ["alpha", "beta", "gamma"]
        }
        #expect(receivedEveryCallback)
    }

    @Test func boundsPendingCallbackCountWhileKeepingRecentStreamingEvents() async throws {
        let lines = try await runBlockedCallbackBurst(
            maximumPendingLineCount: 3,
            maximumPendingUTF8Bytes: 4_096
        )

        #expect(lines == ["first", "line098", "line099", "line100"])
    }

    @Test func boundsPendingCallbackPayloadBytesWhileKeepingRecentStreamingEvents() async throws {
        let lines = try await runBlockedCallbackBurst(
            maximumPendingLineCount: 100,
            // Every generated burst line is seven UTF-8 bytes, so only the
            // newest three can remain queued behind the blocked callback.
            maximumPendingUTF8Bytes: 21
        )

        #expect(lines == ["first", "line098", "line099", "line100"])
    }

    @Test func timeoutTerminatesTheWholeProcessGroupAndClosesInheritedPipes() async {
        let runner = SubprocessRunner(
            timeoutTerminationGracePeriod: .milliseconds(100)
        )
        let observation = ProcessTreeObservation()
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                """
                trap '' TERM
                echo "leader:$$"
                /bin/sh -c 'trap "" TERM; echo "grandchild:$$"; echo "inherited-stderr" >&2; while :; do /bin/sleep 30; done' &
                wait
                """
            ]
        )
        let startedAt = Date()

        do {
            _ = try await runner.run(
                invocation,
                timeout: .milliseconds(1500)
            ) { stream, line in
                observation.record(stream: stream, line: line)
            }
            Issue.record("Expected the process tree to time out")
        } catch let error as SubprocessRunnerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected process-tree timeout error: \(error)")
        }

        // If only the immediate child is killed, the TERM-ignoring grandchild
        // keeps both pipes open and this assertion is reached much later (or not
        // at all). The grace period plus generous scheduling headroom stays bound.
        #expect(Date().timeIntervalSince(startedAt) < 3.5)
        #expect(observation.sawInheritedStandardError)

        guard let leader = observation.leader,
              let grandchild = observation.grandchild else {
            Issue.record("Expected to observe both process identifiers")
            return
        }

        let descendantsExited = await waitUntil(timeout: .seconds(5)) {
            !processExists(grandchild) && !processGroupExists(leader)
        }
        #expect(descendantsExited)
    }

    @Test func timeoutClosesPipesHeldByADescendantThatEscapedTheProcessGroup() async {
        let runner = SubprocessRunner(
            timeoutTerminationGracePeriod: .milliseconds(50)
        )
        let observation = ProcessTreeObservation()
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [
                "-MPOSIX=setsid",
                "-e",
                """
                $| = 1;
                print "leader:$$\\n";
                my $child = fork();
                die "fork failed" unless defined $child;
                if ($child == 0) {
                    die "setsid failed" unless defined setsid();
                    $SIG{HUP} = 'IGNORE';
                    print "escaped:$$\\n";
                    sleep 5;
                    exit 0;
                }
                waitpid($child, 0);
                """,
            ]
        )
        let startedAt = Date()

        do {
            _ = try await runner.run(
                invocation,
                timeout: .milliseconds(1500)
            ) { stream, line in
                observation.record(stream: stream, line: line)
            }
            Issue.record("Expected the escaped-descendant process tree to time out")
        } catch let error as SubprocessRunnerError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Unexpected escaped-descendant timeout error: \(error)")
        }

        // The escaped child deliberately retains both output pipes for five
        // seconds. Returning well before then proves cancellation stopped the
        // host readers instead of waiting for inherited-pipe EOF.
        #expect(Date().timeIntervalSince(startedAt) < 3.5)

        guard let leader = observation.leader,
              let escaped = observation.escaped else {
            Issue.record("Expected to observe the leader and escaped descendant")
            return
        }

        #expect(processExists(escaped))
        #expect(Darwin.getsid(escaped) == escaped)

        // The runner must already have reaped its direct child before returning.
        var waitStatus: Int32 = 0
        errno = 0
        #expect(Darwin.waitpid(leader, &waitStatus, WNOHANG) == -1)
        #expect(errno == ECHILD)

        _ = Darwin.kill(escaped, SIGKILL)
        let escapedExited = await waitUntil(timeout: .seconds(5)) {
            !processExists(escaped)
        }
        #expect(escapedExited)
    }

    @Test func cancellationAfterPipesCloseDoesNotReapBeforeTermination() async {
        let runner = SubprocessRunner(
            timeoutTerminationGracePeriod: .milliseconds(100)
        )
        let observation = ProcessTreeObservation()
        let task = Task {
            try await runner.run(ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "echo \"leader:$$\"; exec 1>&- 2>&-; trap '' TERM; while :; do /bin/sleep 30; done",
                ]
            )) { stream, line in
                observation.record(stream: stream, line: line)
            }
        }

        let observedLeader = await waitUntil(timeout: .seconds(5)) {
            observation.leader != nil
        }
        #expect(observedLeader)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation while the pipe-less process was running")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }

        if let leader = observation.leader {
            let groupExited = await waitUntil(timeout: .seconds(5)) {
                !processGroupExists(leader)
            }
            #expect(groupExited)
        }
    }

    private func waitUntil(
        timeout: Duration,
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func runBlockedCallbackBurst(
        maximumPendingLineCount: Int,
        maximumPendingUTF8Bytes: Int
    ) async throws -> [String] {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let gateURL = temporaryDirectory.appendingPathComponent("continue")
        let releaseCallback = DispatchSemaphore(value: 0)
        defer { releaseCallback.signal() }
        let observation = LineObservation()
        let runner = SubprocessRunner(
            maximumPendingLineCallbackCount: maximumPendingLineCount,
            maximumPendingLineCallbackUTF8Bytes: maximumPendingUTF8Bytes
        )

        let task = Task {
            try await runner.run(
                ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                    arguments: [
                        "-e",
                        """
                        $| = 1;
                        print "first\\n";
                        while (!-e $ARGV[0]) { select undef, undef, undef, 0.01; }
                        for my $index (1..100) { printf "line%03d\\n", $index; }
                        """,
                        gateURL.path,
                    ]
                ),
                timeout: .seconds(2)
            ) { stream, line in
                observation.record(stream: stream, line: line)
                if case .standardOutput = stream, line == "first" {
                    releaseCallback.wait()
                }
            }
        }

        guard await waitUntil(timeout: .seconds(5), condition: {
            observation.standardOutput == ["first"]
        }) else {
            task.cancel()
            releaseCallback.signal()
            _ = try? await task.value
            Issue.record("Expected the first callback to block before the burst")
            return observation.standardOutput
        }

        #expect(FileManager.default.createFile(atPath: gateURL.path, contents: Data()))
        let result = try await task.value
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count == 101)
        #expect(observation.standardOutput == ["first"])

        releaseCallback.signal()
        let deliveredRecentSuffix = await waitUntil(timeout: .seconds(5)) {
            observation.standardOutput.last == "line100"
        }
        #expect(deliveredRecentSuffix)
        return observation.standardOutput
    }

    private func processExists(_ processIdentifier: pid_t) -> Bool {
        errno = 0
        return Darwin.kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    private func processGroupExists(_ processGroupIdentifier: pid_t) -> Bool {
        errno = 0
        return Darwin.kill(-processGroupIdentifier, 0) == 0 || errno == EPERM
    }
}

private final class ProcessTreeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var observedLeader: pid_t?
    private var observedGrandchild: pid_t?
    private var observedEscaped: pid_t?
    private var observedInheritedStandardError = false

    var leader: pid_t? {
        lock.withLock { observedLeader }
    }

    var grandchild: pid_t? {
        lock.withLock { observedGrandchild }
    }

    var escaped: pid_t? {
        lock.withLock { observedEscaped }
    }

    var sawInheritedStandardError: Bool {
        lock.withLock { observedInheritedStandardError }
    }

    func record(stream: SubprocessStream, line: String) {
        lock.withLock {
            switch stream {
            case .standardOutput:
                if line.hasPrefix("leader:") {
                    observedLeader = pid_t(line.dropFirst("leader:".count))
                } else if line.hasPrefix("grandchild:") {
                    observedGrandchild = pid_t(line.dropFirst("grandchild:".count))
                } else if line.hasPrefix("escaped:") {
                    observedEscaped = pid_t(line.dropFirst("escaped:".count))
                }
            case .standardError:
                if line == "inherited-stderr" {
                    observedInheritedStandardError = true
                }
            }
        }
    }
}

private final class LineObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var outputLines: [String] = []
    private var errorLines: [String] = []

    var standardOutput: [String] {
        lock.withLock { outputLines }
    }

    var standardError: [String] {
        lock.withLock { errorLines }
    }

    func record(stream: SubprocessStream, line: String) {
        lock.withLock {
            switch stream {
            case .standardOutput: outputLines.append(line)
            case .standardError: errorLines.append(line)
            }
        }
    }
}
