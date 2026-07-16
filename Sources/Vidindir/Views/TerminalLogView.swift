import AppKit
import SwiftUI

struct TerminalLogView: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    Text(model.processLog.isEmpty ? "No output yet." : model.processLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.84))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 150)
                .background(Color(red: 0.07, green: 0.09, blue: 0.085), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Spacer()
                    Button("Copy Log", action: model.copyProcessLog)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Process Details", systemImage: "terminal")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 4)
    }
}
