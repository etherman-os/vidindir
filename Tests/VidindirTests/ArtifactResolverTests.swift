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
}
