import SwiftUI

struct ToolSetupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.13))
                Image(systemName: model.isInstallingTools ? "gearshape.2" : "wrench.and.screwdriver")
                    .foregroundStyle(.orange)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.engineSetupTitle)
                    .font(.headline)

                if model.isInstallingTools {
                    Text(model.toolInstallStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.top, 3)
                } else {
                    Text(model.missingToolsDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(model.engineSetupActionLabel) {
                            if model.canPrepareEngine {
                                model.prepareEngine()
                            } else {
                                model.openEngineSetupGuide()
                            }
                        }
                        .buttonStyle(.bordered)

                        if model.requiresManualEngineRepair,
                           model.canPrepareEngine {
                            Button("Open Setup Guide") {
                                model.openEngineSetupGuide()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .vidindirCard()
    }
}
