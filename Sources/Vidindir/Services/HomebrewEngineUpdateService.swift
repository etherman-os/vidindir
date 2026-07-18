import Darwin
import Foundation

public struct HomebrewEngineUpdatePolicy: Equatable, Sendable {
    public let successfulCheckInterval: TimeInterval
    public let failedCheckRetryInterval: TimeInterval
    public let metadataCommandTimeout: Duration
    public let upgradeCommandTimeout: Duration
    public let healthCheckTimeout: Duration

    public init(
        successfulCheckInterval: TimeInterval = 24 * 60 * 60,
        failedCheckRetryInterval: TimeInterval = 6 * 60 * 60,
        metadataCommandTimeout: Duration = .seconds(300),
        upgradeCommandTimeout: Duration = .seconds(1_800),
        healthCheckTimeout: Duration = .seconds(30)
    ) {
        self.successfulCheckInterval = successfulCheckInterval
        self.failedCheckRetryInterval = failedCheckRetryInterval
        self.metadataCommandTimeout = metadataCommandTimeout
        self.upgradeCommandTimeout = upgradeCommandTimeout
        self.healthCheckTimeout = healthCheckTimeout
    }
}

/// Developer-preview updater for tools installed as Homebrew formulae.
///
/// It updates Homebrew metadata, discovers which supported formulae are
/// actually installed, and upgrades only the installed formulae Homebrew marks
/// as outdated. Calls are coalesced so simultaneous automatic/manual requests
/// cannot launch overlapping Homebrew processes.
public actor HomebrewEngineUpdateService {
    public typealias DateProvider = @Sendable () -> Date

    private let homebrewURL: URL?
    private let runner: any ProcessRunning
    private let locator: BinaryLocator
    private let toolOverrides: [ToolBinary: URL]
    private let homebrewEnvironment: [String: String]
    private let defaults: UserDefaults
    private let policy: HomebrewEngineUpdatePolicy
    private let now: DateProvider
    private let lastAttemptKey: String
    private let lastSuccessKey: String
    nonisolated let healthStore: HomebrewEngineHealthStore
    nonisolated let mutationLock: HomebrewEngineMutationLock
    private var inFlightCheck: InFlightCheck?

    public init(
        homebrewURL: URL?,
        runner: any ProcessRunning = SubprocessRunner(),
        locator: BinaryLocator = BinaryLocator(),
        toolOverrides: [ToolBinary: URL] = [:],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        policy: HomebrewEngineUpdatePolicy = HomebrewEngineUpdatePolicy(),
        persistenceKeyPrefix: String = "engine.homebrewUpdate",
        persistenceDirectoryURL: URL? = nil,
        now: @escaping DateProvider = Date.init
    ) {
        self.homebrewURL = homebrewURL
        self.runner = runner
        self.locator = locator
        self.toolOverrides = toolOverrides
        self.homebrewEnvironment = HomebrewProcessEnvironment.constrained(
            inheriting: environment
        )
        self.defaults = defaults
        self.policy = policy
        self.now = now
        self.lastAttemptKey = "\(persistenceKeyPrefix).lastAttempt"
        self.lastSuccessKey = "\(persistenceKeyPrefix).lastSuccess"
        let persistenceDirectory = persistenceDirectoryURL
            ?? Self.defaultPersistenceDirectoryURL()
        self.healthStore = HomebrewEngineHealthStore(
            journalURL: persistenceDirectory.appendingPathComponent(
                "homebrew-engine-health.json",
                isDirectory: false
            ),
            legacyDefaults: defaults,
            legacyKeyPrefix: persistenceKeyPrefix
        )
        self.mutationLock = HomebrewEngineMutationLock(
            lockURL: persistenceDirectory.appendingPathComponent(
                "homebrew-engine-mutation.lock",
                isDirectory: false
            )
        )
    }

    public func checkForUpdates(force: Bool = false) async -> DownloadEngineUpdateResult {
        let check: InFlightCheck
        if let inFlightCheck {
            check = inFlightCheck
        } else {
            check = InFlightCheck(task: Task { [self] in
                await performCheck(force: force)
            })
            inFlightCheck = check
        }

        let waiterID = UUID()
        check.addWaiter(waiterID)

        let result = await withTaskCancellationHandler {
            await check.task.value
        } onCancel: {
            // A check can be shared by the scheduler and a manual request. A
            // cancelled observer must not tear down work another observer is
            // still awaiting. The final observer does cancel the subprocess
            // tree so abandoned Homebrew work cannot continue in the app.
            if check.removeWaiter(waiterID) {
                check.task.cancel()
            }
        }
        _ = check.removeWaiter(waiterID)

        if inFlightCheck?.id == check.id {
            inFlightCheck = nil
        }
        return result
    }

    /// Performs only local executable checks. This is used to recover a
    /// persisted unsafe state and to validate a fresh installation without
    /// requiring Homebrew metadata or network access. A manual assessment
    /// bypasses the failed-health retry cadence, but still participates in the
    /// cross-process mutation lock.
    func assessHealth() async -> DownloadEngineUpdateResult {
        await performPersistedHealthAssessment(force: true)
    }

    private func performCheck(force: Bool) async -> DownloadEngineUpdateResult {
        let attemptedAt = now()
        let persistedHealthState = healthStore.state()

        // A prior mutation always takes precedence over update metadata. An
        // interrupted mutation is reassessed immediately; a persisted
        // unhealthy result observes the shorter failed-check cadence unless a
        // user explicitly forces the operation.
        switch persistedHealthState {
        case .mutationPending:
            return await performPersistedHealthAssessment(force: true)
        case .unhealthy:
            return await performPersistedHealthAssessment(force: force)
        case .ready:
            break
        }

        if !force, let nextCheck = nextAutomaticCheck(after: attemptedAt) {
            return .skipped(nextCheck: nextCheck)
        }

        let retryAfter = attemptedAt.addingTimeInterval(policy.failedCheckRetryInterval)

        do {
            guard let mutationLease = try mutationLock.tryAcquire() else {
                return .busy
            }
            defer { withExtendedLifetime(mutationLease) {} }

            // Another process may have completed or failed an engine mutation
            // between our optimistic state read and lock acquisition.
            switch healthStore.state() {
            case .mutationPending:
                return await assessHealthHoldingLock(assessedAt: attemptedAt)
            case .unhealthy:
                if !force,
                   let nextAssessment = nextUnhealthyAssessment(after: attemptedAt) {
                    return .skipped(nextCheck: nextAssessment)
                }
                return await assessHealthHoldingLock(assessedAt: attemptedAt)
            case .ready:
                break
            }

            defaults.set(attemptedAt, forKey: lastAttemptKey)
            guard let homebrewURL else {
                return .unavailable(retryAfter: retryAfter)
            }

            // This refreshes formula metadata only. It does not reinstall or
            // remove any user package.
            _ = try await runHomebrew(
                homebrewURL,
                arguments: ["update"],
                timeout: policy.metadataCommandTimeout
            )

            let installedResult = try await runHomebrew(
                homebrewURL,
                arguments: ["list", "--formula", "--versions"],
                timeout: policy.metadataCommandTimeout
            )
            let installed = Self.installedTools(from: installedResult.standardOutput)

            guard !installed.isEmpty else {
                let unhealthy = try await assessAndPersistHealth(at: attemptedAt)
                guard unhealthy.isEmpty else {
                    return .unhealthy(components: unhealthy, retryAfter: retryAfter)
                }
                let checkedAt = recordSuccessfulCheck()
                return .notManaged(checkedAt: checkedAt)
            }

            let outdatedResult = try await runHomebrew(
                homebrewURL,
                arguments: ["outdated", "--formula", "--json=v2"] + installed.map(\.rawValue),
                timeout: policy.metadataCommandTimeout,
                acceptedExitCodes: [0, 1]
            )
            let outdatedResponse = try Self.outdatedFormulae(from: outdatedResult.standardOutput)
            let outdated = installed.filter { outdatedResponse.upgradable.contains($0.rawValue) }
            let pinned = installed.filter { outdatedResponse.pinned.contains($0.rawValue) }

            guard !outdated.isEmpty else {
                let unhealthy = try await assessAndPersistHealth(at: attemptedAt)
                guard unhealthy.isEmpty else {
                    return .unhealthy(components: unhealthy, retryAfter: retryAfter)
                }
                let checkedAt = recordSuccessfulCheck()
                if !pinned.isEmpty {
                    if installed.count != ToolBinary.allCases.count {
                        return .partiallyManagedWithBlockedUpdates(
                            managedComponents: installed,
                            updatedComponents: [],
                            blockedComponents: pinned,
                            checkedAt: checkedAt
                        )
                    }
                    return .updatesBlocked(components: pinned, checkedAt: checkedAt)
                }
                if installed.count != ToolBinary.allCases.count {
                    return .partiallyManaged(
                        managedComponents: installed,
                        updatedComponents: [],
                        checkedAt: checkedAt
                    )
                }
                return .upToDate(checkedAt: checkedAt)
            }

            // Homebrew can change more than one keg before reporting a late
            // failure. Persist the need for a health check before the first
            // mutation so a cancelled app still validates the engine on its
            // next launch, regardless of the normal retry cadence.
            try healthStore.markMutationPending()
            do {
                _ = try await runHomebrew(
                    homebrewURL,
                    arguments: ["upgrade", "--formula", "--no-ask"] + outdated.map(\.rawValue),
                    timeout: policy.upgradeCommandTimeout
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let unhealthy = try await assessAndPersistHealth(at: attemptedAt)
                guard unhealthy.isEmpty else {
                    return .unhealthy(components: unhealthy, retryAfter: retryAfter)
                }
                return .failed(retryAfter: retryAfter)
            }
            let unhealthy = try await assessAndPersistHealth(at: attemptedAt)
            guard unhealthy.isEmpty else {
                return .unhealthy(components: unhealthy, retryAfter: retryAfter)
            }
            let checkedAt = recordSuccessfulCheck()
            if !pinned.isEmpty {
                if installed.count != ToolBinary.allCases.count {
                    return .partiallyManagedWithBlockedUpdates(
                        managedComponents: installed,
                        updatedComponents: outdated,
                        blockedComponents: pinned,
                        checkedAt: checkedAt
                    )
                }
                return .updatedWithBlockedComponents(
                    updatedComponents: outdated,
                    blockedComponents: pinned,
                    checkedAt: checkedAt
                )
            }
            if installed.count != ToolBinary.allCases.count {
                return .partiallyManaged(
                    managedComponents: installed,
                    updatedComponents: outdated,
                    checkedAt: checkedAt
                )
            }
            return .updated(components: outdated, checkedAt: checkedAt)
        } catch is CancellationError {
            return .failed(retryAfter: retryAfter)
        } catch {
            // Command output and implementation errors are intentionally not
            // exposed to the app UI. A later automatic check can retry.
            return .failed(retryAfter: retryAfter)
        }
    }

    /// Runs the user-triggered setup/repair path under the same process-wide
    /// lease as automatic upgrades. Missing components are installed. Existing
    /// but unhealthy Homebrew-managed components are narrowly reinstalled; an
    /// unmanaged unhealthy component is never replaced without user control.
    func prepareEngine(
        using installer: ToolInstallService,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let mutationLease = try mutationLock.tryAcquire() else {
            throw DownloadEngineError.operationInProgress
        }
        defer { withExtendedLifetime(mutationLease) {} }

        var availability = locator.locateAll()
        if !availability.canDownload {
            try healthStore.markMutationPending()
            do {
                _ = try await installer.installMissing(
                    from: availability,
                    onOutput: onOutput
                )
            } catch {
                let unhealthy = try await persistHealthAfterMutationAttempt(at: now())
                if unhealthy.isEmpty {
                    return
                }
                throw error
            }

            availability = locator.locateAll()
            guard availability.canDownload else {
                _ = try await persistHealthAfterMutationAttempt(at: now())
                throw DownloadEngineError.componentsStillMissing
            }

            try await requireHealthyEngine(at: now())
            return
        }

        let assessedAt = now()
        let unhealthy = try await assessAndPersistHealth(at: assessedAt)
        guard !unhealthy.isEmpty else { return }

        guard let homebrewURL else {
            throw DownloadEngineError.manualRepairRequired(
                components: unhealthy.map(\.displayName)
            )
        }

        let installedResult: SubprocessResult
        do {
            installedResult = try await runHomebrew(
                homebrewURL,
                arguments: ["list", "--formula", "--versions"],
                timeout: policy.metadataCommandTimeout
            )
        } catch {
            throw DownloadEngineError.manualRepairRequired(
                components: unhealthy.map(\.displayName)
            )
        }

        let managed = Set(Self.installedTools(from: installedResult.standardOutput))
        let unmanaged = unhealthy.filter { !managed.contains($0) }
        guard unmanaged.isEmpty else {
            throw DownloadEngineError.manualRepairRequired(
                components: unmanaged.map(\.displayName)
            )
        }

        try healthStore.markMutationPending()
        do {
            _ = try await runHomebrew(
                homebrewURL,
                arguments: ["reinstall", "--formula", "--no-ask"]
                    + unhealthy.map(\.rawValue),
                timeout: policy.upgradeCommandTimeout,
                onLine: { _, line in onOutput(line) }
            )
        } catch {
            let blocked = try await persistHealthAfterMutationAttempt(at: now())
            if blocked.isEmpty {
                return
            }
            throw DownloadEngineError.automaticRepairFailed(
                components: blocked.map(\.displayName)
            )
        }

        try await requireHealthyEngine(at: now())
    }

    private func performPersistedHealthAssessment(
        force: Bool
    ) async -> DownloadEngineUpdateResult {
        let assessedAt = now()
        let retryAfter = assessedAt.addingTimeInterval(policy.failedCheckRetryInterval)

        if !force,
           healthStore.state().isUnhealthy,
           let nextAssessment = nextUnhealthyAssessment(after: assessedAt) {
            return .skipped(nextCheck: nextAssessment)
        }

        do {
            guard let mutationLease = try mutationLock.tryAcquire() else {
                return .busy
            }
            defer { withExtendedLifetime(mutationLease) {} }

            if !force,
               healthStore.state().isUnhealthy,
               let nextAssessment = nextUnhealthyAssessment(after: assessedAt) {
                return .skipped(nextCheck: nextAssessment)
            }
            return await assessHealthHoldingLock(assessedAt: assessedAt)
        } catch {
            return .failed(retryAfter: retryAfter)
        }
    }

    private func assessHealthHoldingLock(
        assessedAt: Date
    ) async -> DownloadEngineUpdateResult {
        let retryAfter = assessedAt.addingTimeInterval(policy.failedCheckRetryInterval)

        do {
            let unhealthy = try await assessAndPersistHealth(at: assessedAt)
            guard unhealthy.isEmpty else {
                return .unhealthy(components: unhealthy, retryAfter: retryAfter)
            }
            return .recovered(checkedAt: assessedAt)
        } catch is CancellationError {
            return .failed(retryAfter: retryAfter)
        } catch {
            return .failed(retryAfter: retryAfter)
        }
    }

    private func assessAndPersistHealth(at assessedAt: Date) async throws -> [ToolBinary] {
        try healthStore.recordAssessmentAttempt(at: assessedAt)
        let unhealthy = try await unhealthyTools(in: ToolBinary.allCases)
        try healthStore.recordAssessment(
            unhealthyComponents: unhealthy,
            attemptedAt: unhealthy.isEmpty ? nil : assessedAt
        )
        return unhealthy
    }

    private func persistHealthAfterMutationAttempt(
        at assessedAt: Date
    ) async throws -> [ToolBinary] {
        try await assessAndPersistHealth(at: assessedAt)
    }

    private func requireHealthyEngine(at assessedAt: Date) async throws {
        let unhealthy = try await assessAndPersistHealth(at: assessedAt)
        guard unhealthy.isEmpty else {
            throw DownloadEngineError.automaticRepairFailed(
                components: unhealthy.map(\.displayName)
            )
        }
    }

    private func nextAutomaticCheck(after date: Date) -> Date? {
        let lastSuccess = defaults.object(forKey: lastSuccessKey) as? Date
        let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date

        if let lastAttempt,
           lastSuccess.map({ lastAttempt > $0 }) ?? true {
            let nextRetry = lastAttempt.addingTimeInterval(policy.failedCheckRetryInterval)
            if nextRetry > date {
                return nextRetry
            }
            return nil
        }

        if let lastSuccess {
            let nextSuccessCheck = lastSuccess.addingTimeInterval(policy.successfulCheckInterval)
            if nextSuccessCheck > date {
                return nextSuccessCheck
            }
        }

        return nil
    }

    private func nextUnhealthyAssessment(after date: Date) -> Date? {
        guard let lastAttempt = healthStore.lastAssessmentAttemptDate() else {
            return nil
        }
        let nextRetry = lastAttempt.addingTimeInterval(policy.failedCheckRetryInterval)
        return nextRetry > date ? nextRetry : nil
    }

    private func recordSuccessfulCheck() -> Date {
        let checkedAt = now()
        defaults.set(checkedAt, forKey: lastSuccessKey)
        return checkedAt
    }

    private func runHomebrew(
        _ executableURL: URL,
        arguments: [String],
        timeout: Duration,
        acceptedExitCodes: Set<Int32> = [0],
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void = { _, _ in }
    ) async throws -> SubprocessResult {
        let result = try await runner.run(ProcessInvocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: homebrewEnvironment
        ), timeout: timeout, onLine: onLine)

        // `brew outdated <formulae>` intentionally exits with status 1 when
        // at least one requested formula is outdated. Its JSON response is
        // still authoritative, so that call explicitly accepts both 0 and 1.
        guard result.terminationReason == .exit,
              acceptedExitCodes.contains(result.exitCode) else {
            throw HomebrewEngineUpdateError.commandFailed
        }
        return result
    }

    private func unhealthyTools(in tools: [ToolBinary]) async throws -> [ToolBinary] {
        var unhealthy: [ToolBinary] = []

        for tool in tools {
            guard let executableURL = locator.locate(tool, override: toolOverrides[tool]) else {
                unhealthy.append(tool)
                continue
            }

            do {
                let result = try await runner.run(ProcessInvocation(
                    executableURL: executableURL,
                    arguments: Self.versionArguments(for: tool)
                ), timeout: policy.healthCheckTimeout) { _, _ in }

                if result.terminationReason != .exit
                    || result.exitCode != 0
                    || !Self.hasRecognizableVersionOutput(result, for: tool) {
                    unhealthy.append(tool)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unhealthy.append(tool)
            }
        }

        return unhealthy
    }

    private static func versionArguments(for tool: ToolBinary) -> [String] {
        switch tool {
        case .ytDLP, .deno:
            return ["--version"]
        case .ffmpeg:
            return ["-version"]
        }
    }

    private static func hasRecognizableVersionOutput(
        _ result: SubprocessResult,
        for tool: ToolBinary
    ) -> Bool {
        let lines = (result.standardOutput + result.standardError)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }

        switch tool {
        case .ytDLP:
            // yt-dlp prints a date-like version, optionally prefixed by a
            // channel name (for example 2026.07.04 or stable@2026.07.04).
            return lines.contains { line in
                guard let firstToken = line.split(whereSeparator: \.isWhitespace).first else {
                    return false
                }
                let channelStripped = firstToken.split(separator: "@").last ?? firstToken
                let datePrefix = channelStripped.prefix { $0.isNumber || $0 == "." }
                let components = datePrefix.split(separator: ".", omittingEmptySubsequences: false)
                guard components.count >= 3,
                      components[0].count == 4,
                      (1...2).contains(components[1].count),
                      (1...2).contains(components[2].count) else { return false }
                return components.prefix(3).allSatisfy {
                    !$0.isEmpty && $0.allSatisfy(\.isNumber)
                }
            }
        case .ffmpeg:
            return lines.contains {
                $0.lowercased().hasPrefix("ffmpeg version ")
            }
        case .deno:
            return lines.contains {
                $0.lowercased().hasPrefix("deno ")
                    && $0.contains(where: \.isNumber)
            }
        }
    }

    private static func installedTools(from lines: [String]) -> [ToolBinary] {
        let installedNames = Set(lines.compactMap { line in
            line.split(whereSeparator: \.isWhitespace).first.map(String.init)
        })
        return ToolBinary.allCases.filter { installedNames.contains($0.rawValue) }
    }

    private static func outdatedFormulae(
        from lines: [String]
    ) throws -> (upgradable: Set<String>, pinned: Set<String>) {
        let data = Data(lines.joined(separator: "\n").utf8)
        guard !data.isEmpty else { throw HomebrewEngineUpdateError.invalidResponse }

        do {
            let response = try JSONDecoder().decode(HomebrewOutdatedResponse.self, from: data)
            let pinned = Set(response.formulae.compactMap { formula in
                formula.pinned == true ? formula.name : nil
            })
            let upgradable = Set(response.formulae.compactMap { formula in
                formula.pinned == true ? nil : formula.name
            })
            return (upgradable, pinned)
        } catch {
            throw HomebrewEngineUpdateError.invalidResponse
        }
    }

    private nonisolated static func defaultPersistenceDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("dev.vidindir.app", isDirectory: true)
            .appendingPathComponent("Engine", isDirectory: true)
    }
}

enum HomebrewEngineHealthState: Equatable, Sendable {
    case ready
    case mutationPending
    case unhealthy([ToolBinary])

    var requiresAssessment: Bool {
        self != .ready
    }

    var isUnhealthy: Bool {
        if case .unhealthy = self { return true }
        return false
    }

    var blockingComponents: [ToolBinary] {
        switch self {
        case .ready:
            return []
        case .mutationPending:
            // Until every required executable has been reassessed, none of
            // the engine should be exposed as ready to the downloader.
            return ToolBinary.allCases
        case .unhealthy(let components):
            return components
        }
    }
}

final class HomebrewEngineHealthStore: @unchecked Sendable {
    private struct StoredState: Codable {
        enum Status: String, Codable {
            case ready
            case mutationPending
            case unhealthy
        }

        let schemaVersion: Int
        let status: Status
        let components: [String]
        let lastAssessmentAttempt: Date?

        var healthState: HomebrewEngineHealthState {
            switch status {
            case .ready:
                return .ready
            case .mutationPending:
                return .mutationPending
            case .unhealthy:
                let names = Set(components)
                let tools = ToolBinary.allCases.filter { names.contains($0.rawValue) }
                return tools.isEmpty ? .mutationPending : .unhealthy(tools)
            }
        }
    }

    private enum LoadResult {
        case missing
        case valid(StoredState)
        case corrupt
    }

    let journalURL: URL
    private let legacyDefaults: UserDefaults
    private let legacyHealthKey: String
    private let legacyMutationPendingKey: String
    private let legacyUnhealthyComponentsKey: String
    private let lock = NSLock()

    init(
        journalURL: URL,
        legacyDefaults: UserDefaults,
        legacyKeyPrefix: String
    ) {
        self.journalURL = journalURL.standardizedFileURL
        self.legacyDefaults = legacyDefaults
        self.legacyHealthKey = "\(legacyKeyPrefix).healthState"
        self.legacyMutationPendingKey = "\(legacyKeyPrefix).mutationPendingHealthCheck"
        self.legacyUnhealthyComponentsKey = "\(legacyKeyPrefix).unhealthyComponents"
    }

    func state() -> HomebrewEngineHealthState {
        lock.lock()
        defer { lock.unlock() }

        return loadOrMigrateLocked().healthState
    }

    func lastAssessmentAttemptDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return loadOrMigrateLocked().lastAssessmentAttempt
    }

    func markMutationPending() throws {
        try setState(.mutationPending, lastAssessmentAttempt: nil)
    }

    func recordAssessmentAttempt(at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        let stored = loadOrMigrateLocked()
        try persistLocked(Self.storedState(
            from: stored.healthState,
            lastAssessmentAttempt: date
        ))
    }

    func recordAssessment(
        unhealthyComponents components: [ToolBinary],
        attemptedAt: Date?
    ) throws {
        try setState(
            components.isEmpty ? .ready : .unhealthy(components),
            lastAssessmentAttempt: attemptedAt
        )
    }

    private func setState(
        _ state: HomebrewEngineHealthState,
        lastAssessmentAttempt: Date?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        try persistLocked(Self.storedState(
            from: state,
            lastAssessmentAttempt: lastAssessmentAttempt
        ))
    }

    private func loadOrMigrateLocked() -> StoredState {
        switch loadJournalLocked() {
        case .valid(let state):
            clearLegacyMarkersLocked()
            return state
        case .corrupt:
            return Self.storedState(from: .mutationPending, lastAssessmentAttempt: nil)
        case .missing:
            let legacy = loadLegacyStateLocked()
            guard legacy.healthState != .ready
                    || legacy.lastAssessmentAttempt != nil else {
                return legacy
            }

            // The legacy marker is removed only after the replacement journal
            // has reached stable storage. A failed migration therefore remains
            // fail-closed on the next launch.
            do {
                try persistLocked(legacy)
                clearLegacyMarkersLocked()
                return legacy
            } catch {
                return Self.storedState(from: .mutationPending, lastAssessmentAttempt: nil)
            }
        }
    }

    private func loadLegacyStateLocked() -> StoredState {
        if let data = legacyDefaults.data(forKey: legacyHealthKey),
           let decoded = try? JSONDecoder().decode(StoredState.self, from: data),
           Self.isValid(decoded) {
            return decoded
        }

        if legacyDefaults.object(forKey: legacyHealthKey) != nil {
            return Self.storedState(from: .mutationPending, lastAssessmentAttempt: nil)
        }

        if legacyDefaults.bool(forKey: legacyMutationPendingKey) {
            return Self.storedState(from: .mutationPending, lastAssessmentAttempt: nil)
        }

        if let names = legacyDefaults.array(forKey: legacyUnhealthyComponentsKey) as? [String] {
            let nameSet = Set(names)
            let components = ToolBinary.allCases.filter { nameSet.contains($0.rawValue) }
            guard components.count == nameSet.count, !components.isEmpty else {
                return Self.storedState(from: .mutationPending, lastAssessmentAttempt: nil)
            }
            return Self.storedState(
                from: .unhealthy(components),
                lastAssessmentAttempt: nil
            )
        }

        return Self.storedState(from: .ready, lastAssessmentAttempt: nil)
    }

    private func clearLegacyMarkersLocked() {
        legacyDefaults.removeObject(forKey: legacyHealthKey)
        legacyDefaults.removeObject(forKey: legacyMutationPendingKey)
        legacyDefaults.removeObject(forKey: legacyUnhealthyComponentsKey)
    }

    private func loadJournalLocked() -> LoadResult {
        let path = journalURL.path
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            return errno == ENOENT ? .missing : .corrupt
        }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == geteuid(),
              metadata.st_size > 0,
              metadata.st_size <= 64 * 1_024 else {
            return .corrupt
        }

        var data = Data(count: Int(metadata.st_size))
        let readSucceeded = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard var destination = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.read(descriptor, destination, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                remaining -= count
                destination = destination.advanced(by: count)
            }
            return true
        }
        guard readSucceeded,
              let decoded = try? JSONDecoder().decode(StoredState.self, from: data),
              Self.isValid(decoded) else {
            return .corrupt
        }
        return .valid(decoded)
    }

    private func persistLocked(_ state: StoredState) throws {
        guard Self.isValid(state) else {
            throw HomebrewEngineJournalError.invalidState
        }

        let directoryURL = journalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(journalURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let temporaryPath = temporaryURL.path
        let descriptor = open(
            temporaryPath,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }
        var shouldRemoveTemporaryFile = true
        var temporaryDescriptorIsOpen = true
        defer {
            if temporaryDescriptorIsOpen {
                close(descriptor)
            }
            if shouldRemoveTemporaryFile {
                unlink(temporaryPath)
            }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard var source = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, source, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw HomebrewEngineJournalError.posix(errno)
                }
                remaining -= count
                source = source.advanced(by: count)
            }
        }
        guard fsync(descriptor) == 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }
        temporaryDescriptorIsOpen = false
        _ = close(descriptor)

        guard rename(temporaryPath, journalURL.path) == 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }
        shouldRemoveTemporaryFile = false

        let directoryDescriptor = open(
            directoryURL.path,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }
        defer { close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }
    }

    private static func storedState(
        from state: HomebrewEngineHealthState,
        lastAssessmentAttempt: Date?
    ) -> StoredState {
        switch state {
        case .ready:
            return StoredState(
                schemaVersion: 1,
                status: .ready,
                components: [],
                lastAssessmentAttempt: lastAssessmentAttempt
            )
        case .mutationPending:
            return StoredState(
                schemaVersion: 1,
                status: .mutationPending,
                components: [],
                lastAssessmentAttempt: lastAssessmentAttempt
            )
        case .unhealthy(let components):
            return StoredState(
                schemaVersion: 1,
                status: .unhealthy,
                components: components.map(\.rawValue),
                lastAssessmentAttempt: lastAssessmentAttempt
            )
        }
    }

    private static func isValid(_ state: StoredState) -> Bool {
        guard state.schemaVersion == 1 else { return false }
        let componentNames = state.components
        let uniqueNames = Set(componentNames)
        guard uniqueNames.count == componentNames.count,
              uniqueNames.allSatisfy({ name in
                  ToolBinary.allCases.contains { $0.rawValue == name }
              }) else { return false }

        switch state.status {
        case .ready, .mutationPending:
            return componentNames.isEmpty
        case .unhealthy:
            return !componentNames.isEmpty
        }
    }
}

final class HomebrewEngineMutationLock: @unchecked Sendable {
    final class Lease: @unchecked Sendable {
        private let descriptor: Int32
        private let closeLock = NSLock()
        private var isClosed = false

        fileprivate init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit {
            closeLock.lock()
            defer { closeLock.unlock() }
            guard !isClosed else { return }
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
            isClosed = true
        }
    }

    let lockURL: URL

    init(lockURL: URL) {
        self.lockURL = lockURL.standardizedFileURL
    }

    func tryAcquire() throws -> Lease? {
        let directory = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let descriptor = open(
            lockURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw HomebrewEngineJournalError.posix(errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                return nil
            }
            throw HomebrewEngineJournalError.posix(lockError)
        }
        return Lease(descriptor: descriptor)
    }
}

private enum HomebrewEngineJournalError: Error {
    case invalidState
    case posix(Int32)
}

private final class InFlightCheck: @unchecked Sendable {
    let id = UUID()
    let task: Task<DownloadEngineUpdateResult, Never>
    private let lock = NSLock()
    private var waiterIDs: Set<UUID> = []

    init(task: Task<DownloadEngineUpdateResult, Never>) {
        self.task = task
    }

    func addWaiter(_ id: UUID) {
        lock.lock()
        waiterIDs.insert(id)
        lock.unlock()
    }

    /// Returns true only when this removal leaves the shared task abandoned.
    func removeWaiter(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard waiterIDs.remove(id) != nil else { return false }
        return waiterIDs.isEmpty
    }
}

private struct HomebrewOutdatedResponse: Decodable {
    struct Formula: Decodable {
        let name: String
        let pinned: Bool?
    }

    let formulae: [Formula]
}

private enum HomebrewEngineUpdateError: Error {
    case commandFailed
    case invalidResponse
}
