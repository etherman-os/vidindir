import Foundation

public struct ProcessInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let currentDirectoryURL: URL?
    public let environment: [String: String]?

    public init(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
    }
}

public struct YTDLPCommandBuilder: Sendable {
    public static let outputTemplate = "%(title).180B [%(id)s].%(ext)s"

    public init() {}

    public func build(
        _ request: DownloadRequest,
        tools: ToolAvailability
    ) throws -> ProcessInvocation {
        let ytDLP = try requiredAbsoluteURL(tools.ytDLP, tool: .ytDLP)
        let ffmpeg = try requiredAbsoluteURL(tools.ffmpeg, tool: .ffmpeg)
        let deno = try requiredAbsoluteURL(tools.deno, tool: .deno)

        guard request.destinationDirectory.isFileURL,
              (request.destinationDirectory.path as NSString).isAbsolutePath else {
            throw YTDLPCommandBuilderError.invalidDestination
        }

        var arguments = [
            "--ignore-config",
            "--no-playlist",
            "--newline",
            "--no-color",
            "--progress",
            "--progress-delta", "0.2",
            "--no-simulate",
            "--trim-filenames", "180",
            "--paths", request.destinationDirectory.path,
            "--output", Self.outputTemplate,
            "--ffmpeg-location", ffmpeg.path,
            "--js-runtimes", "deno:\(deno.path)",
            "--remote-components", "ejs:npm",
            "--progress-template", Self.progressTemplate,
            "--print", Self.plannedArtifactTemplate,
            "--print", Self.postProcessingTemplate,
            "--print", Self.finalArtifactTemplate,
        ]

        switch request.format {
        case .mp4:
            arguments += [
                "--format", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
                "--merge-output-format", "mp4",
                "--remux-video", "mp4",
            ]
        case .mp3:
            arguments += [
                "--extract-audio",
                "--audio-format", "mp3",
                "--audio-quality", "0",
            ]
        }

        // Everything after this marker is an input URL, never an option. This
        // is deliberately safe even if pasted text begins with "--exec".
        arguments += ["--", request.sourceURL.absoluteString]

        return ProcessInvocation(
            executableURL: ytDLP,
            arguments: arguments,
            currentDirectoryURL: request.destinationDirectory
        )
    }

    private func requiredAbsoluteURL(_ url: URL?, tool: ToolBinary) throws -> URL {
        guard let url else {
            throw YTDLPCommandBuilderError.missingTool(tool)
        }
        guard url.isFileURL, (url.path as NSString).isAbsolutePath else {
            throw YTDLPCommandBuilderError.invalidToolPath(tool)
        }
        return url.standardizedFileURL
    }

    private static let progressTemplate =
        #"download:__VIDINDIR_YTDLP__{"event":"progress","status":%(progress.status)j,"downloadedBytes":%(progress.downloaded_bytes)j,"totalBytes":%(progress.total_bytes)j,"estimatedTotalBytes":%(progress.total_bytes_estimate)j,"speed":%(progress.speed)j,"eta":%(progress.eta)j,"filename":%(progress.filename)j}"#

    private static let plannedArtifactTemplate =
        #"before_dl:__VIDINDIR_YTDLP__{"event":"plannedArtifact","path":%(filename)j}"#

    private static let postProcessingTemplate =
        #"post_process:__VIDINDIR_YTDLP__{"event":"postProcessing"}"#

    private static let finalArtifactTemplate =
        #"after_move:__VIDINDIR_YTDLP__{"event":"artifact","path":%(filepath)j}"#
}

public enum YTDLPCommandBuilderError: LocalizedError, Equatable, Sendable {
    case missingTool(ToolBinary)
    case invalidToolPath(ToolBinary)
    case invalidDestination

    public var errorDescription: String? {
        switch self {
        case .missingTool(let tool):
            return "\(tool.displayName) was not found."
        case .invalidToolPath(let tool):
            return "\(tool.displayName) does not have a valid absolute path."
        case .invalidDestination:
            return "The download folder is not a valid absolute file path."
        }
    }
}
