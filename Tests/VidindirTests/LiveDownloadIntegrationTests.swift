import Foundation
import Testing
@testable import Vidindir

private let liveDownloadURL = ProcessInfo.processInfo.environment["VIDINDIR_LIVE_TEST_URL"]

@Suite(
    "Live download integration",
    .enabled(
        if: liveDownloadURL != nil,
        "Set VIDINDIR_LIVE_TEST_URL to an authorized public media URL."
    )
)
struct LiveDownloadIntegrationTests {
    @Test("downloads and post-processes a real link as MP4 and MP3")
    func downloadsAuthorizedLink() async throws {
        guard let liveDownloadURL,
              let sourceURL = URL(string: liveDownloadURL) else {
            Issue.record("VIDINDIR_LIVE_TEST_URL is not a valid URL")
            return
        }

        let tools = BinaryLocator().locateAll()
        guard tools.canDownload else {
            Issue.record("The live test requires yt-dlp, FFmpeg, and Deno")
            return
        }

        for format in DownloadFormat.allCases {
            try await download(sourceURL, as: format)
        }
    }

    private func download(_ sourceURL: URL, as format: DownloadFormat) async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let events = LiveDownloadEventRecorder()
        let backend = YTDLPBackend()
        let record = try await backend.download(DownloadRequest(
            sourceURL: sourceURL,
            format: format,
            destinationDirectory: destination
        )) { event in
            events.record(event)
        }

        let outputURL = try #require(record.outputFileURL)
        #expect(record.status == .completed)
        #expect(outputURL.pathExtension.lowercased() == format.fileExtension)
        #expect(outputURL.standardizedFileURL.path.hasPrefix(
            destination.standardizedFileURL.path + "/"
        ))
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let fileSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(fileSize > 0)
        #expect(events.completedOutput == outputURL)
        #expect(events.sawPlannedArtifact)
    }
}

private final class LiveDownloadEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCompletedOutput: URL?
    private var storedSawPlannedArtifact = false

    var completedOutput: URL? {
        lock.withLiveDownloadLock { storedCompletedOutput }
    }

    var sawPlannedArtifact: Bool {
        lock.withLiveDownloadLock { storedSawPlannedArtifact }
    }

    func record(_ event: DownloadBackendEvent) {
        lock.withLiveDownloadLock {
            switch event {
            case .plannedArtifact:
                storedSawPlannedArtifact = true
            case .completed(let record):
                storedCompletedOutput = record.outputFileURL
            default:
                break
            }
        }
    }
}

private extension NSLock {
    func withLiveDownloadLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
