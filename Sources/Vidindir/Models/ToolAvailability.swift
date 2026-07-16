import Foundation

public enum ToolBinary: String, CaseIterable, Codable, Hashable, Sendable {
    case ytDLP = "yt-dlp"
    case ffmpeg
    case deno

    public var displayName: String {
        switch self {
        case .ytDLP: return "yt-dlp"
        case .ffmpeg: return "FFmpeg"
        case .deno: return "Deno"
        }
    }
}

public struct ToolAvailability: Equatable, Hashable, Sendable {
    public var ytDLP: URL?
    public var ffmpeg: URL?
    public var deno: URL?

    public init(ytDLP: URL? = nil, ffmpeg: URL? = nil, deno: URL? = nil) {
        self.ytDLP = ytDLP
        self.ffmpeg = ffmpeg
        self.deno = deno
    }

    public var canDownload: Bool {
        ytDLP != nil && ffmpeg != nil && deno != nil
    }

    public var missingRequiredTools: [ToolBinary] {
        var missing: [ToolBinary] = []
        if ytDLP == nil { missing.append(.ytDLP) }
        if ffmpeg == nil { missing.append(.ffmpeg) }
        if deno == nil { missing.append(.deno) }
        return missing
    }

    public subscript(tool: ToolBinary) -> URL? {
        get {
            switch tool {
            case .ytDLP: return ytDLP
            case .ffmpeg: return ffmpeg
            case .deno: return deno
            }
        }
        set {
            switch tool {
            case .ytDLP: ytDLP = newValue
            case .ffmpeg: ffmpeg = newValue
            case .deno: deno = newValue
            }
        }
    }
}
