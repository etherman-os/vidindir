import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var appUpdater: AppUpdateController
    @AppStorage("integrations.clipboardSuggestions") private var clipboardSuggestions = true

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            downloads
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            engine
                .tabItem { Label("Engine", systemImage: "wrench.and.screwdriver") }
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 610, height: 440)
        .padding(18)
    }

    private var general: some View {
        Form {
            Section("Updates") {
                LabeledContent("Vidindir") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("Automatic updates enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(VidindirTheme.success)
                        Text("Checked daily in the background")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Check for App Updates…") { appUpdater.checkForUpdates() }
            }

            Section("Library") {
                LabeledContent("Storage") {
                    Text("Local SQLite database")
                        .foregroundStyle(.secondary)
                }
                Text("Links and organization remain available offline. Downloaded media files stay separate from library records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Suggest copied media links", isOn: $clipboardSuggestions)
                Text("When enabled, Vidindir checks the clipboard only while the app is active. Clipboard contents are never uploaded to Vidindir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var downloads: some View {
        Form {
            Section("Default Download") {
                Picker("Format", selection: formatBinding) {
                    Text("Video (MP4)").tag(DownloadFormat.mp4)
                    Text("Audio (MP3)").tag(DownloadFormat.mp3)
                }
                if model.selectedFormat == .mp4 {
                    Picker("Quality", selection: qualityBinding) {
                        ForEach(DownloadQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                }
                LabeledContent("Folder") {
                    HStack {
                        Text(model.destinationDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: model.chooseDestinationDirectory)
                    }
                }
            }

            Section {
                Text("Vidindir remembers a separate folder and quality preference for each format on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var engine: some View {
        Form {
            Section("Download Engine") {
                LabeledContent("Status") {
                    Label(
                        model.engineStatus.isReady ? "Ready" : "Needs attention",
                        systemImage: model.engineStatus.isReady
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.engineStatus.isReady ? VidindirTheme.success : .orange)
                }
                LabeledContent("Automatic maintenance") {
                    Text("Enabled · checked daily")
                        .foregroundStyle(.secondary)
                }
                Text(model.engineUpdateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Refresh Status", action: model.refreshEngineStatus)
                    Button("Update Engine Now…", action: model.updateEngineNow)
                        .disabled(
                            model.phase.isBusy
                                || model.isInstallingTools
                                || model.isCheckingEngineUpdates
                        )
                    if !model.engineStatus.isReady {
                        Button(model.engineSetupActionLabel, action: model.prepareEngine)
                            .buttonStyle(.borderedProminent)
                            .tint(VidindirTheme.accent)
                    }
                }
            }

            Section("Components") {
                LabeledContent("Metadata & downloads", value: "yt-dlp")
                LabeledContent("Media processing", value: "FFmpeg")
                LabeledContent("Extractor runtime", value: "Deno")
                Text("Updates never delete your library or downloaded media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("Vidindir is privacy-first") {
                privacyRow("No analytics", "chart.bar.xaxis")
                privacyRow("No tracking", "eye.slash")
                privacyRow("No ads", "rectangle.slash")
                privacyRow("No mandatory account", "person.crop.circle.badge.xmark")
                privacyRow("Local-first and open source", "lock.open")
            }

            Section {
                Text("Media links are processed on this Mac and sent only to the source service needed to inspect or download them. Vidindir does not operate a URL-collection server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 16) {
            VidindirMark(size: 72)
            VStack(spacing: 4) {
                Text("Vidindir")
                    .font(.title.weight(.bold))
                Text("Save. Organize. Download.")
                    .foregroundStyle(.secondary)
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Link("Built by etherman-os", destination: URL(string: "https://github.com/etherman-os")!)
                Text("·").foregroundStyle(.tertiary)
                Link("etherman.org", destination: URL(string: "https://etherman.org")!)
            }
            Text("Open source under the MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 35)
    }

    private func privacyRow(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(.primary)
    }

    private var formatBinding: Binding<DownloadFormat> {
        Binding(
            get: { model.selectedFormat },
            set: { model.selectFormat($0) }
        )
    }

    private var qualityBinding: Binding<DownloadQuality> {
        Binding(
            get: { model.selectedQuality },
            set: { model.selectQuality($0) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }
}
