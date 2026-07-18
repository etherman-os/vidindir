import Foundation

public struct CanonicalizedSource: Codable, Equatable, Hashable, Sendable {
    public let sourceURL: URL
    public let canonicalURL: URL?
    public let sourceType: SourceType
    public let sourceMediaID: String?
    public let canonicalizationVersion: Int

    public init(
        sourceURL: URL,
        canonicalURL: URL?,
        sourceType: SourceType,
        sourceMediaID: String?,
        canonicalizationVersion: Int = 1
    ) {
        self.sourceURL = sourceURL
        self.canonicalURL = canonicalURL
        self.sourceType = sourceType
        self.sourceMediaID = sourceMediaID
        self.canonicalizationVersion = canonicalizationVersion
    }
}

public struct SourceCanonicalizer: Sendable {
    public init() {}

    public func canonicalize(_ sourceURL: URL) throws -> CanonicalizedSource {
        guard let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw LibraryDomainError.invalidSourceURL
        }

        if let result = canonicalizeYouTube(sourceURL, components: components, host: host) {
            return result
        }
        if let result = canonicalizeX(sourceURL, components: components, host: host) {
            return result
        }
        if let result = canonicalizeVimeo(sourceURL, components: components, host: host) {
            return result
        }
        return CanonicalizedSource(
            sourceURL: sourceURL,
            canonicalURL: nil,
            sourceType: .generic,
            sourceMediaID: nil
        )
    }

    private func canonicalizeYouTube(
        _ sourceURL: URL,
        components: URLComponents,
        host: String
    ) -> CanonicalizedSource? {
        let youtubeHosts: Set<String> = [
            "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
            "youtu.be", "www.youtu.be",
        ]
        guard youtubeHosts.contains(host) else { return nil }

        let segments = components.path.split(separator: "/").map(String.init)
        let mediaID: String?
        if host == "youtu.be" || host == "www.youtu.be" {
            mediaID = segments.first
        } else if segments.first == "shorts" || segments.first == "embed" || segments.first == "live" {
            mediaID = segments.dropFirst().first
        } else {
            mediaID = components.queryItems?.first(where: { $0.name == "v" })?.value
        }

        guard let mediaID, isSafeSourceIdentifier(mediaID) else {
            return CanonicalizedSource(
                sourceURL: sourceURL,
                canonicalURL: nil,
                sourceType: .youtube,
                sourceMediaID: nil
            )
        }
        let canonicalURL = URL(string: "https://www.youtube.com/watch?v=\(mediaID)")
        return CanonicalizedSource(
            sourceURL: sourceURL,
            canonicalURL: canonicalURL,
            sourceType: .youtube,
            sourceMediaID: mediaID
        )
    }

    private func canonicalizeX(
        _ sourceURL: URL,
        components: URLComponents,
        host: String
    ) -> CanonicalizedSource? {
        let xHosts: Set<String> = [
            "x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com",
            "mobile.twitter.com",
        ]
        guard xHosts.contains(host) else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        guard let statusIndex = segments.firstIndex(of: "status"),
              segments.indices.contains(statusIndex + 1) else {
            return CanonicalizedSource(
                sourceURL: sourceURL,
                canonicalURL: nil,
                sourceType: .x,
                sourceMediaID: nil
            )
        }
        let mediaID = segments[statusIndex + 1]
        guard mediaID.allSatisfy(\.isNumber), !mediaID.isEmpty else {
            return CanonicalizedSource(
                sourceURL: sourceURL,
                canonicalURL: nil,
                sourceType: .x,
                sourceMediaID: nil
            )
        }
        return CanonicalizedSource(
            sourceURL: sourceURL,
            canonicalURL: URL(string: "https://x.com/i/status/\(mediaID)"),
            sourceType: .x,
            sourceMediaID: mediaID
        )
    }

    private func canonicalizeVimeo(
        _ sourceURL: URL,
        components: URLComponents,
        host: String
    ) -> CanonicalizedSource? {
        guard host == "vimeo.com" || host == "www.vimeo.com" || host == "player.vimeo.com" else {
            return nil
        }
        let mediaID = components.path.split(separator: "/").last.map(String.init)
        guard let mediaID, !mediaID.isEmpty, mediaID.allSatisfy(\.isNumber) else {
            return CanonicalizedSource(
                sourceURL: sourceURL,
                canonicalURL: nil,
                sourceType: .vimeo,
                sourceMediaID: nil
            )
        }
        return CanonicalizedSource(
            sourceURL: sourceURL,
            canonicalURL: URL(string: "https://vimeo.com/\(mediaID)"),
            sourceType: .vimeo,
            sourceMediaID: mediaID
        )
    }

    private func isSafeSourceIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
    }
}
