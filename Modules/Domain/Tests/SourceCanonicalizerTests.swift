import Foundation
import Testing
@testable import VidindirDomain

@Suite("Source canonicalization")
struct SourceCanonicalizerTests {
    private let canonicalizer = SourceCanonicalizer()

    @Test func youtubeShortsAndWatchURLsShareAnIdentity() throws {
        let short = try canonicalizer.canonicalize(try #require(URL(
            string: "https://youtube.com/shorts/OpeV9uFQcGg?si=DtvxWBZOFToIeZpd"
        )))
        let watch = try canonicalizer.canonicalize(try #require(URL(
            string: "https://www.youtube.com/watch?v=OpeV9uFQcGg&t=3"
        )))

        #expect(short.sourceType == .youtube)
        #expect(short.sourceMediaID == "OpeV9uFQcGg")
        #expect(short.canonicalURL?.absoluteString ==
            "https://www.youtube.com/watch?v=OpeV9uFQcGg")
        #expect(short.sourceMediaID == watch.sourceMediaID)
        #expect(short.canonicalURL == watch.canonicalURL)
    }

    @Test func xAndTwitterStatusURLsShareAnIdentity() throws {
        let x = try canonicalizer.canonicalize(try #require(URL(
            string: "https://x.com/someone/status/1234567890?s=20"
        )))
        let twitter = try canonicalizer.canonicalize(try #require(URL(
            string: "https://twitter.com/another/status/1234567890"
        )))

        #expect(x.sourceType == .x)
        #expect(x.sourceMediaID == "1234567890")
        #expect(x.canonicalURL?.absoluteString == "https://x.com/i/status/1234567890")
        #expect(x.canonicalURL == twitter.canonicalURL)
    }

    @Test func genericURLsRemainIntactWithoutRiskyNormalization() throws {
        let url = try #require(URL(string:
            "https://example.com/media?token=signed-value#chapter-2"
        ))
        let result = try canonicalizer.canonicalize(url)

        #expect(result.sourceURL == url)
        #expect(result.canonicalURL == nil)
        #expect(result.sourceType == .generic)
        #expect(result.sourceMediaID == nil)
    }

    @Test func rejectsNonHTTPURLs() throws {
        let fileURL = try #require(URL(string: "file:///tmp/movie.mp4"))
        #expect(throws: LibraryDomainError.invalidSourceURL) {
            try canonicalizer.canonicalize(fileURL)
        }
    }
}
