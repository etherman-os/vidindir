import Testing
@testable import Vidindir

@Suite("Diagnostic redaction")
struct DiagnosticRedactorTests {
    @Test func stripsURLSecretsAndSensitiveHeaders() {
        let output = DiagnosticRedactor().redact(
            "GET https://example.com/watch?v=private&token=hidden#part Authorization: Bearer top-secret"
        )

        #expect(output == "GET https://example.com/watch Authorization: [REDACTED]")
        #expect(!output.contains("private"))
        #expect(!output.contains("top-secret"))
    }

    @Test func masksAssignmentsCookiesAndCommandOptions() {
        let output = DiagnosticRedactor().redact(
            "token=abc api_key:xyz Cookie: session=secret\n--password hunter2"
        )

        #expect(output.contains("token=[REDACTED]"))
        #expect(output.contains("api_key=[REDACTED]"))
        #expect(output.contains("Cookie: [REDACTED]"))
        #expect(output.contains("--password [REDACTED]"))
        #expect(!output.contains("hunter2"))
    }

    @Test func boundsThePublishedText() {
        let output = DiagnosticRedactor().redact(
            String(repeating: "x", count: 1_000),
            maximumLength: 40
        )
        #expect(output.count == 40)
    }
}
