import Foundation

public final class ToolInstallService: @unchecked Sendable {
    public typealias OutputHandler = @Sendable (String) -> Void

    private let homebrewURL: URL?
    private let runner: SubprocessRunner

    public init(
        homebrewURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: SubprocessRunner = SubprocessRunner()
    ) {
        self.homebrewURL = homebrewURL.flatMap(Self.validExecutable)
            ?? Self.findHomebrew(environment: environment)
        self.runner = runner
    }

    public var isHomebrewAvailable: Bool { homebrewURL != nil }

    public func installationInvocation(
        for missingTools: [ToolBinary]
    ) throws -> ProcessInvocation {
        guard let homebrewURL else {
            throw ToolInstallServiceError.homebrewNotFound
        }

        let requested = ToolBinary.allCases.filter { missingTools.contains($0) }
        guard !requested.isEmpty else {
            throw ToolInstallServiceError.noToolsToInstall
        }

        return ProcessInvocation(
            executableURL: homebrewURL,
            arguments: ["install"] + requested.map(\.rawValue)
        )
    }

    @discardableResult
    public func installMissing(
        from availability: ToolAvailability,
        onOutput: @escaping OutputHandler = { _ in }
    ) async throws -> SubprocessResult {
        let invocation = try installationInvocation(
            for: availability.missingRequiredTools
        )
        let result = try await runner.run(invocation) { _, line in
            onOutput(line)
        }
        guard result.terminationReason == .exit, result.exitCode == 0 else {
            let detail = result.standardError.suffix(4).joined(separator: " ")
            throw ToolInstallServiceError.installationFailed(
                exitCode: result.exitCode,
                message: detail.isEmpty ? nil : detail
            )
        }
        return result
    }

    private static func findHomebrew(environment: [String: String]) -> URL? {
        var candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            URL(fileURLWithPath: "/usr/local/bin/brew"),
        ]
        if let path = environment["PATH"] {
            candidates += path
                .split(separator: ":", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { ($0 as NSString).isAbsolutePath }
                .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("brew") }
        }
        var seen = Set<String>()
        return candidates.lazy
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .compactMap(validExecutable)
            .first
    }

    private static func validExecutable(_ url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL,
              (standardized.path as NSString).isAbsolutePath else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: standardized.path) else {
            return nil
        }
        return standardized.resolvingSymlinksInPath()
    }
}

public enum ToolInstallServiceError: LocalizedError, Equatable, Sendable {
    case homebrewNotFound
    case noToolsToInstall
    case installationFailed(exitCode: Int32, message: String?)

    public var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            return "Homebrew was not found. Install it from brew.sh, then try again."
        case .noToolsToInstall:
            return "All required tools are already installed."
        case .installationFailed(let exitCode, let message):
            let detail = message.map { " \($0)" } ?? ""
            return "Homebrew could not install the tools (exit code \(exitCode)).\(detail)"
        }
    }
}
