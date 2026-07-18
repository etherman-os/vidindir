import SwiftUI

@main
struct VidindirApp: App {
    @StateObject private var model: AppModel
    @StateObject private var appUpdater: AppUpdateController

    init() {
        let model = AppModel(
            downloadBackend: YTDLPBackend(),
            engineManager: HomebrewDownloadEngineManager()
        )
        _model = StateObject(wrappedValue: model)
        _appUpdater = StateObject(wrappedValue: AppUpdateController(
            activityProvider: model
        ))
    }

    var body: some Scene {
        WindowGroup("Vidindir") {
            ContentView(model: model)
        }
        .defaultSize(width: 700, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
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
                        || model.isInstallingTools
                        || model.isCheckingEngineUpdates
                )
            }
        }
    }
}
