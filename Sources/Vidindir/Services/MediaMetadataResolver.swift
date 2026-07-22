import Foundation

struct ResolvedMediaMetadata: Equatable, Sendable {
    let title: String?
    let creator: String?
    let durationSeconds: Double?
    let thumbnailURL: URL?
    let sourceLabel: String?
}

protocol MediaMetadataResolving: Sendable {
    func resolve(_ sourceURL: URL) async throws -> ResolvedMediaMetadata
}

struct YTDLPMetadataResolver: MediaMetadataResolving, Sendable {
    private let locator: BinaryLocator
    private let runner: any ProcessRunning

    init(
        locator: BinaryLocator = BinaryLocator(),
        runner: any ProcessRunning = SubprocessRunner(
            maximumCapturedLineCountPerStream: 32,
            maximumCapturedUTF8BytesPerStream: 512 * 1_024,
            maximumPendingLineCallbackCount: 16,
            maximumPendingLineCallbackUTF8Bytes: 512 * 1_024
        )
    ) {
        self.locator = locator
        self.runner = runner
    }

    func resolve(_ sourceURL: URL) async throws -> ResolvedMediaMetadata {
        guard let scheme = sourceURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              sourceURL.host != nil else {
            throw MetadataResolutionError.invalidURL
        }
        let tools = locator.locateAll()
        guard let ytDLP = tools.ytDLP else {
            throw MetadataResolutionError.engineUnavailable
        }

        var arguments = [
            "--ignore-config",
            "--no-playlist",
            "--skip-download",
            "--no-warnings",
            "--no-remote-components",
        ]
        if let deno = tools.deno {
            arguments += [
                "--js-runtimes", "deno:\(deno.path)",
            ]
        }
        arguments += [
            "--print",
            #"%(.{id,title,uploader,creator,duration,thumbnail,webpage_url,extractor_key})j"#,
            "--",
            sourceURL.absoluteString,
        ]

        let result = try await runner.run(
            ProcessInvocation(executableURL: ytDLP, arguments: arguments),
            timeout: .seconds(30),
            onLine: { _, _ in }
        )
        guard result.terminationReason == .exit, result.exitCode == 0 else {
            throw MetadataResolutionError.unavailable
        }
        guard let line = result.standardOutput.last,
              line.utf8.count <= 512 * 1_024,
              let data = line.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw MetadataResolutionError.invalidResponse
        }

        let title = Self.bounded(payload.title, bytes: 4_096)
        let creator = Self.bounded(payload.uploader ?? payload.creator, bytes: 2_048)
        let duration: Double?
        if let value = payload.duration, value.isFinite, value >= 0 {
            duration = value
        } else {
            duration = nil
        }
        let thumbnailURL = payload.thumbnail.flatMap(Self.safeHTTPURL)
        return ResolvedMediaMetadata(
            title: title,
            creator: creator,
            durationSeconds: duration,
            thumbnailURL: thumbnailURL,
            sourceLabel: Self.bounded(payload.extractorKey, bytes: 256)
        )
    }

    private static func bounded(_ value: String?, bytes: Int) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty,
              normalized.utf8.count <= bytes else {
            return nil
        }
        return normalized
    }

    private static func safeHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private struct Payload: Decodable {
        let title: String?
        let uploader: String?
        let creator: String?
        let duration: Double?
        let thumbnail: String?
        let extractorKey: String?

        enum CodingKeys: String, CodingKey {
            case title, uploader, creator, duration, thumbnail
            case extractorKey = "extractor_key"
        }
    }
}

enum MetadataResolutionError: LocalizedError, Equatable {
    case invalidURL
    case engineUnavailable
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid HTTP or HTTPS media link."
        case .engineUnavailable:
            "The download engine is not ready to inspect this link."
        case .unavailable:
            "Metadata is unavailable for this link right now. You can still save it."
        case .invalidResponse:
            "The source returned metadata Vidindir could not read. You can still save the link."
        }
    }
}
