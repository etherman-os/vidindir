import Foundation

public struct ArtifactResolver: Sendable {
    public init() {}

    public func resolve(path: String, inside destinationDirectory: URL) throws -> URL {
        let destination = destinationDirectory
            .standardizedFileURL
        let resolvedDestination = resolveExistingAncestors(of: destination)
        guard resolvedDestination.isFileURL,
              (resolvedDestination.path as NSString).isAbsolutePath else {
            throw ArtifactResolverError.invalidDestination
        }

        let artifact: URL
        if (path as NSString).isAbsolutePath {
            artifact = URL(fileURLWithPath: path, isDirectory: false)
                .standardizedFileURL
        } else {
            artifact = resolvedDestination
                .appendingPathComponent(path, isDirectory: false)
                .standardizedFileURL
        }
        let resolvedArtifact = resolveExistingAncestors(of: artifact)

        let destinationPath = resolvedDestination.path.hasSuffix("/")
            ? String(resolvedDestination.path.dropLast())
            : resolvedDestination.path
        let artifactPath = resolvedArtifact.path
        guard artifactPath != destinationPath,
              artifactPath.hasPrefix(destinationPath + "/") else {
            throw ArtifactResolverError.outsideDestination
        }
        return resolvedArtifact
    }

    /// `URL.resolvingSymlinksInPath()` leaves the path untouched when its final
    /// component does not exist. yt-dlp reports planned paths before creating
    /// them, so resolve the nearest existing ancestor and append only the
    /// genuinely missing suffix.
    private func resolveExistingAncestors(of url: URL) -> URL {
        var ancestor = url
        var missingComponents: [String] = []

        while ancestor.path != "/",
              !FileManager.default.fileExists(atPath: ancestor.path) {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }

        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }
}

public enum ArtifactResolverError: LocalizedError, Equatable, Sendable {
    case invalidDestination
    case outsideDestination

    public var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "The selected download folder is invalid."
        case .outsideDestination:
            return "The downloader reported a file outside the selected folder."
        }
    }
}
