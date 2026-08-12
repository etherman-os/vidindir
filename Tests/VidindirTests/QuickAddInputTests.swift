import Foundation
import Testing
@testable import Vidindir

@Suite("Quick Add input parsing")
struct QuickAddInputTests {
    @Test func parsesWhitespaceSeparatedLinksInOrderAndDeduplicatesExactRepeats() throws {
        let input = QuickAddInput.parse("""
            https://example.com/one
            https://example.com/two https://example.com/one
            """)

        #expect(input.urls.map(\.absoluteString) == [
            "https://example.com/one",
            "https://example.com/two",
        ])
        #expect(input.invalidTokenCount == 0)
        #expect(input.duplicateTokenCount == 1)
        #expect(input.isValid)
        #expect(input.isBatch)
    }

    @Test func rejectsMixedTextInsteadOfSilentlyDroppingIt() {
        let input = QuickAddInput.parse("https://example.com/one not-a-link https://example.com/two")

        #expect(input.urls.map(\.absoluteString) == [
            "https://example.com/one",
            "https://example.com/two",
        ])
        #expect(input.invalidTokenCount == 1)
        #expect(!input.isValid)
    }

    @Test func acceptsOnlyHTTPAndHTTPSLinks() {
        let input = QuickAddInput.parse("ftp://example.com/file https://example.com/video")

        #expect(input.urls.map(\.absoluteString) == ["https://example.com/video"])
        #expect(input.invalidTokenCount == 1)
        #expect(!input.isValid)
    }
}
