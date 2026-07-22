import Foundation
import Testing
@testable import Vidindir

@Suite("Homebrew engine updates")
struct HomebrewEngineUpdateServiceTests {
    @Test func upgradesOnlyInstalledFormulaeReportedAsOutdated() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"

        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: [
                "yt-dlp 2026.7.4",
                "ffmpeg 8.1.2",
            ]),
            .outdated(output: [
                #"{"formulae":[{"name":"yt-dlp","pinned":false},{"name":"ffmpeg","pinned":true},{"name":"deno","pinned":false}],"casks":[]}"#,
            ]),
            .success(),
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            environment: ["PATH": "/test/bin"],
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let result = await service.checkForUpdates()

        #expect(result == .partiallyManagedWithBlockedUpdates(
            managedComponents: [.ytDLP, .ffmpeg],
            updatedComponents: [.ytDLP],
            blockedComponents: [.ffmpeg],
            checkedAt: date
        ))
        #expect(await runner.arguments == [
            ["update"],
            ["list", "--formula", "--versions"],
            ["outdated", "--formula", "--json=v2", "yt-dlp", "ffmpeg"],
            ["upgrade", "--formula", "--no-ask", "yt-dlp"],
            ["--version"],
            ["-version"],
            ["--version"],
        ])
        let invocations = await runner.invocations
        #expect(invocations.prefix(4).allSatisfy {
            $0.environment?["PATH"] == "/test/bin"
                && $0.environment?["HOMEBREW_NO_ASK"] == "1"
                && $0.environment?["HOMEBREW_NO_INSTALL_CLEANUP"] == "1"
                && $0.environment?["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1"
                && $0.environment?["HOMEBREW_NO_AUTO_UPDATE"] == "1"
                && $0.environment?["HOMEBREW_NO_ANALYTICS"] == "1"
        })
        #expect(await runner.timeouts == [
            .seconds(300), .seconds(300), .seconds(300),
            .seconds(1_800), .seconds(30), .seconds(30), .seconds(30),
        ])
        let persisted = UserDefaults(suiteName: prefix)!
        #expect(persisted.object(forKey: "\(prefix).lastAttempt") as? Date == date)
        #expect(persisted.object(forKey: "\(prefix).lastSuccess") as? Date == date)
        persisted.removePersistentDomain(forName: prefix)
        removeTestPersistence(prefix)
    }

    @Test func recentSuccessfulCheckSkipsWorkButManualCheckBypassesSchedule() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let previousCheck = date.addingTimeInterval(-60 * 60)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        UserDefaults(suiteName: prefix)!.set(previousCheck, forKey: "\(prefix).lastSuccess")

        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: ["yt-dlp 2026.7.4"]),
            .success(output: [#"{"formulae":[],"casks":[]}"#]),
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let automaticResult = await service.checkForUpdates()
        #expect(automaticResult == .skipped(
            nextCheck: previousCheck.addingTimeInterval(24 * 60 * 60)
        ))
        #expect(await runner.arguments.isEmpty)

        let manualResult = await service.checkForUpdates(force: true)
        #expect(manualResult == .partiallyManaged(
            managedComponents: [.ytDLP],
            updatedComponents: [],
            checkedAt: date
        ))
        #expect(await runner.arguments.count == 6)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func failureUsesShortRetryCadenceWithoutExposingCommandOutput() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"

        let runner = StubProcessRunner(responses: [
            .failure(error: ["raw package manager failure"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        let retryAfter = date.addingTimeInterval(6 * 60 * 60)

        let failedResult = await service.checkForUpdates()
        #expect(failedResult == .failed(retryAfter: retryAfter))
        #expect(!failedResult.message.contains("raw package manager failure"))
        let persisted = UserDefaults(suiteName: prefix)!
        #expect(persisted.object(forKey: "\(prefix).lastAttempt") as? Date == date)
        #expect(persisted.object(forKey: "\(prefix).lastSuccess") == nil)

        let immediateRetry = await service.checkForUpdates()
        #expect(immediateRetry == .skipped(nextCheck: retryAfter))
        #expect(await runner.arguments == [["update"]])
        persisted.removePersistentDomain(forName: prefix)
        removeTestPersistence(prefix)
    }

    @Test func failedForcedCheckOverridesOlderSuccessfulCadence() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        UserDefaults(suiteName: prefix)!.set(
            date.addingTimeInterval(-60 * 60),
            forKey: "\(prefix).lastSuccess"
        )
        let runner = StubProcessRunner(responses: [
            .failure(error: ["network unavailable"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        #expect(await service.checkForUpdates(force: true) == .failed(
            retryAfter: date.addingTimeInterval(6 * 60 * 60)
        ))
        #expect(await service.checkForUpdates() == .skipped(
            nextCheck: date.addingTimeInterval(6 * 60 * 60)
        ))
        #expect(await runner.arguments == [["update"]])
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func nonHomebrewToolsAreNeverDeletedOrReinstalled() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"

        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: []),
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let result = await service.checkForUpdates()

        #expect(result == .notManaged(checkedAt: date))
        let arguments = await runner.arguments
        #expect(arguments.count == 5)
        #expect(!arguments.joined().contains("uninstall"))
        #expect(!arguments.joined().contains("reinstall"))
        #expect(!arguments.joined().contains("upgrade"))
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func simultaneousRequestsShareOneHomebrewCheck() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(
            responses: [
                .success(),
                .success(output: [
                    "yt-dlp 2026.7.4",
                    "ffmpeg 8.1.2",
                    "deno 2.9.2",
                ]),
                .success(output: [#"{"formulae":[],"casks":[]}"#]),
                .success(output: ["2026.7.4"]),
                .success(output: ["ffmpeg version 8.1.2"]),
                .success(output: ["deno 2.9.2"]),
            ],
            firstInvocationDelay: .milliseconds(100)
        )
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let results = await withTaskGroup(
            of: DownloadEngineUpdateResult.self,
            returning: [DownloadEngineUpdateResult].self
        ) { group in
            for _ in 0..<24 {
                group.addTask {
                    await service.checkForUpdates(force: true)
                }
            }

            var values: [DownloadEngineUpdateResult] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        #expect(results.count == 24)
        #expect(results.allSatisfy { $0 == .upToDate(checkedAt: date) })
        #expect(await runner.arguments.count == 6)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func pinnedOutdatedFormulaIsReportedInsteadOfUpToDate() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: [
                "yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2",
            ]),
            .outdated(output: [
                #"{"formulae":[{"name":"ffmpeg","pinned":true}],"casks":[]}"#,
            ]),
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        #expect(await service.checkForUpdates() == .updatesBlocked(
            components: [.ffmpeg],
            checkedAt: date
        ))
        #expect(!(await runner.arguments).joined().contains("upgrade"))
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func cancellingAwaitingCallerCancelsSharedHomebrewWork() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(
            responses: [.success()],
            firstInvocationDelay: .seconds(60)
        )
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let caller = Task {
            await service.checkForUpdates(force: true)
        }
        await runner.waitForFirstInvocation()
        caller.cancel()
        let result = await caller.value

        #expect(result == .failed(retryAfter: date.addingTimeInterval(6 * 60 * 60)))
        #expect(await runner.observedCancellation)
        #expect(await runner.arguments == [["update"]])
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func cancellingOneCoalescedCallerDoesNotCancelSharedHomebrewWork() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(
            responses: [
                .success(),
                .success(output: [
                    "yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2",
                ]),
                .success(output: [#"{"formulae":[],"casks":[]}"#]),
                .success(output: ["2026.7.4"]),
                .success(output: ["ffmpeg version 8.1.2"]),
                .success(output: ["deno 2.9.2"]),
            ],
            firstInvocationDelay: .milliseconds(150)
        )
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let callers = (0..<12).map { _ in
            Task { await service.checkForUpdates(force: true) }
        }
        await runner.waitForFirstInvocation()
        try? await Task.sleep(for: .milliseconds(30))
        callers[0].cancel()

        var results: [DownloadEngineUpdateResult] = []
        for caller in callers {
            results.append(await caller.value)
        }

        #expect(results.allSatisfy { $0 == .upToDate(checkedAt: date) })
        #expect(!(await runner.observedCancellation))
        #expect(await runner.arguments.count == 6)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func failedHealthCheckDoesNotRecordSuccessfulDailyCheck() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: ["yt-dlp 2026.7.4"]),
            .success(output: [#"{"formulae":[],"casks":[]}"#]),
            .failure(error: ["broken executable"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let result = await service.checkForUpdates()

        #expect(result == .unhealthy(
            components: [.ytDLP],
            retryAfter: date.addingTimeInterval(6 * 60 * 60)
        ))
        let persisted = UserDefaults(suiteName: prefix)!
        #expect(persisted.object(forKey: "\(prefix).lastAttempt") as? Date == date)
        #expect(persisted.object(forKey: "\(prefix).lastSuccess") == nil)
        #expect(await runner.arguments.suffix(3) == [
            ["--version"], ["-version"], ["--version"],
        ])
        persisted.removePersistentDomain(forName: prefix)
        removeTestPersistence(prefix)
    }

    @Test func managerLatchesAFailedHealthCheckAsNotReady() async throws {
        let fixture = try EngineToolFixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: [
                "yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2",
            ]),
            .success(output: [#"{"formulae":[],"casks":[]}"#]),
            .failure(error: ["broken yt-dlp"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let updater = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        let manager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: URL(fileURLWithPath: "/bin/echo")),
            updater: updater
        )

        #expect(manager.currentStatus().isReady)
        let result = await manager.checkForUpdates(force: true)
        #expect(result == .unhealthy(
            components: [.ytDLP],
            retryAfter: date.addingTimeInterval(6 * 60 * 60)
        ))
        #expect(!manager.currentStatus().isReady)
        #expect(manager.currentStatus().missingComponents == [ToolBinary.ytDLP.displayName])
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func unhealthyStateSurvivesRelaunchAndClearsAfterRepair() async throws {
        let fixture = try EngineToolFixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let failingRunner = StubProcessRunner(responses: [
            .success(),
            .success(output: [
                "yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2",
            ]),
            .success(output: [#"{"formulae":[],"casks":[]}"#]),
            .failure(error: ["broken yt-dlp"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let firstUpdater = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: failingRunner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        let firstManager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: URL(fileURLWithPath: "/bin/echo")),
            updater: firstUpdater
        )

        _ = await firstManager.checkForUpdates(force: true)
        #expect(!firstManager.currentStatus().isReady)

        let repairedRunner = StubProcessRunner(responses: [
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let relaunchedUpdater = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: repairedRunner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date.addingTimeInterval(60) }
        )
        let relaunchedManager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: URL(fileURLWithPath: "/bin/echo")),
            updater: relaunchedUpdater
        )

        #expect(!relaunchedManager.currentStatus().isReady)
        #expect(await relaunchedManager.checkForUpdates(force: true) == .recovered(
            checkedAt: date.addingTimeInterval(60)
        ))
        #expect(relaunchedManager.currentStatus().isReady)
        #expect(await repairedRunner.arguments == [
            ["--version"], ["-version"], ["--version"],
        ])
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func managerRejectsInstallWhileAnUpdateOwnsTheEngine() async throws {
        let fixture = try EngineToolFixture()
        defer { fixture.remove() }
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(
            responses: [.success()],
            firstInvocationDelay: .seconds(60)
        )
        let updater = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
        persistenceDirectoryURL: testPersistenceDirectory(prefix)
        )
        let manager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: URL(fileURLWithPath: "/bin/echo")),
            updater: updater
        )

        let update = Task { await manager.checkForUpdates(force: true) }
        await runner.waitForFirstInvocation()
        do {
            try await manager.prepare { _ in }
            Issue.record("Expected the engine operation gate to reject preparation")
        } catch let error as DownloadEngineError {
            #expect(error == .operationInProgress)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        update.cancel()
        _ = await update.value
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func failedUpgradeStillValidatesAndLatchesMutatedEngine() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(responses: [
            .success(),
            .success(output: [
                "yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2",
            ]),
            .outdated(output: [
                #"{"formulae":[{"name":"yt-dlp","pinned":false}],"casks":[]}"#,
            ]),
            .failure(error: ["upgrade failed after changing a keg"]),
            .failure(error: ["broken yt-dlp"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        let result = await service.checkForUpdates(force: true)

        #expect(result == .unhealthy(
            components: [.ytDLP],
            retryAfter: date.addingTimeInterval(6 * 60 * 60)
        ))
        let persisted = UserDefaults(suiteName: prefix)!
        #expect(service.healthStore.state() == .unhealthy([.ytDLP]))
        #expect(FileManager.default.fileExists(
            atPath: service.healthStore.journalURL.path
        ))
        #expect(persisted.data(forKey: "\(prefix).healthState") == nil)
        #expect(persisted.object(forKey: "\(prefix).mutationPendingHealthCheck") == nil)
        #expect(persisted.object(forKey: "\(prefix).unhealthyComponents") == nil)
        #expect(await runner.arguments.suffix(4) == [
            ["upgrade", "--formula", "--no-ask", "yt-dlp"],
            ["--version"], ["-version"], ["--version"],
        ])
        persisted.removePersistentDomain(forName: prefix)
        removeTestPersistence(prefix)
    }

    @Test func pendingMutationIsNotReadyAndRecoversOfflineBeforeUpdateMetadata() async throws {
        let fixture = try EngineToolFixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let setupDefaults = UserDefaults(suiteName: prefix)!
        setupDefaults.set(date, forKey: "\(prefix).lastSuccess")
        let interruptedUpdater = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: StubProcessRunner(responses: []),
            locator: fixture.locator,
            defaults: setupDefaults,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        try interruptedUpdater.healthStore.markMutationPending()

        let runner = StubProcessRunner(responses: [
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let relaunchedUpdater = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: runner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        let manager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: nil, environment: [:]),
            updater: relaunchedUpdater
        )

        #expect(!manager.currentStatus().isReady)
        #expect(manager.currentStatus().missingComponents.count == ToolBinary.allCases.count)
        let result = await manager.checkForUpdates(force: false)

        #expect(result == .recovered(checkedAt: date))
        #expect(await runner.arguments == [
            ["--version"], ["-version"], ["--version"],
        ])
        #expect(manager.currentStatus().isReady)
        #expect(relaunchedUpdater.healthStore.state() == .ready)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func successfulExitWithoutRecognizableVersionOutputIsUnhealthy() async {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let runner = StubProcessRunner(responses: [
            .success(output: ["random-tool-1.2"]),
            .success(output: ["not ffmpeg output"]),
            .success(output: ["deno stable"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        #expect(await service.assessHealth() == .unhealthy(
            components: ToolBinary.allCases,
            retryAfter: date.addingTimeInterval(6 * 60 * 60)
        ))
        #expect(service.healthStore.state() == .unhealthy(ToolBinary.allCases))
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func freshInstallIsHealthCheckedBeforeItBecomesReady() async throws {
        let fixture = try FreshInstallEngineFixture(brokenTool: .ffmpeg)
        defer { fixture.remove() }
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let updater = HomebrewEngineUpdateService(
            homebrewURL: fixture.homebrewURL,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix)
        )
        let manager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(
                homebrewURL: fixture.homebrewURL,
                environment: [:]
            ),
            updater: updater
        )

        #expect(!manager.currentStatus().isReady)
        do {
            try await manager.prepare { _ in }
            Issue.record("Expected the newly installed broken tool to fail health assessment")
        } catch let error as DownloadEngineError {
            #expect(error == .automaticRepairFailed(
                components: [ToolBinary.ffmpeg.displayName]
            ))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(updater.healthStore.state() == .unhealthy([.ffmpeg]))
        #expect(!manager.currentStatus().isReady)
        #expect(manager.currentStatus().missingComponents == [ToolBinary.ffmpeg.displayName])

        try fixture.repair(.ffmpeg)
        try await manager.prepare { _ in }
        #expect(manager.currentStatus().isReady)
        #expect(updater.healthStore.state() == .ready)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }

    @Test func corruptJournalFailsClosedAndRecoversOnlyAfterLocalHealthChecks() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let directory = testPersistenceDirectory(prefix)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let journalURL = directory.appendingPathComponent("homebrew-engine-health.json")
        try Data("{not-valid-json".utf8).write(to: journalURL)
        defer {
            UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
            removeTestPersistence(prefix)
        }

        let runner = StubProcessRunner(responses: [
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: directory,
            now: { date }
        )

        #expect(service.healthStore.state() == .mutationPending)
        #expect(await service.checkForUpdates() == .recovered(checkedAt: date))
        #expect(service.healthStore.state() == .ready)
        #expect(await runner.arguments == [["--version"], ["-version"], ["--version"]])

        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test func crossInstanceLeasePreventsASecondMutation() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let directory = testPersistenceDirectory(prefix)
        defer {
            UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
            removeTestPersistence(prefix)
        }

        let first = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: directory,
            now: { date }
        )
        let secondRunner = StubProcessRunner(responses: [.success()])
        let second = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: secondRunner,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: directory,
            now: { date }
        )

        let acquiredLease = try first.mutationLock.tryAcquire()
        let lease = try #require(acquiredLease)
        #expect(await second.checkForUpdates(force: true) == .busy)
        #expect(await secondRunner.arguments.isEmpty)
        withExtendedLifetime(lease) {}
    }

    @Test func unhealthyAutomaticAssessmentUsesRetryCadenceButManualBypassesIt() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let previousAttempt = date.addingTimeInterval(-60 * 60)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
            removeTestPersistence(prefix)
        }

        let runner = StubProcessRunner(responses: [
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let service = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: runner,
            toolOverrides: testToolOverrides,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        try service.healthStore.recordAssessment(
            unhealthyComponents: [.ytDLP],
            attemptedAt: previousAttempt
        )

        #expect(await service.checkForUpdates(force: false) == .skipped(
            nextCheck: previousAttempt.addingTimeInterval(6 * 60 * 60)
        ))
        #expect(await runner.arguments.isEmpty)
        #expect(await service.checkForUpdates(force: true) == .recovered(checkedAt: date))
        #expect(await runner.arguments == [["--version"], ["-version"], ["--version"]])
    }

    @Test func legacyUnsafeMarkerMigratesToDurableJournalBeforeRecovery() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        UserDefaults(suiteName: prefix)!.set(
            true,
            forKey: "\(prefix).mutationPendingHealthCheck"
        )
        defer {
            UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
            removeTestPersistence(prefix)
        }

        let service = HomebrewEngineUpdateService(
            homebrewURL: nil,
            runner: StubProcessRunner(responses: []),
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )

        #expect(service.healthStore.state() == .mutationPending)
        #expect(FileManager.default.fileExists(atPath: service.healthStore.journalURL.path))
        #expect(UserDefaults(suiteName: prefix)!.object(
            forKey: "\(prefix).mutationPendingHealthCheck"
        ) == nil)
    }

    @Test func prepareRepairsOnlyTheUnhealthyManagedFormulaAndRechecksEverything() async throws {
        let fixture = try EngineToolFixture()
        defer { fixture.remove() }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prefix = "test.engine-update.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
            removeTestPersistence(prefix)
        }

        let runner = StubProcessRunner(responses: [
            .success(output: ["2026.7.4"]),
            .failure(error: ["broken ffmpeg"]),
            .success(output: ["deno 2.9.2"]),
            .success(output: ["yt-dlp 2026.7.4", "ffmpeg 8.1.2", "deno 2.9.2"]),
            .success(),
            .success(output: ["2026.7.4"]),
            .success(output: ["ffmpeg version 8.1.2"]),
            .success(output: ["deno 2.9.2"]),
        ])
        let updater = HomebrewEngineUpdateService(
            homebrewURL: URL(fileURLWithPath: "/bin/echo"),
            runner: runner,
            locator: fixture.locator,
            defaults: UserDefaults(suiteName: prefix)!,
            persistenceKeyPrefix: prefix,
            persistenceDirectoryURL: testPersistenceDirectory(prefix),
            now: { date }
        )
        let manager = HomebrewDownloadEngineManager(
            locator: fixture.locator,
            installer: ToolInstallService(homebrewURL: URL(fileURLWithPath: "/bin/echo")),
            updater: updater
        )

        try await manager.prepare { _ in }

        #expect(updater.healthStore.state() == .ready)
        #expect(await runner.arguments == [
            ["--version"], ["-version"], ["--version"],
            ["list", "--formula", "--versions"],
            ["reinstall", "--formula", "--no-ask", "ffmpeg"],
            ["--version"], ["-version"], ["--version"],
        ])
    }

    @Test @MainActor func appModelRefreshesReadinessAfterEveryCompletedResult() async {
        let prefix = "test.engine-update.\(UUID().uuidString)"
        let manager = ReadinessChangingEngineManager()
        let defaults = UserDefaults(suiteName: prefix)!
        let model = AppModel(
            downloadBackend: IdleDownloadBackend(),
            engineManager: manager,
            preferences: DownloadPreferencesStore(
                defaults: defaults,
                fallbackDirectory: FileManager.default.temporaryDirectory
            ),
            defaults: defaults
        )

        #expect(model.engineStatus.isReady)
        model.updateEngineNow()
        for _ in 0..<1_000 where model.engineUpdateResult == nil {
            await Task.yield()
        }

        #expect(model.engineUpdateResult == manager.result)
        #expect(!model.engineStatus.isReady)
        UserDefaults(suiteName: prefix)!.removePersistentDomain(forName: prefix)
    }
}

private actor StubProcessRunner: ProcessRunning {
    private var responses: [SubprocessResult]
    private let firstInvocationDelay: Duration?
    private(set) var invocations: [ProcessInvocation] = []
    private(set) var timeouts: [Duration?] = []
    private(set) var observedCancellation = false

    var arguments: [[String]] {
        invocations.map(\.arguments)
    }

    func waitForFirstInvocation() async {
        while invocations.isEmpty {
            await Task.yield()
        }
    }

    init(
        responses: [SubprocessResult],
        firstInvocationDelay: Duration? = nil
    ) {
        self.responses = responses
        self.firstInvocationDelay = firstInvocationDelay
    }

    func run(
        _ invocation: ProcessInvocation,
        timeout: Duration?,
        onLine: @escaping @Sendable (SubprocessStream, String) -> Void
    ) async throws -> SubprocessResult {
        invocations.append(invocation)
        timeouts.append(timeout)
        if invocations.count == 1, let firstInvocationDelay {
            do {
                try await Task.sleep(for: firstInvocationDelay)
            } catch is CancellationError {
                observedCancellation = true
                throw CancellationError()
            }
        }
        guard !responses.isEmpty else {
            return .failure(error: ["Unexpected invocation"])
        }
        return responses.removeFirst()
    }
}

private let testToolOverrides: [ToolBinary: URL] = [
    .ytDLP: URL(fileURLWithPath: "/bin/echo"),
    .ffmpeg: URL(fileURLWithPath: "/bin/echo"),
    .deno: URL(fileURLWithPath: "/bin/echo"),
]

private func testPersistenceDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vidindir-engine-update-tests", isDirectory: true)
        .appendingPathComponent(prefix, isDirectory: true)
}

private func removeTestPersistence(_ prefix: String) {
    try? FileManager.default.removeItem(at: testPersistenceDirectory(prefix))
}

private struct EngineToolFixture {
    let directory: URL
    let locator: BinaryLocator

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-engine-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        for tool in ToolBinary.allCases {
            let url = directory.appendingPathComponent(tool.rawValue)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        locator = BinaryLocator(
            environment: [:],
            fixedSearchDirectories: [directory],
            includeBundledTools: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FreshInstallEngineFixture {
    let root: URL
    let toolsDirectory: URL
    let templatesDirectory: URL
    let homebrewURL: URL
    let locator: BinaryLocator

    init(brokenTool: ToolBinary? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidindir-fresh-install-\(UUID().uuidString)", isDirectory: true)
        toolsDirectory = root.appendingPathComponent("tools", isDirectory: true)
        templatesDirectory = root.appendingPathComponent("templates", isDirectory: true)
        homebrewURL = root.appendingPathComponent("brew")
        try FileManager.default.createDirectory(
            at: toolsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: templatesDirectory,
            withIntermediateDirectories: true
        )

        for tool in ToolBinary.allCases {
            let template = templatesDirectory.appendingPathComponent(tool.rawValue)
            try Self.writeTool(tool, to: template, recognizable: tool != brokenTool)
        }

        locator = BinaryLocator(
            environment: [:],
            fixedSearchDirectories: [toolsDirectory],
            includeBundledTools: false
        )

        let copyCommands = ToolBinary.allCases.map { tool -> String in
            let source = templatesDirectory.appendingPathComponent(tool.rawValue).path
            let destination = toolsDirectory.appendingPathComponent(tool.rawValue).path
            return "/bin/cp \(shellQuote(source)) \(shellQuote(destination))"
        }.joined(separator: "\n")
        let brewScript = """
        #!/bin/sh
        set -eu
        \(copyCommands)
        """
        try Self.writeExecutable(brewScript, to: homebrewURL)
    }

    func repair(_ tool: ToolBinary) throws {
        try Self.writeTool(
            tool,
            to: toolsDirectory.appendingPathComponent(tool.rawValue),
            recognizable: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func writeTool(
        _ tool: ToolBinary,
        to url: URL,
        recognizable: Bool
    ) throws {
        let output: String
        if !recognizable {
            output = ""
        } else {
            switch tool {
            case .ytDLP:
                output = "2026.7.4"
            case .ffmpeg:
                output = "ffmpeg version 8.1.2"
            case .deno:
                output = "deno 2.9.2"
            }
        }
        let script = """
        #!/bin/sh
        /usr/bin/printf '%s\\n' \(shellQuote(output))
        """
        try writeExecutable(script, to: url)
    }

    private static func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}

private final class ReadinessChangingEngineManager: DownloadEngineManaging, @unchecked Sendable {
    let result = DownloadEngineUpdateResult.failed(
        retryAfter: Date(timeIntervalSince1970: 1_800_021_600)
    )
    private let lock = NSLock()
    private var status = DownloadEngineStatus(isReady: true)

    var canPrepareAutomatically: Bool { false }
    var setupGuideURL: URL? { nil }

    func currentStatus() -> DownloadEngineStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {}

    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        setStatus(DownloadEngineStatus(
            isReady: false,
            missingComponents: [ToolBinary.ytDLP.displayName]
        ))
        return result
    }

    private func setStatus(_ newValue: DownloadEngineStatus) {
        lock.lock()
        status = newValue
        lock.unlock()
    }
}

private final class IdleDownloadBackend: DownloadBackend, @unchecked Sendable {
    var isDownloading: Bool { false }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        throw CancellationError()
    }

    func cancelCurrentDownload() {}
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private extension SubprocessResult {
    static func success(output: [String] = []) -> SubprocessResult {
        SubprocessResult(
            exitCode: 0,
            terminationReason: .exit,
            standardOutput: output,
            standardError: []
        )
    }

    static func failure(error: [String]) -> SubprocessResult {
        SubprocessResult(
            exitCode: 1,
            terminationReason: .exit,
            standardOutput: [],
            standardError: error
        )
    }

    static func outdated(output: [String]) -> SubprocessResult {
        SubprocessResult(
            exitCode: 1,
            terminationReason: .exit,
            standardOutput: output,
            standardError: []
        )
    }
}
