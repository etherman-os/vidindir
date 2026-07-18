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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                VidindirMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Media")
                        .font(.title2.weight(.semibold))
                    Text("Save a media link to your local library.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                TextField("Paste a video link…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .focused($linkIsFocused)
                    .onSubmit { submit(allowDuplicate: false) }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if isResolvingMetadata || resolvedMetadata != nil || metadataMessage != nil {
                metadataPreview
            }

            if !duplicateCandidates.isEmpty {
                duplicateNotice
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 13) {
                GridRow {
                    Text("Save to")
                        .foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Text(destinationExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GridRow {
                    Text("Action")
                        .foregroundStyle(.secondary)
                    Picker("Action", selection: $action) {
                        ForEach(Action.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if action == .downloadNow {
                    GridRow {
                        Text("Format")
                            .foregroundStyle(.secondary)
                        Picker("Format", selection: formatBinding) {
                            Label("Video", systemImage: "film").tag(DownloadFormat.mp4)
                            Label("Audio", systemImage: "waveform").tag(DownloadFormat.mp3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if download.selectedFormat == .mp4 {
                        GridRow {
                            Text("Quality")
                                .foregroundStyle(.secondary)
                            Picker("Quality", selection: qualityBinding) {
                                ForEach(DownloadQuality.allCases) { quality in
                                    Text(quality.displayName).tag(quality)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    GridRow {
                        Text("Save file to")
                            .foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "folder")
                            Text(download.destinationDirectory.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose…", action: download.chooseDestinationDirectory)
                        }
                    }
                }
            }

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
                        Text(action == .saveOnly ? "Add" : "Add & Download")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(VidindirTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(validURL == nil || isWorking)
            }
        }
        .padding(24)
        .frame(width: 570)
        .onAppear {
            if linkText.isEmpty, !initialLink.isEmpty {
                linkText = initialLink
            } else if linkText.isEmpty,
               let clipboard = NSPasteboard.general.string(forType: .string),
               Self.validHTTPURL(clipboard) != nil {
                linkText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async { linkIsFocused = true }
        }
        .task(id: linkText) {
            await resolveCurrentLink()
        }
    }

    private var duplicateNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Already in your library", systemImage: "rectangle.on.rectangle")
                .font(.headline)
            if let first = duplicateCandidates.first {
                Text(first.mediaItem.displayTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Button("Open Existing") {
                    if let first = duplicateCandidates.first {
                        library.destination = .library
                        library.selectedMediaItemID = first.mediaItem.id
                    }
                    close()
                }
                Button("Add Anyway") { submit(allowDuplicate: true) }
            }
        }
        .padding(13)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var metadataPreview: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.secondary.opacity(0.08))
                if let thumbnailURL = resolvedMetadata?.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(VidindirTheme.accent)
                        }
                    }
                } else if isResolvingMetadata {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(VidindirTheme.accent)
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                if let metadata = resolvedMetadata {
                    Text(metadata.title ?? "Video details unavailable")
                        .font(.headline)
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
        .padding(11)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
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

    private var validURL: URL? {
        Self.validHTTPURL(linkText)
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
        guard let url = validURL, !isWorking else { return }
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

    private static func validHTTPURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    private func resolveCurrentLink() async {
        resolvedMetadata = nil
        metadataMessage = nil
        isResolvingMetadata = false
        guard let url = validURL else { return }
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
