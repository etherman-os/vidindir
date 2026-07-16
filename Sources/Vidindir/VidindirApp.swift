import SwiftUI

@main
struct VidindirApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel(
            downloadBackend: YTDLPBackend(),
            engineManager: HomebrewDownloadEngineManager()
        ))
    }

    var body: some Scene {
        WindowGroup("Vidindir") {
            ContentView(model: model)
        }
        .defaultSize(width: 700, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
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
            }
        }
    }
}
