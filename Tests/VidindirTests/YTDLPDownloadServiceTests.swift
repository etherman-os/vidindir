import Foundation
import Testing
@testable import Vidindir

@Suite("yt-dlp download service")
struct YTDLPDownloadServiceTests {
    @Test func reconcilesTheFinalArtifactBeforeReturning() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidindirDownloadService-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: destination) }
        let artifact = destination.appendingPathComponent("video.mp4")
        try Data("media".utf8).write(to: artifact)

        let event = #"__VIDINDIR_YTDLP__{"event":"artifact","path":"video.mp4"}"#
        let runner = StubDownloadRunner(result: SubprocessResult(
            exitCode: 0,
            terminationReason: .exit,
            standardOutput: [event],
            standardError: []
        ))
        let service = YTDLPDownloadService(processRunner: runner)

        let record = try await service.download(
            request(destination: destination),
            tools: tools
        )

        #expect(record.status == .completed)
        #expect(record.outputFileURL == artifact.resolvingSymlinksInPath())
    }

    @Test func redactsProcessFailuresAndPublishedLogs() async {
        let secretLine = "ERROR https://example.com/watch?token=private Authorization: Bearer hidden"
        let runner = StubDownloadRunner(
            result: SubprocessResult(
                exitCode: 7,
                terminationReason: .exit,
                standardOutput: [],
                standardError: [secretLine]
            ),
            streamedLines: [(.standardError, secretLine)]
        )
        let service = YTDLPDownloadService(processRunner: runner)
        let observation = DownloadEventObservation()

        do {
            _ = try await service.download(
                request(destination: FileManager.default.temporaryDirectory),
                tools: tools,
                onEvent: observation.record
            )
            Issue.record("Expected the process failure")
        } catch {
            #expect(!error.localizedDescription.contains("private"))
            #expect(!error.localizedDescription.contains("hidden"))
            #expect(error.localizedDescription.contains("https://example.com/watch"))
        }

        #expect(!observation.joinedLogs.contains("private"))
        #expect(!observation.joinedLogs.contains("hidden"))
        #expect(observation.joinedLogs.contains("[REDACTED]"))
    }

    @Test func explicitCancellationReachesTheProcessRunner() async {
        let service = YTDLPDownloadService(processRunner: BlockingDownloadRunner())
        let observation = DownloadEventObservation()
        let task = Task {
            try await service.download(
                request(destination: FileManager.default.temporaryDirectory),
                tools: tools,
                onEvent: observation.record
            )
        }

        let started = await waitForDownload(timeout: .seconds(2)) {
            service.isDownloading
        }
        #expect(started)
        service.cancelCurrentDownload()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }

        #expect(observation.events.contains(.cancelled))
        #expect(!service.isDownloading)
    }

    private var tools: ToolAvailability {
        ToolAvailability(
            ytDLP: URL(fileURLWithPath: "/usr/bin/true"),
            ffmpeg: URL(fileURLWithPath: "/usr/bin/true"),
            deno: URL(fileURLWithPath: "/usr/bin/true")
        )
    }

    private func request(destination: URL) -> DownloadRequest {
        DownloadRequest(
            sourceURL: URL(string: "https://example.com/video")!,
            format: .mp4,
            destinationDirectory: destination
        )
    }

    private func waitForDownload(
        timeout: Duration,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private struct StubDownloadRunner: ProcessRunning {
    let result: SubprocessResult
    var streamedLines: [(SubprocessStream, String)] = []

    func run(
        _ invocation: ProcessInvocation,
        timeout: Duration?,
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void
    ) async throws -> SubprocessResult {
        for (stream, line) in streamedLines {
            onLine(stream, line)
        }
        return result
    }
}

private struct BlockingDownloadRunner: ProcessRunning {
    func run(
        _ invocation: ProcessInvocation,
        timeout: Duration?,
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void
    ) async throws -> SubprocessResult {
        try await Task.sleep(for: .seconds(30))
        return SubprocessResult(
            exitCode: 0,
            terminationReason: .exit,
            standardOutput: [],
            standardError: []
        )
    }
}

private final class DownloadEventObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadServiceEvent] = []

    var events: [DownloadServiceEvent] {
        lock.withLock { storage }
    }

    var joinedLogs: String {
        events.compactMap { event in
            guard case .log(let line) = event else { return nil }
            return line
        }.joined(separator: "\n")
    }

    func record(_ event: DownloadServiceEvent) {
        lock.withLock { storage.append(event) }
    }
}
