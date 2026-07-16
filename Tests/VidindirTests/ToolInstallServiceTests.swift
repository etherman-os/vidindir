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
        #expect(invocation.arguments == ["install", "yt-dlp", "deno"])
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
