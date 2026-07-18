import Foundation

public struct TypedID<Scope>: RawRepresentable, Codable, Hashable, Comparable, Sendable,
    CustomStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(uuidString: String) {
        guard let value = UUID(uuidString: uuidString) else { return nil }
        rawValue = value
    }

    public var description: String { rawValue.uuidString.lowercased() }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.description < rhs.description
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a canonical UUID string."
            )
        }
        rawValue = uuid
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum WorkspaceIDScope: Sendable {}
public enum MediaItemIDScope: Sendable {}
public enum CollectionIDScope: Sendable {}
public enum CollectionMembershipIDScope: Sendable {}
public enum TagIDScope: Sendable {}
public enum MediaItemTagIDScope: Sendable {}
public enum FavoriteIDScope: Sendable {}
public enum WorkspaceSettingIDScope: Sendable {}
public enum DeviceIDScope: Sendable {}
public enum LocalAssetIDScope: Sendable {}
public enum DownloadJobIDScope: Sendable {}

public typealias WorkspaceID = TypedID<WorkspaceIDScope>
public typealias MediaItemID = TypedID<MediaItemIDScope>
public typealias CollectionID = TypedID<CollectionIDScope>
public typealias CollectionMembershipID = TypedID<CollectionMembershipIDScope>
public typealias TagID = TypedID<TagIDScope>
public typealias MediaItemTagID = TypedID<MediaItemTagIDScope>
public typealias FavoriteID = TypedID<FavoriteIDScope>
public typealias WorkspaceSettingID = TypedID<WorkspaceSettingIDScope>
public typealias DeviceID = TypedID<DeviceIDScope>
public typealias LocalAssetID = TypedID<LocalAssetIDScope>
public typealias DownloadJobID = TypedID<DownloadJobIDScope>

public enum VidindirIdentity {
    public static let namespace = UUID(uuidString: "39320744-c789-4f7d-94a4-d86788df5028")!
    public static let personalWorkspace = WorkspaceID(
        rawValue: UUID(uuidString: "4ce29601-0ff5-55fb-995f-2329e01734d8")!
    )
    public static let personalInbox = CollectionID(
        rawValue: UUID(uuidString: "4bb48462-deda-5c43-afd5-03031290ff60")!
    )

    public static func inboxCollection(workspaceID: WorkspaceID) -> CollectionID {
        if workspaceID == personalWorkspace {
            return personalInbox
        }
        return CollectionID(rawValue: uuidV5(
            name: #"["collection","inbox",1,"\#(workspaceID)"]"#
        ))
    }

    public static func collectionMembership(
        workspaceID: WorkspaceID,
        collectionID: CollectionID,
        mediaItemID: MediaItemID
    ) -> CollectionMembershipID {
        CollectionMembershipID(rawValue: uuidV5(
            name: #"["collection-membership",1,"\#(workspaceID)","\#(collectionID)","\#(mediaItemID)"]"#
        ))
    }

    public static func favorite(
        workspaceID: WorkspaceID,
        mediaItemID: MediaItemID
    ) -> FavoriteID {
        FavoriteID(rawValue: uuidV5(
            name: #"["favorite",1,"\#(workspaceID)","\#(mediaItemID)"]"#
        ))
    }

    public static func mediaItemTag(
        workspaceID: WorkspaceID,
        mediaItemID: MediaItemID,
        tagID: TagID
    ) -> MediaItemTagID {
        MediaItemTagID(rawValue: uuidV5(
            name: #"["media-item-tag",1,"\#(workspaceID)","\#(mediaItemID)","\#(tagID)"]"#
        ))
    }

    private static func uuidV5(name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: name.utf8)
        var digest = SHA1.hash(bytes)
        digest[6] = (digest[6] & 0x0f) | 0x50
        digest[8] = (digest[8] & 0x3f) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

private enum SHA1 {
    static func hash(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian) { Array($0) })

        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xefcd_ab89
        var h2: UInt32 = 0x98ba_dcfe
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xc3d2_e1f0

        for offset in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 80)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] = UInt32(message[start]) << 24
                    | UInt32(message[start + 1]) << 16
                    | UInt32(message[start + 2]) << 8
                    | UInt32(message[start + 3])
            }
            for index in 16..<80 {
                words[index] = rotateLeft(
                    words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16],
                    by: 1
                )
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4

            for index in 0..<80 {
                let function: UInt32
                let constant: UInt32
                switch index {
                case 0..<20:
                    function = (b & c) | ((~b) & d)
                    constant = 0x5a82_7999
                case 20..<40:
                    function = b ^ c ^ d
                    constant = 0x6ed9_eba1
                case 40..<60:
                    function = (b & c) | (b & d) | (c & d)
                    constant = 0x8f1b_bcdc
                default:
                    function = b ^ c ^ d
                    constant = 0xca62_c1d6
                }
                let temporary = rotateLeft(a, by: 5)
                    &+ function
                    &+ e
                    &+ constant
                    &+ words[index]
                e = d
                d = c
                c = rotateLeft(b, by: 30)
                b = a
                a = temporary
            }

            h0 &+= a
            h1 &+= b
            h2 &+= c
            h3 &+= d
            h4 &+= e
        }

        return [h0, h1, h2, h3, h4].flatMap { value in
            withUnsafeBytes(of: value.bigEndian) { Array($0) }
        }
    }

    private static func rotateLeft(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
