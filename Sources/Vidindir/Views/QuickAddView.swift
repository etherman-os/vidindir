import SwiftUI
import VidindirDomain

struct QuickAddView: View {
    enum Action: String, CaseIterable, Identifiable {
        case saveOnly
        case downloadNow

        var id: String { rawValue }
        var title: String { self == .saveOnly ? "Save only" : "Download now" }
    }

    @ObservedObject var library: LibraryViewModel
    @ObservedObject var download: AppModel
    let initialLink: String
    let close: () -> Void
    @State private var linkText = ""
    @State private var action: Action = .saveOnly
    @State private var destination: SaveDestination = .inbox
    @State private var isWorking = false
    @State private var duplicateCandidates: [DuplicateCandidate] = []
    @State private var errorMessage: String?
    @State private var resolvedMetadata: ResolvedMediaMetadata?
    @State private var isResolvingMetadata = false
    @State private var metadataMessage: String?
    @FocusState private var linkIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Media")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Paste a media link…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($linkIsFocused)
                    .onSubmit { submit(allowDuplicate: false) }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if parsedInput.isBatch, parsedInput.isValid {
                batchPreview
            } else if isResolvingMetadata || resolvedMetadata != nil || metadataMessage != nil {
                metadataPreview
            }

            if !duplicateCandidates.isEmpty {
                duplicateNotice
            }

            Divider()

            Form {
                LabeledContent("Save to") {
                    VStack(alignment: .leading, spacing: 3) {
                        Picker("Save to", selection: $destination) {
                            Label("Inbox — organize later", systemImage: "tray")
                                .tag(SaveDestination.inbox)
                            Label("All Media — skip Inbox", systemImage: "rectangle.stack")
                                .tag(SaveDestination.libraryOnly)
                            if !userCollections.isEmpty {
                                Divider()
                                ForEach(userCollections) { collection in
                                    Label(collection.name, systemImage: "folder")
                                        .tag(SaveDestination.collection(collection.id))
                                }
                            }
                        }
                        .labelsHidden()

                        Text(destinationExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Picker("Action", selection: $action) {
                    ForEach(Action.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                if action == .downloadNow {
                    Picker("Format", selection: formatBinding) {
                        Label("Video", systemImage: "film").tag(DownloadFormat.mp4)
                        Label("Audio", systemImage: "waveform").tag(DownloadFormat.mp3)
                    }
                    .pickerStyle(.segmented)

                    if download.selectedFormat == .mp4 {
                        Picker("Quality", selection: qualityBinding) {
                            ForEach(DownloadQuality.allCases) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    LabeledContent("Save file to") {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(download.destinationDirectory.lastPathComponent)
                                .lineLimit(1)
                            Button("Choose…", action: download.chooseDestinationDirectory)
                        }
                    }
                }
            }
            .formStyle(.columns)

            Divider()

            HStack {
                if action == .downloadNow, !download.engineStatus.isReady {
                    Label("The download engine needs setup first.", systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit(allowDuplicate: false)
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(submitButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(VidindirTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!parsedInput.isValid || isWorking)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            if linkText.isEmpty, !initialLink.isEmpty {
                linkText = initialLink
            } else if linkText.isEmpty,
                      let clipboard = NSPasteboard.general.string(forType: .string),
                      QuickAddInput.parse(clipboard).isValid {
                linkText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async { linkIsFocused = true }
        }
        .task(id: linkText) {
            await resolveCurrentLink()
        }
    }

    private var batchPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(parsedInput.urls.count) links ready", systemImage: "link")
                .font(.subheadline.weight(.medium))
            Text(batchPreviewMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if parsedInput.duplicateTokenCount > 0 {
                Text("\(parsedInput.duplicateTokenCount) repeated pasted link\(parsedInput.duplicateTokenCount == 1 ? "" : "s") will only be handled once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var duplicateNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Already in your library", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Existing") {
                    if let first = duplicateCandidates.first {
                        library.destination = .library
                        library.selectedMediaItemID = first.mediaItem.id
                    }
                    close()
                }
                .buttonStyle(.borderless)
                Button("Add Anyway") { submit(allowDuplicate: true) }
                    .buttonStyle(.borderless)
            }
            if let first = duplicateCandidates.first {
                Text(first.mediaItem.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var metadataPreview: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                if let thumbnailURL = resolvedMetadata?.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if isResolvingMetadata {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if let metadata = resolvedMetadata {
                    Text(metadata.title ?? "Video details unavailable")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        if let creator = metadata.creator { Text(creator) }
                        if let duration = LibraryBrowserView.duration(metadata.durationSeconds) {
                            if metadata.creator != nil { Text("·") }
                            Text(duration).monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if isResolvingMetadata {
                    Text("Inspecting the link…")
                        .font(.subheadline.weight(.medium))
                    Text("You can still save it without waiting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let metadataMessage {
                    Text("Video details unavailable")
                        .font(.subheadline.weight(.medium))
                    Text(metadataMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var userCollections: [Collection] {
        library.collections.filter { $0.kind == .user }
    }

    private var destinationExplanation: String {
        switch destination {
        case .inbox:
            "Inbox is a temporary review list. The link is also saved in All Media."
        case .libraryOnly:
            "Save permanently without adding it to the Inbox review list."
        case .collection:
            "Save permanently and organize it in this collection now."
        }
    }

    private var parsedInput: QuickAddInput {
        QuickAddInput.parse(linkText)
    }

    private var singleURL: URL? {
        guard parsedInput.isValid, parsedInput.urls.count == 1 else { return nil }
        return parsedInput.urls[0]
    }

    private var validationMessage: String? {
        guard !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsedInput.invalidTokenCount > 0 else { return nil }
        return "Paste complete http(s) links separated by spaces or new lines."
    }

    private var batchPreviewMessage: String {
        switch action {
        case .saveOnly:
            "New links will be saved together. Links already in your library will not be duplicated. Details fill in after adding."
        case .downloadNow:
            "New links will be saved, existing library links will be reused, and the resulting items will enter the download queue."
        }
    }

    private var submitButtonTitle: String {
        guard parsedInput.isBatch else {
            return action == .saveOnly ? "Add" : "Add & Download"
        }
        switch action {
        case .saveOnly:
            return "Add \(parsedInput.urls.count) Links"
        case .downloadNow:
            return "Add & Download \(parsedInput.urls.count)"
        }
    }

    private var formatBinding: Binding<DownloadFormat> {
        Binding(
            get: { download.selectedFormat },
            set: { download.selectFormat($0) }
        )
    }

    private var qualityBinding: Binding<DownloadQuality> {
        Binding(
            get: { download.selectedQuality },
            set: { download.selectQuality($0) }
        )
    }

    private func submit(allowDuplicate: Bool) {
        guard parsedInput.isValid, !isWorking else { return }
        if parsedInput.isBatch {
            submitBatch()
            return
        }
        guard let url = singleURL else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let result = try await library.addLink(
                    url,
                    destination: destination,
                    allowDuplicate: allowDuplicate,
                    metadata: resolvedMetadata
                )
                switch result {
                case .duplicate(let candidates):
                    duplicateCandidates = candidates
                    isWorking = false
                case .saved:
                    if action == .downloadNow {
                        download.linkText = url.absoluteString
                        library.destination = .activeDownloads
                        download.startDownload()
                    }
                    close()
                }
            } catch {
                isWorking = false
                errorMessage = "Vidindir could not save this link. Check the address and try again."
            }
        }
    }

    private func submitBatch() {
        let urls = parsedInput.urls
        let selectedAction = action
        let selectedDestination = destination
        isWorking = true
        errorMessage = nil
        duplicateCandidates = []

        Task {
            let result = await library.addLinks(urls, destination: selectedDestination)
            isWorking = false

            if selectedAction == .downloadNow, !result.downloadItems.isEmpty {
                library.destination = .activeDownloads
                download.startDownloads(result.downloadItems)
            }

            if let alert = batchResultAlert(result, action: selectedAction) {
                library.alert = alert
            }
            close()
        }
    }

    private func batchResultAlert(_ result: BatchAddResult, action: Action) -> AppAlert? {
        let addedCount = result.addedItems.count
        let failedCount = result.failedURLs.count

        switch action {
        case .saveOnly:
            guard result.duplicateCount > 0 || failedCount > 0 else { return nil }
            var details: [String] = []
            if result.duplicateCount > 0 {
                details.append("\(result.duplicateCount) already in your library")
            }
            if failedCount > 0 {
                details.append("\(failedCount) could not be saved")
            }
            return AppAlert(
                title: addedCount == 0
                    ? "No New Links Added"
                    : "Added \(addedCount) Link\(addedCount == 1 ? "" : "s")",
                message: details.joined(separator: "; ") + "."
            )
        case .downloadNow:
            guard failedCount > 0 else { return nil }
            return AppAlert(
                title: result.downloadItems.isEmpty ? "No Downloads Queued" : "Some Links Could Not Be Added",
                message: "\(failedCount) link\(failedCount == 1 ? "" : "s") could not be saved. The remaining items can continue through the download queue."
            )
        }
    }

    private func resolveCurrentLink() async {
        resolvedMetadata = nil
        metadataMessage = nil
        isResolvingMetadata = false
        duplicateCandidates = []
        errorMessage = nil
        guard let url = singleURL else { return }
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            isResolvingMetadata = true
            let metadata = try await library.resolveMetadata(for: url)
            try Task.checkCancellation()
            resolvedMetadata = metadata
            isResolvingMetadata = false
        } catch is CancellationError {
            isResolvingMetadata = false
        } catch {
            isResolvingMetadata = false
            metadataMessage = (error as? LocalizedError)?.errorDescription
                ?? "Metadata is unavailable right now. You can still save the link."
        }
    }
}
