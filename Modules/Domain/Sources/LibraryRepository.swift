import Foundation

public enum SaveDestination: Equatable, Hashable, Sendable {
    case inbox
    case collection(CollectionID)
    case libraryOnly
}

public struct SaveLinkCommand: Equatable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let sourceURL: URL
    public let destination: SaveDestination
    public let allowDuplicate: Bool

    public init(
        workspaceID: WorkspaceID = VidindirIdentity.personalWorkspace,
        sourceURL: URL,
        destination: SaveDestination = .inbox,
        allowDuplicate: Bool = false
    ) {
        self.workspaceID = workspaceID
        self.sourceURL = sourceURL
        self.destination = destination
        self.allowDuplicate = allowDuplicate
    }
}

public enum DuplicateReason: String, Codable, Equatable, Hashable, Sendable {
    case sourceIdentity
    case canonicalURL
    case sourceURL
}

public struct DuplicateCandidate: Equatable, Hashable, Sendable {
    public let mediaItem: MediaItem
    public let reason: DuplicateReason

    public init(mediaItem: MediaItem, reason: DuplicateReason) {
        self.mediaItem = mediaItem
        self.reason = reason
    }
}

public enum SaveLinkResult: Equatable, Hashable, Sendable {
    case saved(MediaItem)
    case duplicate([DuplicateCandidate])
}

public struct MediaMetadataUpdate: Equatable, Hashable, Sendable {
    public let title: String?
    public let creator: String?
    public let description: String?
    public let durationSeconds: Double?
    public let thumbnailURL: URL?
    public let status: MetadataStatus
    public let errorCode: String?

    public init(
        title: String?,
        creator: String?,
        description: String?,
        durationSeconds: Double?,
        thumbnailURL: URL?,
        status: MetadataStatus,
        errorCode: String? = nil
    ) {
        self.title = title
        self.creator = creator
        self.description = description
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.status = status
        self.errorCode = errorCode
    }
}

public struct UpdateMediaCommand: Equatable, Hashable, Sendable {
    public let id: MediaItemID
    public let workspaceID: WorkspaceID
    public let expectedRevision: Int64
    public let metadata: MediaMetadataUpdate

    public init(
        id: MediaItemID,
        workspaceID: WorkspaceID,
        expectedRevision: Int64,
        metadata: MediaMetadataUpdate
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.metadata = metadata
    }
}

public struct CreateCollectionCommand: Equatable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let name: String
    public let sortOrder: Double
    public let colorToken: String?
    public let iconName: String?

    public init(
        workspaceID: WorkspaceID = VidindirIdentity.personalWorkspace,
        name: String,
        sortOrder: Double = 0,
        colorToken: String? = nil,
        iconName: String? = nil
    ) {
        self.workspaceID = workspaceID
        self.name = name
        self.sortOrder = sortOrder
        self.colorToken = colorToken
        self.iconName = iconName
    }
}

public struct MembershipCommand: Equatable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let mediaItemID: MediaItemID
    public let collectionID: CollectionID
    public let isMember: Bool

    public init(
        workspaceID: WorkspaceID,
        mediaItemID: MediaItemID,
        collectionID: CollectionID,
        isMember: Bool
    ) {
        self.workspaceID = workspaceID
        self.mediaItemID = mediaItemID
        self.collectionID = collectionID
        self.isMember = isMember
    }
}

public enum LibraryScope: Equatable, Hashable, Sendable {
    case all
    case inbox
    case favorites
    case collection(CollectionID)
}

public struct LibraryQuery: Equatable, Hashable, Sendable {
    public let workspaceID: WorkspaceID
    public let scope: LibraryScope
    public let searchText: String?
    public let limit: Int
    public let offset: Int

    public init(
        workspaceID: WorkspaceID = VidindirIdentity.personalWorkspace,
        scope: LibraryScope = .all,
        searchText: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.workspaceID = workspaceID
        self.scope = scope
        self.searchText = searchText
        self.limit = limit
        self.offset = offset
    }
}

public struct LibraryItemSummary: Identifiable, Equatable, Hashable, Sendable {
    public var id: MediaItemID { mediaItem.id }
    public let mediaItem: MediaItem
    public let isFavorite: Bool
    public let collectionIDs: [CollectionID]
    public let localAssetStatus: LocalAssetStatus?
    public let latestDownloadState: DownloadJobState?

    public init(
        mediaItem: MediaItem,
        isFavorite: Bool,
        collectionIDs: [CollectionID],
        localAssetStatus: LocalAssetStatus?,
        latestDownloadState: DownloadJobState?
    ) {
        self.mediaItem = mediaItem
        self.isFavorite = isFavorite
        self.collectionIDs = collectionIDs
        self.localAssetStatus = localAssetStatus
        self.latestDownloadState = latestDownloadState
    }
}

public struct LibraryPage: Equatable, Hashable, Sendable {
    public let items: [LibraryItemSummary]
    public let totalCount: Int

    public init(items: [LibraryItemSummary], totalCount: Int) {
        self.items = items
        self.totalCount = totalCount
    }
}

public protocol LibraryRepository: Sendable {
    func saveLink(_ command: SaveLinkCommand) async throws -> SaveLinkResult
    func updateMedia(_ command: UpdateMediaCommand) async throws -> MediaItem
    func createCollection(_ command: CreateCollectionCommand) async throws -> Collection
    func collections(workspaceID: WorkspaceID) async throws -> [Collection]
    func setFavorite(mediaID: MediaItemID, workspaceID: WorkspaceID, value: Bool) async throws
    func setCollectionMembership(_ command: MembershipCommand) async throws
    func organizeFromInbox(
        mediaID: MediaItemID,
        workspaceID: WorkspaceID,
        collectionIDs: [CollectionID]
    ) async throws
    func tombstoneMedia(
        id: MediaItemID,
        workspaceID: WorkspaceID,
        expectedRevision: Int64
    ) async throws
    func page(_ query: LibraryQuery) async throws -> LibraryPage
}
