import Foundation
import Testing
@testable import Vidindir

@Suite("Tool installation")
struct ToolInstallServiceTests {
    @Test func buildsDirectHomebrewInvocationForMissingTools() throws {
        let service = ToolInstallService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            environment: [:]
        )
        let invocation = try service.installationInvocation(for: [.deno, .ytDLP, .deno])

        #expect(invocation.executableURL.path == "/bin/echo")
        #expect(invocation.arguments == ["install", "--no-ask", "yt-dlp", "deno"])
        #expect(invocation.environment?["HOMEBREW_NO_ASK"] == "1")
        #expect(invocation.environment?["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
        #expect(invocation.environment?["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1")
        #expect(invocation.environment?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(invocation.environment?["HOMEBREW_NO_ANALYTICS"] == "1")
    }

    @Test func allThreeToolsAreRequired() {
        let availability = ToolAvailability(
            ytDLP: URL(fileURLWithPath: "/yt-dlp"),
            ffmpeg: nil,
            deno: nil
        )
        #expect(!availability.canDownload)
        #expect(availability.missingRequiredTools == [.ffmpeg, .deno])
    }
}
