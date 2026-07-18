import Foundation

public struct OpenStringValue<Scope>: RawRepresentable, Codable, Hashable, Comparable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum WorkspaceKindScope: Sendable {}
public enum SourceTypeScope: Sendable {}
public enum MetadataStatusScope: Sendable {}
public enum CollectionKindScope: Sendable {}
public enum LocalAssetStatusScope: Sendable {}
public enum DownloadJobStateScope: Sendable {}
public enum MediaKindScope: Sendable {}
public enum QualityPresetScope: Sendable {}
public enum ChangeOperationScope: Sendable {}

public typealias WorkspaceKind = OpenStringValue<WorkspaceKindScope>
public typealias SourceType = OpenStringValue<SourceTypeScope>
public typealias MetadataStatus = OpenStringValue<MetadataStatusScope>
public typealias CollectionKind = OpenStringValue<CollectionKindScope>
public typealias LocalAssetStatus = OpenStringValue<LocalAssetStatusScope>
public typealias DownloadJobState = OpenStringValue<DownloadJobStateScope>
public typealias MediaKind = OpenStringValue<MediaKindScope>
public typealias QualityPreset = OpenStringValue<QualityPresetScope>
public typealias ChangeOperation = OpenStringValue<ChangeOperationScope>

public extension OpenStringValue where Scope == WorkspaceKindScope {
    static let personal: Self = "personal"
    static let shared: Self = "shared"
}

public extension OpenStringValue where Scope == SourceTypeScope {
    static let youtube: Self = "youtube"
    static let x: Self = "x"
    static let vimeo: Self = "vimeo"
    static let generic: Self = "generic"
    static let unknown: Self = "unknown"
}

public extension OpenStringValue where Scope == MetadataStatusScope {
    static let unresolved: Self = "unresolved"
    static let resolving: Self = "resolving"
    static let resolved: Self = "resolved"
    static let failed: Self = "failed"
}

public extension OpenStringValue where Scope == CollectionKindScope {
    static let user: Self = "user"
    static let systemInbox: Self = "system_inbox"
}

public extension OpenStringValue where Scope == LocalAssetStatusScope {
    static let available: Self = "available"
    static let unverified: Self = "unverified"
    static let missing: Self = "missing"
    static let removed: Self = "removed"
}

public extension OpenStringValue where Scope == DownloadJobStateScope {
    static let created: Self = "created"
    static let resolving: Self = "resolving"
    static let ready: Self = "ready"
    static let queued: Self = "queued"
    static let downloading: Self = "downloading"
    static let postProcessing: Self = "post_processing"
    static let completed: Self = "completed"
    static let paused: Self = "paused"
    static let failed: Self = "failed"
    static let cancelled: Self = "cancelled"
    static let interrupted: Self = "interrupted"
}

public extension OpenStringValue where Scope == MediaKindScope {
    static let video: Self = "video"
    static let audio: Self = "audio"
}

public extension OpenStringValue where Scope == QualityPresetScope {
    static let best: Self = "best"
    static let p1080: Self = "p1080"
    static let p720: Self = "p720"
}

public extension OpenStringValue where Scope == ChangeOperationScope {
    static let upsert: Self = "upsert"
    static let tombstone: Self = "tombstone"
}
