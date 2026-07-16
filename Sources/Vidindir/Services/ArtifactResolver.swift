import Foundation

public struct ArtifactResolver: Sendable {
    public init() {}

    public func resolve(path: String, inside destinationDirectory: URL) throws -> URL {
        let destination = destinationDirectory.standardizedFileURL
        guard destination.isFileURL,
              (destination.path as NSString).isAbsolutePath else {
            throw ArtifactResolverError.invalidDestination
        }

        let artifact: URL
        if (path as NSString).isAbsolutePath {
            artifact = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        } else {
            artifact = destination
                .appendingPathComponent(path, isDirectory: false)
                .standardizedFileURL
        }

        let destinationPath = destination.path.hasSuffix("/")
            ? String(destination.path.dropLast())
            : destination.path
        let artifactPath = artifact.path
        guard artifactPath != destinationPath,
              artifactPath.hasPrefix(destinationPath + "/") else {
            throw ArtifactResolverError.outsideDestination
        }
        return artifact
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
