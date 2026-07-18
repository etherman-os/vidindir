import SwiftUI
import VidindirDomain

struct LibrarySidebarView: View {
    @ObservedObject var library: LibraryViewModel
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $library.destination) {
                Section("Library") {
                    sidebarRow(.inbox)
                    sidebarRow(.library)
                    sidebarRow(.favorites)
                }

                Section("Downloads") {
                    sidebarRow(.activeDownloads)
                    sidebarRow(.completedDownloads)
                    sidebarRow(.failedDownloads)
                }

                Section {
                    ForEach(userCollections) { collection in
                        Label(collection.name, systemImage: collection.iconName ?? "folder")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                library.destination = .collection(collection.id)
                            }
                            .dropDestination(for: URL.self) { urls, _ in
                                guard let url = urls.first else { return false }
                                saveDropped(url: url, to: collection.id)
                                return true
                            }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first,
                                      let url = URL(string: value) else { return false }
                                saveDropped(url: url, to: collection.id)
                                return true
                            }
                            .contextMenu {
                                Button("Open") {
                                    library.destination = .collection(collection.id)
                                }
                            }
                            .tag(LibraryDestination.collection(collection.id))
                    }
                } header: {
                    HStack {
                        Text("Collections")
                        Spacer()
                        Button {
                            newCollectionName = ""
                            isCreatingCollection = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("New Collection")
                    }
                }

                Section("Workspaces") {
                    Label("Personal", systemImage: "person.crop.circle")
                        .foregroundStyle(.primary)
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    VidindirMark(size: 24)
                    Text("Vidindir")
                        .font(.caption.weight(.semibold))
                }
                HStack(spacing: 4) {
                    Link("Built by etherman-os", destination: URL(string: "https://github.com/etherman-os")!)
                    Text("·")
                    Link("etherman.org", destination: URL(string: "https://etherman.org")!)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Vidindir")
        .alert("New Collection", isPresented: $isCreatingCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newCollectionName
                Task { _ = await library.createCollection(named: name) }
            }
            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Collections keep related media together without moving or duplicating the original item.")
        }
    }

    private var userCollections: [Collection] {
        library.collections.filter { $0.kind == .user }
    }

    private func sidebarRow(_ destination: LibraryDestination) -> some View {
        HStack(spacing: 8) {
            Label(destination.title, systemImage: destination.systemImage)
            Spacer(minLength: 8)
            if count(for: destination) > 0 {
                Text(count(for: destination), format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
            .contentShape(Rectangle())
            .onTapGesture { library.destination = destination }
            .help(helpText(for: destination))
            .tag(destination)
    }

    private func count(for destination: LibraryDestination) -> Int {
        switch destination {
        case .inbox: library.inboxCount
        case .library: library.libraryCount
        case .favorites: library.favoritesCount
        default: 0
        }
    }

    private func helpText(for destination: LibraryDestination) -> String {
        switch destination {
        case .inbox: "New links waiting to be organized. They are already saved in All Media."
        case .library: "Every saved link, including items still in Inbox."
        case .favorites: "Saved media you marked as a favorite."
        default: destination.title
        }
    }

    private func saveDropped(url: URL, to collectionID: CollectionID) {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return }
        Task {
            do {
                let result = try await library.addLink(
                    url,
                    destination: .collection(collectionID)
                )
                if case .duplicate(let candidates) = result,
                   let existing = candidates.first?.mediaItem {
                    try await library.addExistingMedia(existing, to: collectionID)
                }
                library.destination = .collection(collectionID)
            } catch {
                library.alert = AppAlert(
                    title: "Could not add this link",
                    message: "Check the media link and try again."
                )
            }
        }
    }
}
