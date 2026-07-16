import Testing
@testable import Vidindir

@Suite("yt-dlp event decoding")
struct YTDLPEventDecoderTests {
    private let decoder = YTDLPEventDecoder()

    @Test func decodesProgressWithLossyNumbers() throws {
        let line = YTDLPEventDecoder.sentinel + #"{"event":"progress","status":"downloading","downloadedBytes":"50","totalBytes":null,"estimatedTotalBytes":"100.0","speed":"12.5","eta":"NA","filename":"Vidindir 🌊.mp4"}"#

        guard case .event(.progress(let progress)) = decoder.decode(line: line) else {
            Issue.record("Expected progress event")
            return
        }
        #expect(progress.status == "downloading")
        #expect(progress.downloadedBytes == 50)
        #expect(progress.totalBytes == nil)
        #expect(progress.estimatedTotalBytes == 100)
        #expect(progress.speedBytesPerSecond == 12.5)
        #expect(progress.etaSeconds == nil)
        #expect(progress.filename == "Vidindir 🌊.mp4")
        #expect(progress.fractionCompleted == 0.5)
    }

    @Test func decodesArtifactAndPreservesEscapedCharacters() {
        let line = YTDLPEventDecoder.sentinel + #"{"event":"artifact","path":"/tmp/quote \" and %\t.mp3"}"#
        #expect(
            decoder.decode(line: line)
                == .event(.artifact(path: "/tmp/quote \" and %\t.mp3"))
        )
    }

    @Test func separatesLogsMalformedAndUnknownEvents() {
        #expect(decoder.decode(line: "WARNING: hello") == .log("WARNING: hello"))
        #expect(
            decoder.decode(line: YTDLPEventDecoder.sentinel + "{")
                == .malformed(payload: "{")
        )

        let payload = #"{"event":"futureEvent","extra":42}"#
        #expect(
            decoder.decode(line: YTDLPEventDecoder.sentinel + payload)
                == .event(.unknown(name: "futureEvent", payload: payload))
        )
    }

    @Test func progressFractionIsClampedAndZeroTotalIsIndeterminate() {
        #expect(YTDLPProgress(downloadedBytes: 200, totalBytes: 100).fractionCompleted == 1)
        #expect(YTDLPProgress(downloadedBytes: 1, totalBytes: 0).fractionCompleted == nil)
    }
}
