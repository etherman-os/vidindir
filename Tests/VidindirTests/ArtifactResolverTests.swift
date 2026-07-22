import Foundation
import Testing
@testable import Vidindir

@Suite("Artifact resolution")
struct ArtifactResolverTests {
    @Test func resolvesRelativeAndAbsolutePathsInsideDestination() throws {
        let destination = URL(fileURLWithPath: "/tmp/Vidindir Downloads", isDirectory: true)
        let resolver = ArtifactResolver()

        #expect(
            try resolver.resolve(path: "Artist/Song.mp3", inside: destination).path
                == "/tmp/Vidindir Downloads/Artist/Song.mp3"
        )
        #expect(
            try resolver.resolve(path: "/tmp/Vidindir Downloads/Video.mp4", inside: destination).path
                == "/tmp/Vidindir Downloads/Video.mp4"
        )
    }

    @Test func rejectsTraversalAndSiblingPrefix() {
        let destination = URL(fileURLWithPath: "/tmp/download", isDirectory: true)
        let resolver = ArtifactResolver()

        #expect(throws: ArtifactResolverError.outsideDestination) {
            try resolver.resolve(path: "../escape.mp4", inside: destination)
        }
        #expect(throws: ArtifactResolverError.outsideDestination) {
            try resolver.resolve(path: "/tmp/downloader/escape.mp4", inside: destination)
        }
    }

    @Test func rejectsASymlinkThatEscapesTheDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidindirArtifactResolver-\(UUID().uuidString)")
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        #expect(throws: ArtifactResolverError.outsideDestination) {
            try ArtifactResolver().resolve(
                path: "escape/video.mp4",
                inside: destination
            )
        }
    }
}
