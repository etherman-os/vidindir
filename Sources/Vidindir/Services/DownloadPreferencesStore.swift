import Foundation

public final class DownloadPreferencesStore: @unchecked Sendable {
    private enum Keys {
        static let selectedFormat = "preferences.selectedFormat"
        static func quality(for format: DownloadFormat) -> String {
            "preferences.quality.\(format.rawValue)"
        }
        static func destinationBookmark(for format: DownloadFormat) -> String {
            "preferences.destinationBookmark.\(format.rawValue)"
        }
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let fallbackDirectory: URL
    private let allowsUnscopedBookmarkFallback: Bool
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        fallbackDirectory: URL? = nil,
        allowsUnscopedBookmarkFallback: Bool = ProcessInfo.processInfo
            .environment["APP_SANDBOX_CONTAINER_ID"] == nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.allowsUnscopedBookmarkFallback = allowsUnscopedBookmarkFallback
        self.fallbackDirectory = fallbackDirectory?.standardizedFileURL
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
    }

    public var selectedFormat: DownloadFormat {
        get {
            lock.withLock {
                guard let rawValue = defaults.string(forKey: Keys.selectedFormat),
                      let format = DownloadFormat(rawValue: rawValue) else {
                    return .mp4
                }
                return format
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Keys.selectedFormat)
            }
        }
    }

    public func quality(for format: DownloadFormat) -> DownloadQuality {
        lock.withLock {
            guard let rawValue = defaults.string(forKey: Keys.quality(for: format)),
                  let quality = DownloadQuality(rawValue: rawValue) else {
                return .best
            }
            return quality
        }
    }

    public func setQuality(_ quality: DownloadQuality, for format: DownloadFormat) {
        lock.withLock {
            defaults.set(quality.rawValue, forKey: Keys.quality(for: format))
        }
    }

    public func destinationDirectory(for format: DownloadFormat) -> URL {
        lock.withLock {
            let key = Keys.destinationBookmark(for: format)
            guard let data = defaults.data(forKey: key) else {
                return fallbackDirectory
            }

            guard let bookmark = resolveBookmark(data),
                  case let (scopedURL, isStale) = bookmark else {
                defaults.removeObject(forKey: key)
                return fallbackDirectory
            }

            let accessedSecurityScope = scopedURL.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
            }

            let resolved = scopedURL.standardizedFileURL
            guard isExistingDirectory(resolved) else {
                defaults.removeObject(forKey: key)
                return fallbackDirectory
            }

            if isStale, let refreshed = try? makeBookmark(for: resolved) {
                defaults.set(refreshed, forKey: key)
            }
            return resolved
        }
    }

    public func setDestinationDirectory(
        _ directory: URL,
        for format: DownloadFormat
    ) throws {
        let standardized = directory.standardizedFileURL
        guard isExistingDirectory(standardized) else {
            throw DownloadPreferencesError.notDirectory
        }

        let bookmark: Data
        do {
            bookmark = try makeBookmark(for: standardized)
        } catch {
            throw DownloadPreferencesError.couldNotCreateBookmark
        }

        lock.withLock {
            defaults.set(bookmark, forKey: Keys.destinationBookmark(for: format))
        }
    }

    public func remember(format: DownloadFormat, destinationDirectory: URL) throws {
        try setDestinationDirectory(destinationDirectory, for: format)
        selectedFormat = format
    }

    public func clearDestinationDirectory(for format: DownloadFormat) {
        lock.withLock {
            defaults.removeObject(forKey: Keys.destinationBookmark(for: format))
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.isDirectoryKey],
                relativeTo: nil
            )
        } catch {
            guard allowsUnscopedBookmarkFallback else { throw error }
            // Unsandboxed development builds do not always have access to
            // ScopedBookmarksAgent. Keep using bookmark data there; signed
            // sandboxed builds take the security-scoped branch above.
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: [.isDirectoryKey],
                relativeTo: nil
            )
        }
    }

    private func resolveBookmark(_ data: Data) -> (URL, Bool)? {
        var isStale = false
        if let scoped = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (scoped, isStale)
        }

        isStale = false
        guard let regular = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (regular, isStale)
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

public enum DownloadPreferencesError: LocalizedError, Equatable, Sendable {
    case notDirectory
    case couldNotCreateBookmark

    public var errorDescription: String? {
        switch self {
        case .notDirectory:
            return "The selected destination is not an existing folder."
        case .couldNotCreateBookmark:
            return "Vidindir could not remember permission for that folder."
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
