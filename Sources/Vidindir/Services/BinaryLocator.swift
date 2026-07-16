import Foundation

public struct BinaryLocator {
    public static let homebrewAndSystemDirectories: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        URL(fileURLWithPath: "/bin", isDirectory: true),
    ]

    private let fileManager: FileManager
    private let searchDirectories: [URL]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fixedSearchDirectories: [URL] = BinaryLocator.homebrewAndSystemDirectories,
        includeBundledTools: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        var directories: [URL] = []
        if includeBundledTools,
           let resources = Bundle.main.resourceURL {
            directories.append(resources.appendingPathComponent("Tools", isDirectory: true))
        }
        directories.append(contentsOf: fixedSearchDirectories)

        if let path = environment["PATH"] {
            directories.append(contentsOf: path
                .split(separator: ":", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { ($0 as NSString).isAbsolutePath }
                .map { URL(fileURLWithPath: $0, isDirectory: true) })
        }

        var seen = Set<String>()
        self.searchDirectories = directories.compactMap { directory in
            let path = directory.standardizedFileURL.path
            guard (path as NSString).isAbsolutePath, seen.insert(path).inserted else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    public func locate(_ tool: ToolBinary, override: URL? = nil) -> URL? {
        if let override, let executable = executableURL(for: override) {
            return executable
        }

        for directory in searchDirectories {
            let candidate = directory.appendingPathComponent(tool.rawValue, isDirectory: false)
            if let executable = executableURL(for: candidate) {
                return executable
            }
        }
        return nil
    }

    public func locateAll(overrides: [ToolBinary: URL] = [:]) -> ToolAvailability {
        ToolAvailability(
            ytDLP: locate(.ytDLP, override: overrides[.ytDLP]),
            ffmpeg: locate(.ffmpeg, override: overrides[.ffmpeg]),
            deno: locate(.deno, override: overrides[.deno])
        )
    }

    private func executableURL(for candidate: URL) -> URL? {
        guard candidate.isFileURL,
              (candidate.path as NSString).isAbsolutePath else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: candidate.path) else {
            return nil
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard (resolved.path as NSString).isAbsolutePath else { return nil }
        return resolved
    }
}
