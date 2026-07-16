import Foundation
import Testing
@testable import Vidindir

@Suite("Download preferences")
struct DownloadPreferencesStoreTests {
    @Test func defaultsToMP4AndFallbackDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()

        #expect(store.selectedFormat == .mp4)
        #expect(store.destinationDirectory(for: .mp4) == fixture.temporaryRoot.standardizedFileURL)
    }

    @Test func persistsFormatAndSeparateDestinationBookmarks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let mp4Directory = fixture.temporaryRoot.appendingPathComponent("Video", isDirectory: true)
        let mp3Directory = fixture.temporaryRoot.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: mp4Directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mp3Directory, withIntermediateDirectories: true)

        let store = fixture.makeStore()
        try store.remember(format: .mp3, destinationDirectory: mp3Directory)
        try store.setDestinationDirectory(mp4Directory, for: .mp4)

        let reloaded = fixture.makeStore()
        #expect(reloaded.selectedFormat == .mp3)
        #expect(
            reloaded.destinationDirectory(for: .mp3).resolvingSymlinksInPath()
                == mp3Directory.resolvingSymlinksInPath()
        )
        #expect(
            reloaded.destinationDirectory(for: .mp4).resolvingSymlinksInPath()
                == mp4Directory.resolvingSymlinksInPath()
        )
    }

    @Test func deletedRememberedFolderFallsBack() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let selected = fixture.temporaryRoot.appendingPathComponent("Soon Deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let store = fixture.makeStore()
        try store.setDestinationDirectory(selected, for: .mp4)
        try FileManager.default.removeItem(at: selected)

        #expect(store.destinationDirectory(for: .mp4) == fixture.temporaryRoot.standardizedFileURL)
    }

    @Test func unknownStoredFormatMigratesToMP4() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("wav", forKey: "preferences.selectedFormat")
        #expect(fixture.makeStore().selectedFormat == .mp4)
    }
}

private struct Fixture {
    let defaults: UserDefaults
    let suiteName: String
    let temporaryRoot: URL

    init() throws {
        suiteName = "VidindirTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidindirPreferences-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    func makeStore() -> DownloadPreferencesStore {
        DownloadPreferencesStore(defaults: defaults, fallbackDirectory: temporaryRoot)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}
