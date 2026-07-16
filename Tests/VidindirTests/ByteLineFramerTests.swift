import Foundation
import Testing
@testable import Vidindir

@Suite("Byte line framing")
struct ByteLineFramerTests {
    @Test func framesMultipleLinesAndFlushesFinalLine() throws {
        var framer = ByteLineFramer()

        #expect(try framer.append(Data("one\r\ntwo\npartial".utf8)) == ["one", "two"])
        #expect(try framer.finish() == ["partial"])
        #expect(try framer.finish() == [])
    }

    @Test func preservesUnicodeAtEveryPossibleChunkBoundary() throws {
        let expected = "Vidindir 🌊 — naïve café.mp4"
        let bytes = Data((expected + "\n").utf8)

        for splitIndex in 0...bytes.count {
            var framer = ByteLineFramer()
            var lines: [String] = []
            lines += try framer.append(bytes.prefix(splitIndex))
            lines += try framer.append(bytes.suffix(bytes.count - splitIndex))
            lines += try framer.finish()
            #expect(lines == [expected], "Failed at byte split \(splitIndex)")
        }
    }

    @Test func boundsNewlineLessOutputAndRecovers() throws {
        var framer = ByteLineFramer(maximumLineLength: 4)
        #expect(throws: ByteLineFramerError.lineTooLong(limit: 4)) {
            try framer.append(Data("12345".utf8))
        }
        #expect(try framer.append(Data("ok\n".utf8)) == ["ok"])
    }
}
