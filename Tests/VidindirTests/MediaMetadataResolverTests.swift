import Foundation
import Testing
@testable import Vidindir

@Suite("Structured media metadata resolution")
struct MediaMetadataResolverTests {
    @Test func parsesBoundedStructuredOutputAndKeepsTheURLAfterTheOptionMarker() async throws {
        let fixture = try MetadataResolverFixture()
        defer { fixture.remove() }
        let runner = MetadataRunner(result: SubprocessResult(
            exitCode: 0,
            terminationReason: .exit,
            standardOutput: [
                #"{"title":"A calm SwiftUI video","uploader":"Etherman","duration":93.5,"thumbnail":"https://example.com/thumb.jpg","extractor_key":"Youtube"}"#,
            ],
            standardError: []
        ))
        let resolver = YTDLPMetadataResolver(locator: fixture.locator, runner: runner)
        let url = try #require(URL(string: "https://example.com/watch?v=a&list=b"))

        let metadata = try await resolver.resolve(url)

        #expect(metadata.title == "A calm SwiftUI video")
        #expect(metadata.creator == "Etherman")
        #expect(metadata.durationSeconds == 93.5)
        #expect(metadata.thumbnailURL == URL(string: "https://example.com/thumb.jpg"))
        let invocation = try #require(await runner.lastInvocation())
        #expect(Array(invocation.arguments.suffix(2)) == ["--", url.absoluteString])
        #expect(invocation.arguments.contains("--ignore-config"))
        #expect(invocation.arguments.contains("--no-playlist"))
        #expect(invocation.arguments.contains("--skip-download"))
        #expect(invocation.arguments.contains("--print"))
        #expect(invocation.arguments.contains(where: { $0.contains("{id,title,uploader") }))
    }

    @Test func badExitAndMalformedJSONBecomeHumanReadableFailures() async throws {
        let fixture = try MetadataResolverFixture()
        defer { fixture.remove() }
        let failed = YTDLPMetadataResolver(
            locator: fixture.locator,
            runner: MetadataRunner(result: SubprocessResult(
                exitCode: 1,
                terminationReason: .exit,
                standardOutput: [],
                standardError: ["private diagnostic"]
            ))
        )
        await #expect(throws: MetadataResolutionError.unavailable) {
            try await failed.resolve(try #require(URL(string: "https://example.com/video")))
        }

        let malformed = YTDLPMetadataResolver(
            locator: fixture.locator,
            runner: MetadataRunner(result: SubprocessResult(
                exitCode: 0,
                terminationReason: .exit,
                standardOutput: ["not-json"],
                standardError: []
            ))
        )
        await #expect(throws: MetadataResolutionError.invalidResponse) {
            try await malformed.resolve(try #require(URL(string: "https://example.com/video")))
        }
    }

    @Test func unsafeThumbnailAndInvalidDurationAreDroppedWithoutLosingTheTitle() async throws {
        let fixture = try MetadataResolverFixture()
        defer { fixture.remove() }
        let resolver = YTDLPMetadataResolver(
            locator: fixture.locator,
            runner: MetadataRunner(result: SubprocessResult(
                exitCode: 0,
                terminationReason: .exit,
                standardOutput: [
                    #"{"title":"Video","duration":-2,"thumbnail":"file:///tmp/private.jpg"}"#,
                ],
                standardError: []
            ))
        )

        let metadata = try await resolver.resolve(
            try #require(URL(string: "https://example.com/video"))
        )
        #expect(metadata.title == "Video")
        #expect(metadata.durationSeconds == nil)
        #expect(metadata.thumbnailURL == nil)
    }
}

private actor MetadataRunner: ProcessRunning {
    let result: SubprocessResult
    private var invocation: ProcessInvocation?

    init(result: SubprocessResult) {
        self.result = result
    }

    func run(
        _ invocation: ProcessInvocation,
        timeout: Duration?,
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void
    ) async throws -> SubprocessResult {
        self.invocation = invocation
        return result
    }

    func lastInvocation() -> ProcessInvocation? {
        invocation
    }
}

private struct MetadataResolverFixture {
    let rootURL: URL
    let locator: BinaryLocator

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-metadata-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("yt-dlp"),
            withDestinationURL: URL(fileURLWithPath: "/bin/echo")
        )
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("deno"),
            withDestinationURL: URL(fileURLWithPath: "/bin/echo")
        )
        locator = BinaryLocator(
            environment: [:],
            fixedSearchDirectories: [rootURL],
            includeBundledTools: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
