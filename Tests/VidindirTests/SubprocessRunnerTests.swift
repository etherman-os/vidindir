import Foundation
import Testing
@testable import Vidindir

@Suite("Subprocess execution")
struct SubprocessRunnerTests {
    @Test func drainsStdoutAndStderrIncludingFinalNewlineLessText() async throws {
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out\\nlast'; printf 'warning\\nend' >&2"]
        )
        let result = try await SubprocessRunner().run(invocation)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == ["out", "last"])
        #expect(result.standardError == ["warning", "end"])
    }

    @Test func returnsNonzeroExitCodeWithoutDiscardingOutput() async throws {
        let result = try await SubprocessRunner().run(ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf failure >&2; exit 7"]
        ))

        #expect(result.exitCode == 7)
        #expect(result.standardError == ["failure"])
    }
}
