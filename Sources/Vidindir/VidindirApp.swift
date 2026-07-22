import SwiftUI
import VidindirDomain
import VidindirPersistence

@main
struct VidindirApp: App {
    @StateObject private var model: AppModel
    @StateObject private var library: LibraryViewModel
    @StateObject private var appUpdater: AppUpdateController

    init() {
        let defaults = UserDefaults.standard
        let downloadBackend = YTDLPBackend()
        let persistence = Self.makePersistenceComponents(
            defaults: defaults,
            downloadBackend: downloadBackend
        )
        let model = AppModel(
            downloadBackend: downloadBackend,
            engineManager: HomebrewDownloadEngineManager(),
            defaults: defaults,
            downloadCoordinator: persistence.coordinator
        )
        _model = StateObject(wrappedValue: model)
        _library = StateObject(wrappedValue: persistence.library)
        _appUpdater = StateObject(wrappedValue: AppUpdateController(
            activityProvider: model
        ))
    }

    var body: some Scene {
        WindowGroup("Vidindir") {
            ContentView(model: model, library: library)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Link…") {
                    library.isQuickAddPresented = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("New Media Item…") {
                    library.isQuickAddPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
            }

            CommandMenu("Download") {
                Button("Paste Link") {
                    model.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Start Download") {
                    model.startDownload()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canStartDownload)

                Button("Cancel Download") {
                    model.cancelDownload()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.phase.isBusy)

                Divider()

                Button("Refresh Engine Status") {
                    model.refreshEngineStatus()
                }

                Button("Update Download Engine Now…") {
                    model.updateEngineNow()
                }
                .disabled(
                    model.phase.isBusy
                        || model.hasPendingDownloads
                        || model.isInstallingTools
                        || model.isCheckingEngineUpdates
                )
            }
        }

        Settings {
            SettingsView(model: model, appUpdater: appUpdater)
        }
    }

    @MainActor
    private static func makePersistenceComponents(
        defaults: UserDefaults,
        downloadBackend: any DownloadBackend
    ) -> (library: LibraryViewModel, coordinator: DownloadCoordinator?) {
        let deviceID: DeviceID
        let deviceKey = "library.currentDeviceID"
        if let value = defaults.string(forKey: deviceKey),
           let storedID = DeviceID(uuidString: value) {
            deviceID = storedID
        } else {
            let newID = DeviceID()
            defaults.set(newID.description, forKey: deviceKey)
            deviceID = newID
        }

        do {
            let database = try LibraryDatabase(
                url: LibraryDatabase.defaultURL(),
                configuration: LibraryDatabaseConfiguration(
                    currentDeviceID: deviceID,
                    deviceDisplayName: Host.current().localizedName ?? "This Mac",
                    appVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String
                )
            )
            let libraryRepository = GRDBLibraryRepository(database: database)
            let downloadRepository = GRDBDownloadJobRepository(database: database)
            let importer = LegacyHistoryImporter(database: database)
            let metadataResolver = YTDLPMetadataResolver()
            return (
                LibraryViewModel(
                    libraryRepository: libraryRepository,
                    downloadRepository: downloadRepository,
                    legacyImporter: importer,
                    legacyHistoryData: defaults.data(
                        forKey: LegacyHistoryImporter.userDefaultsKey
                    ),
                    metadataResolver: metadataResolver
                ),
                DownloadCoordinator(
                    libraryRepository: libraryRepository,
                    downloadRepository: downloadRepository,
                    backend: downloadBackend,
                    metadataResolver: metadataResolver
                )
            )
        } catch {
            return (
                LibraryViewModel(
                    libraryRepository: nil,
                    downloadRepository: nil,
                    legacyImporter: nil,
                    legacyHistoryData: nil,
                    startupError: "Vidindir could not open its local library. The existing database was left untouched so it can be retried safely."
                ),
                nil
            )
        }
    }
}
