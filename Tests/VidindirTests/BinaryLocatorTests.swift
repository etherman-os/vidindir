import Foundation
import Testing
@testable import Vidindir

@Suite("Binary location")
struct BinaryLocatorTests {
    @Test func findsExecutableFromAbsolutePATHAndResolvesIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("yt-dlp")
        try makeExecutable(at: executable)

        let locator = BinaryLocator(
            environment: ["PATH": "relative::\(directory.path):\(directory.path)"],
            fixedSearchDirectories: [],
            includeBundledTools: false
        )

        #expect(locator.locate(.ytDLP) == executable.standardizedFileURL)
    }

    @Test func validOverrideWinsAndStaleOverrideFallsBack() throws {
        let directory = try makeTemporaryDirectory()
        let overrideDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: overrideDirectory)
        }
        let fallback = directory.appendingPathComponent("ffmpeg")
        let override = overrideDirectory.appendingPathComponent("custom-ffmpeg")
        try makeExecutable(at: fallback)
        try makeExecutable(at: override)

        let locator = BinaryLocator(
            environment: [:],
            fixedSearchDirectories: [directory],
            includeBundledTools: false
        )
        #expect(locator.locate(.ffmpeg, override: override) == override.standardizedFileURL)
        #expect(
            locator.locate(.ffmpeg, override: overrideDirectory.appendingPathComponent("missing"))
                == fallback.standardizedFileURL
        )
    }

    @Test func ignoresDirectoryNamedLikeBinary() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("deno"),
            withIntermediateDirectories: false
        )
        let locator = BinaryLocator(
            environment: [:],
            fixedSearchDirectories: [directory],
            includeBundledTools: false
        )
        #expect(locator.locate(.deno) == nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidindirTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(at url: URL) throws {
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data("#!/bin/sh\n".utf8)
        )
        #expect(created)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
