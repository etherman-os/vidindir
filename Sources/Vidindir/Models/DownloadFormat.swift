import Foundation

public enum DownloadFormat: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case mp4
    case mp3

    public var id: String { rawValue }

    public var displayName: String { rawValue.uppercased() }

    public var fileExtension: String { rawValue }

    public var requiresFFmpeg: Bool { true }
}
