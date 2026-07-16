import Foundation
import Testing
@testable import Vidindir

@Suite("yt-dlp command building")
struct YTDLPCommandBuilderTests {
    private let tools = ToolAvailability(
        ytDLP: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
        ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
        deno: URL(fileURLWithPath: "/opt/homebrew/bin/deno")
    )

    @Test func buildsSafeMP4ArgumentsWithoutShellQuoting() throws {
        let sourceURL = try #require(URL(string: "https://example.com/watch?v=a&list=b c"))
        let destination = URL(fileURLWithPath: "/tmp/Vidindir Downloads 🌊", isDirectory: true)
        let request = DownloadRequest(
            sourceURL: sourceURL,
            format: .mp4,
            destinationDirectory: destination
        )

        let invocation = try YTDLPCommandBuilder().build(request, tools: tools)

        #expect(invocation.executableURL.path == "/opt/homebrew/bin/yt-dlp")
        #expect(invocation.arguments.contains("--ignore-config"))
        #expect(invocation.arguments.contains("--no-playlist"))
        #expect(invocation.arguments.contains("--remote-components"))
        #expect(invocation.arguments.contains("ejs:npm"))
        #expect(invocation.arguments.contains("deno:/opt/homebrew/bin/deno"))
        #expect(invocation.arguments.contains("bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"))
        #expect(value(after: "--paths", in: invocation.arguments) == destination.path)
        #expect(value(after: "--merge-output-format", in: invocation.arguments) == "mp4")
        #expect(Array(invocation.arguments.suffix(2)) == ["--", sourceURL.absoluteString])
    }

    @Test func buildsMP3ExtractionArguments() throws {
        let request = DownloadRequest(
            sourceURL: try #require(URL(string: "https://example.com/video")),
            format: .mp3,
            destinationDirectory: URL(fileURLWithPath: "/tmp")
        )
        let arguments = try YTDLPCommandBuilder().build(request, tools: tools).arguments

        #expect(arguments.contains("--extract-audio"))
        #expect(value(after: "--audio-format", in: arguments) == "mp3")
        #expect(value(after: "--audio-quality", in: arguments) == "0")
    }

    @Test func keepsOptionLookingInputAfterEndOfOptionsMarker() throws {
        let request = DownloadRequest(
            sourceURL: try #require(URL(string: "--exec")),
            format: .mp4,
            destinationDirectory: URL(fileURLWithPath: "/tmp")
        )
        let arguments = try YTDLPCommandBuilder().build(request, tools: tools).arguments
        #expect(Array(arguments.suffix(2)) == ["--", "--exec"])
    }

    @Test func reportsTheFirstMissingTool() throws {
        let request = DownloadRequest(
            sourceURL: try #require(URL(string: "https://example.com")),
            format: .mp4,
            destinationDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(throws: YTDLPCommandBuilderError.missingTool(.ytDLP)) {
            try YTDLPCommandBuilder().build(request, tools: ToolAvailability())
        }
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
