import AppKit
import SwiftUI
import VidindirDomain

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: LibraryViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("library.displayMode") private var displayMode: LibraryDisplayMode = .grid
    @AppStorage("integrations.clipboardSuggestions") private var clipboardSuggestions = true
    @AppStorage("layout.inspectorPreferred") private var inspectorPreferred = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var windowWidth: CGFloat = 0
    @State private var inspectorPresented = false
    @State private var compactInspectorPresented = false
    @State private var didInitializeAdaptiveLayout = false
    @State private var inspectorWasAutomaticallyCollapsed = false
    @State private var sidebarWasAutomaticallyCollapsed = false
    @State private var quickAddInitialLink = ""
    @State private var detectedClipboardURL: URL?
    @State private var lastInspectedClipboardValue = ""
    @State private var compactSearchPresented = false
    @FocusState private var compactSearchFocused: Bool

    private let inspectorCollapseWidth: CGFloat = 1_080
    private let inspectorRestoreWidth: CGFloat = 1_160
    private let sidebarCollapseWidth: CGFloat = 720
    private let sidebarRestoreWidth: CGFloat = 800

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebarView(library: library)
                .navigationSplitViewColumnWidth(min: 176, ideal: 205, max: 248)
        } detail: {
            mainContent
                .navigationTitle(library.destinationTitle)
                .modifier(
                    AdaptiveToolbarSearch(
                        isEnabled: windowWidth >= 760,
                        text: $library.searchText
                    )
                )
                .toolbar { toolbar }
                .safeAreaInset(edge: .top, spacing: 0) {
                    topAccessories
                }
        }
        .inspector(isPresented: inspectorBinding) {
            MediaInspectorView(library: library, startDownload: startDownload)
                .inspectorColumnWidth(min: 236, ideal: 272, max: 326)
        }
        .frame(minWidth: 640, idealWidth: 1180, minHeight: 500, idealHeight: 760)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { adaptLayout(to: proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in
                        adaptLayout(to: width)
                    }
            }
        }
        .overlay { transientPanelOverlay }
        .sheet(isPresented: $model.showsResponsibleUse) {
            ResponsibleUseView(accept: model.acceptResponsibleUse)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $library.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            model.bootstrap()
            library.bootstrap()
            inspectClipboardIfNeeded()
        }
        .onChange(of: model.phase) {
            library.reload()
        }
        .onChange(of: model.downloadActivityRevision) {
            library.reload()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                inspectClipboardIfNeeded()
            } else {
                dismissTransientPanels()
            }
        }
        .onChange(of: library.isQuickAddPresented) {
            if !library.isQuickAddPresented {
                quickAddInitialLink = ""
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, Self.isHTTPURL(url) else { return false }
            presentQuickAdd(url: url)
            return true
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let url = URL(string: value),
                  Self.isHTTPURL(url) else { return false }
            presentQuickAdd(url: url)
            return true
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let startupError = library.startupError {
            ContentUnavailableView {
                Label("Library Unavailable", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(startupError)
            } actions: {
                Button("Try Again", action: library.reload)
            }
        } else if library.isDownloadDestination {
            DownloadsLibraryView(library: library, download: model)
        } else {
            LibraryBrowserView(
                library: library,
                displayMode: displayMode,
                startDownload: startDownload,
                startCollectionDownload: startCollectionDownload
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if windowWidth < 760 {
                Menu {
                    if !library.isDownloadDestination {
                        Picker("View", selection: $displayMode) {
                            ForEach(LibraryDisplayMode.allCases) { mode in
                                Label(mode.rawValue.capitalized, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                        Divider()
                    }

                    Button("Show Inspector…", systemImage: "sidebar.right") {
                        toggleInspector()
                    }
                    .disabled(!hasInspectorContent)

                    Divider()
                    Label(engineMenuTitle, systemImage: engineMenuSymbol)
                } label: {
                    Label("View Options", systemImage: "ellipsis.circle")
                }
                .help("View Options")

                Button {
                    compactSearchPresented.toggle()
                    if compactSearchPresented {
                        DispatchQueue.main.async { compactSearchFocused = true }
                    }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help(compactSearchPresented ? "Hide Search" : "Search Library")
            } else if !library.isDownloadDestination {
                if windowWidth >= 800 {
                    Picker("View", selection: $displayMode) {
                        ForEach(LibraryDisplayMode.allCases) { mode in
                            Image(systemName: mode.systemImage)
                                .help(mode.rawValue.capitalized)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 102)
                } else {
                    Menu {
                        Picker("View", selection: $displayMode) {
                            ForEach(LibraryDisplayMode.allCases) { mode in
                                Label(mode.rawValue.capitalized, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                    } label: {
                        Label("View", systemImage: displayMode.systemImage)
                    }
                    .help("Change View")
                }
            }

            Button {
                quickAddInitialLink = ""
                compactInspectorPresented = false
                library.isQuickAddPresented = true
            } label: {
                Label("Add Link", systemImage: "plus")
            }
            .help("Add Link (⌘L)")

            if windowWidth >= 760 {
                Button {
                    toggleInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }

    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorPresented },
            set: { value in
                guard windowWidth >= inspectorCollapseWidth else {
                    inspectorPresented = false
                    return
                }
                inspectorPresented = value
                inspectorPreferred = value
                inspectorWasAutomaticallyCollapsed = false
            }
        )
    }

    private var isInspectorVisible: Bool {
        windowWidth < inspectorCollapseWidth
            ? compactInspectorPresented
            : inspectorPresented
    }

    private var hasInspectorContent: Bool {
        library.selectedItem != nil || library.selectedJob != nil
    }

    private var engineMenuTitle: String {
        if model.isCheckingEngineUpdates { return "Engine update in progress" }
        return model.engineStatus.isReady ? "Download engine ready" : "Engine setup required"
    }

    private var engineMenuSymbol: String {
        if model.isCheckingEngineUpdates { return "arrow.triangle.2.circlepath" }
        return model.engineStatus.isReady ? "checkmark.circle.fill" : "wrench.and.screwdriver"
    }

    private func toggleInspector() {
        if windowWidth < inspectorCollapseWidth {
            if !compactInspectorPresented {
                library.isQuickAddPresented = false
            }
            compactInspectorPresented.toggle()
        } else {
            inspectorPresented.toggle()
            inspectorPreferred = inspectorPresented
            inspectorWasAutomaticallyCollapsed = false
        }
    }

    private func adaptLayout(to width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        windowWidth = width
        if width >= 760 {
            compactSearchPresented = false
        }

        if !didInitializeAdaptiveLayout {
            didInitializeAdaptiveLayout = true
            inspectorPresented = width >= inspectorCollapseWidth && inspectorPreferred
            inspectorWasAutomaticallyCollapsed = width < inspectorCollapseWidth
            if width < sidebarCollapseWidth {
                columnVisibility = .detailOnly
                sidebarWasAutomaticallyCollapsed = true
            }
            return
        }

        if width < inspectorCollapseWidth {
            if inspectorPresented {
                inspectorPresented = false
                inspectorWasAutomaticallyCollapsed = true
            }
        } else if width > inspectorRestoreWidth,
                  inspectorWasAutomaticallyCollapsed {
            inspectorPresented = inspectorPreferred
            inspectorWasAutomaticallyCollapsed = false
        }

        if width < sidebarCollapseWidth {
            if columnVisibility != .detailOnly {
                columnVisibility = .detailOnly
                sidebarWasAutomaticallyCollapsed = true
            }
        } else if width > sidebarRestoreWidth,
                  sidebarWasAutomaticallyCollapsed {
            columnVisibility = .all
            sidebarWasAutomaticallyCollapsed = false
        }
    }

    private func startDownload(_ item: LibraryItemSummary) {
        model.linkText = item.mediaItem.sourceURL.absoluteString
        library.destination = .activeDownloads
        model.startDownload(mediaItemID: item.id)
    }

    private func startCollectionDownload(_ items: [LibraryItemSummary]) {
        guard !items.isEmpty else { return }
        library.destination = .activeDownloads
        model.startDownloads(items)
    }

    @ViewBuilder
    private var transientPanelOverlay: some View {
        if library.isQuickAddPresented || compactInspectorPresented {
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissTransientPanels() }

                    Group {
                        if library.isQuickAddPresented {
                            QuickAddView(
                                library: library,
                                download: model,
                                initialLink: quickAddInitialLink,
                                close: dismissTransientPanels
                            )
                        } else {
                            MediaInspectorView(library: library, startDownload: startDownload)
                                .frame(
                                    width: min(360, max(320, proxy.size.width - 32)),
                                    height: min(560, max(360, proxy.size.height - 80))
                                )
                        }
                    }
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.11))
                    }
                    .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
                    .padding(.top, 50)
                    .padding(.trailing, 18)
                    .onExitCommand { dismissTransientPanels() }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topTrailing)))
            .zIndex(20)
        }
    }

    private func dismissTransientPanels() {
        library.isQuickAddPresented = false
        compactInspectorPresented = false
    }

    @ViewBuilder
    private var topAccessories: some View {
        VStack(spacing: 0) {
            if windowWidth < 760, compactSearchPresented {
                compactSearchBar
            }
            if let detectedClipboardURL {
                clipboardSuggestion(detectedClipboardURL)
            }
        }
    }

    private var compactSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search title, creator, URL, collection…",
                text: $library.searchText
            )
            .textFieldStyle(.plain)
            .focused($compactSearchFocused)
            .onSubmit { compactSearchPresented = false }

            if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }

            Button("Done") {
                compactSearchPresented = false
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func clipboardSuggestion(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(VidindirTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Media link detected")
                    .font(.subheadline.weight(.medium))
                Text(url.host ?? "Copied link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ignore") { detectedClipboardURL = nil }
                .buttonStyle(.borderless)
            Button("Add") {
                detectedClipboardURL = nil
                presentQuickAdd(url: url)
            }
            .buttonStyle(.borderedProminent)
            .tint(VidindirTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func inspectClipboardIfNeeded() {
        guard clipboardSuggestions,
              !library.isQuickAddPresented,
              let value = NSPasteboard.general.string(forType: .string),
              value != lastInspectedClipboardValue else { return }
        lastInspectedClipboardValue = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), Self.isHTTPURL(url) else {
            detectedClipboardURL = nil
            return
        }
        detectedClipboardURL = url
    }

    private func presentQuickAdd(url: URL) {
        quickAddInitialLink = url.absoluteString
        compactInspectorPresented = false
        library.isQuickAddPresented = true
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}

private struct AdaptiveToolbarSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                placement: .toolbar,
                prompt: "Search title, creator, URL, collection…"
            )
        } else {
            content
        }
    }
}
