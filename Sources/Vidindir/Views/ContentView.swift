import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            RadialGradient(
                colors: [VidindirTheme.accent.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    DownloadFormView(model: model)

                    if model.shouldShowToolSetup {
                        ToolSetupView(model: model)
                    }

                    if model.phase != .idle {
                        DownloadStatusView(model: model)
                    }

                    if !model.history.isEmpty {
                        HistoryView(model: model)
                    }

                    if !model.processLog.isEmpty || model.phase.isBusy {
                        TerminalLogView(model: model)
                    }

                    footer
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 620, idealHeight: 760)
        .sheet(isPresented: $model.showsResponsibleUse) {
            ResponsibleUseView(accept: model.acceptResponsibleUse)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onAppear(perform: model.bootstrap)
    }

    private var header: some View {
        HStack(spacing: 15) {
            VidindirMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("Vidindir")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("From link to file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            toolStatus
        }
    }

    @ViewBuilder
    private var toolStatus: some View {
        if model.isCheckingEngineUpdates {
            Label("Updating Engine…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.09), in: Capsule())
        } else if model.engineStatus.isReady {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(VidindirTheme.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VidindirTheme.success.opacity(0.09), in: Capsule())
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("Independent, local, and open source")
                .font(.caption.weight(.medium))
            Text("Powered by yt-dlp · FFmpeg · Deno")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if model.engineStatus.isReady || model.engineUpdateResult != nil {
                Text(model.engineUpdateMessage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 5) {
                Link("Built by etherman-os", destination: URL(string: "https://github.com/etherman-os")!)
                Text("·")
                    .foregroundStyle(.tertiary)
                Link("etherman.org", destination: URL(string: "https://etherman.org")!)
            }
            .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}
