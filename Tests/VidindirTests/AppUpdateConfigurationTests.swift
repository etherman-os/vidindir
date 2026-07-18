import Foundation
import Testing
@testable import Vidindir

@Suite("App update configuration")
struct AppUpdateConfigurationTests {
    private let validKey = Data(repeating: 7, count: 32).base64EncodedString()

    @Test("accepts an HTTPS feed and Ed25519 public key")
    func acceptsSecureConfiguration() throws {
        let configuration = try #require(AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://github.com/etherman-os/vidindir/releases/latest/download/appcast.xml",
            "SUPublicEDKey": validKey,
            "SUAllowsAutomaticUpdates": true,
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": true,
        ]))

        #expect(configuration.feedURL.scheme == "https")
        #expect(configuration.publicEDKey == validKey)
    }

    @Test("rejects an insecure feed")
    func rejectsHTTPFeed() {
        let configuration = AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "http://example.com/appcast.xml",
            "SUPublicEDKey": validKey,
            "SUAllowsAutomaticUpdates": true,
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": true,
        ])

        #expect(configuration == nil)
    }

    @Test("rejects a missing or malformed public key")
    func rejectsInvalidKey() {
        #expect(AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
        ]) == nil)

        #expect(AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 7, count: 31).base64EncodedString(),
            "SUAllowsAutomaticUpdates": true,
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": true,
        ]) == nil)
    }

    @Test("rejects a feed without strict verification and automatic checks")
    func rejectsIncompleteSecurityPolicy() {
        let base: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": validKey,
            "SUAllowsAutomaticUpdates": true,
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": true,
        ]

        for requiredFlag in [
            "SUAllowsAutomaticUpdates",
            "SURequireSignedFeed",
            "SUVerifyUpdateBeforeExtraction",
            "SUEnableAutomaticChecks",
            "SUAutomaticallyUpdate",
        ] {
            var weakened = base
            weakened[requiredFlag] = false
            #expect(AppUpdateConfiguration(infoDictionary: weakened) == nil)
        }
    }
}
