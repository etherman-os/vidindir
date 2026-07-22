import Foundation
import Testing
@testable import Vidindir

@Suite("App model engine update scheduler")
@MainActor
struct AppModelEngineUpdateSchedulerTests {
    @Test func bootstrapStartsOneImmediateAutomaticCheck() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = SchedulerEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        fixture.model?.bootstrap()

        let started = await eventually {
            let snapshot = await probe.snapshot()
            return snapshot.forceValues == [false]
                && sleeper.pendingCount == 1
                && fixture.model?.isCheckingEngineUpdates == false
        }
        #expect(started)
        #expect(sleeper.requestedIntervals == [.seconds(3_600)])

        let weakModel = WeakReference(fixture.model)
        fixture.model = nil
        let stopped = await eventually {
            weakModel.value == nil && sleeper.cancellationCount == 1
        }
        #expect(stopped)
        #expect(sleeper.pendingCount == 0)
    }

    @Test func eachPeriodicWakeStartsTheNextAutomaticCheck() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = SchedulerEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        #expect(await waitForCompletedChecks(
            1,
            model: fixture.model,
            probe: probe,
            sleeper: sleeper
        ))

        #expect(sleeper.wakeNext())
        #expect(await waitForCompletedChecks(
            2,
            model: fixture.model,
            probe: probe,
            sleeper: sleeper
        ))

        let snapshot = await probe.snapshot()
        #expect(snapshot.forceValues == [false, false])
        #expect(sleeper.requestedIntervals == [.seconds(3_600), .seconds(3_600)])

        fixture.model = nil
        #expect(await eventually { sleeper.cancellationCount == 1 })
    }

    @Test func busyDownloadAndEngineInstallationDeferScheduledChecks() async {
        let schedulerSleeper = ControlledSchedulerSleeper()
        let preparationSleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = SchedulerEngineManager(
            probe: probe,
            preparationSleeper: preparationSleeper
        )
        let backend = MutableSchedulerDownloadBackend(isDownloading: true)
        let fixture = makeFixture(
            backend: backend,
            manager: manager,
            sleeper: schedulerSleeper
        )
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        let launchWasDeferred = await eventually {
            schedulerSleeper.pendingCount == 1
        }
        #expect(launchWasDeferred)
        #expect(await probe.snapshot().forceValues.isEmpty)

        backend.setDownloading(false)
        fixture.model?.prepareEngine()
        let installStarted = await eventually {
            fixture.model?.isInstallingTools == true && preparationSleeper.pendingCount == 1
        }
        #expect(installStarted)

        #expect(schedulerSleeper.wakeNext())
        let installWakeWasDeferred = await eventually {
            schedulerSleeper.requestedIntervals.count == 2
        }
        #expect(installWakeWasDeferred)
        #expect(await probe.snapshot().forceValues.isEmpty)

        #expect(preparationSleeper.wakeNext())
        #expect(await eventually { fixture.model?.isInstallingTools == false })

        #expect(schedulerSleeper.wakeNext())
        #expect(await waitForCompletedChecks(
            1,
            model: fixture.model,
            probe: probe,
            sleeper: schedulerSleeper
        ))
        #expect(await probe.snapshot().forceValues == [false])

        fixture.model = nil
        #expect(await eventually { schedulerSleeper.cancellationCount == 1 })
    }

    @Test func periodicAndManualTriggersNeverOverlapAnActiveCheck() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe(blocksChecks: true)
        let manager = SchedulerEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        let firstCheckStarted = await eventually {
            let snapshot = await probe.snapshot()
            return snapshot.activeCount == 1 && sleeper.pendingCount == 1
        }
        #expect(firstCheckStarted)

        for expectedSleepCount in 2...4 {
            #expect(sleeper.wakeNext())
            #expect(await eventually {
                sleeper.requestedIntervals.count == expectedSleepCount
            })
            fixture.model?.updateEngineNow()
        }

        var snapshot = await probe.snapshot()
        #expect(snapshot.forceValues == [false])
        #expect(snapshot.activeCount == 1)
        #expect(snapshot.maximumActiveCount == 1)

        await probe.releaseNextCheck()
        let firstCheckFinished = await eventually {
            let current = await probe.snapshot()
            return current.activeCount == 0 && fixture.model?.isCheckingEngineUpdates == false
        }
        #expect(firstCheckFinished)

        #expect(sleeper.wakeNext())
        let secondCheckStarted = await eventually {
            let current = await probe.snapshot()
            return current.forceValues.count == 2 && current.activeCount == 1
        }
        #expect(secondCheckStarted)

        snapshot = await probe.snapshot()
        #expect(snapshot.forceValues == [false, false])
        #expect(snapshot.maximumActiveCount == 1)

        await probe.releaseNextCheck()
        #expect(await eventually {
            let current = await probe.snapshot()
            return current.activeCount == 0 && fixture.model?.isCheckingEngineUpdates == false
        })

        fixture.model = nil
        #expect(await eventually { sleeper.cancellationCount == 1 })
    }

    @Test func releasingTheModelCancelsTheSleepingSchedulerTask() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = SchedulerEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        #expect(await waitForCompletedChecks(
            1,
            model: fixture.model,
            probe: probe,
            sleeper: sleeper
        ))

        let weakModel = WeakReference(fixture.model)
        fixture.model = nil

        let cancelled = await eventually {
            weakModel.value == nil
                && sleeper.pendingCount == 0
                && sleeper.cancellationCount == 1
        }
        #expect(cancelled)
    }

    @Test func activeEngineCheckDoesNotRetainTheModel() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe(blocksChecks: true)
        let manager = SchedulerEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.bootstrap()
        #expect(await eventually {
            let snapshot = await probe.snapshot()
            return snapshot.activeCount == 1 && sleeper.pendingCount == 1
        })

        let weakModel = WeakReference(fixture.model)
        fixture.model = nil

        #expect(await eventually {
            weakModel.value == nil
                && sleeper.pendingCount == 0
                && sleeper.cancellationCount == 1
        })

        // The deliberately cancellation-insensitive fake manager must be
        // released so its detached task does not outlive the test process.
        await probe.releaseNextCheck()
    }

    @Test func delayedInstallOutputCannotOverwriteTheCompletedState() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = DelayedOutputEngineManager(probe: probe)
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        fixture.model?.prepareEngine()
        #expect(await eventually {
            fixture.model?.isInstallingTools == false
                && fixture.model?.toolInstallStatus == "Tools are ready."
        })

        manager.emitDelayedOutput("Installing stale package output")
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(fixture.model?.toolInstallStatus == "Tools are ready.")
        #expect(fixture.model?.processLog.isEmpty == true)
        fixture.model = nil
    }

    @Test func activeDownloadDoesNotRetainTheModel() async {
        let sleeper = ControlledSchedulerSleeper()
        let probe = EngineCheckProbe()
        let manager = SchedulerEngineManager(probe: probe)
        let backend = BlockingSchedulerDownloadBackend()
        let fixture = makeFixture(
            backend: backend,
            manager: manager,
            sleeper: sleeper
        )
        defer { fixture.removeDefaults() }

        fixture.model?.linkText = "https://example.com/video"
        fixture.model?.startDownload()
        #expect(await eventually { backend.isDownloading })

        let weakModel = WeakReference(fixture.model)
        fixture.model = nil
        #expect(await eventually { weakModel.value == nil })

        // Release the deliberately cancellation-insensitive backend so the
        // detached operation cannot outlive the test process.
        backend.releaseDownload()
    }

    @Test func unrecoverableEngineFailureSwitchesToTheManualGuide() async {
        let sleeper = ControlledSchedulerSleeper()
        let manager = FailingRepairEngineManager()
        let fixture = makeFixture(manager: manager, sleeper: sleeper)
        defer { fixture.removeDefaults() }

        #expect(fixture.model?.engineSetupTitle == "Engine repair")
        #expect(fixture.model?.engineSetupActionLabel == "Repair Engine")
        fixture.model?.prepareEngine()

        #expect(await eventually {
            fixture.model?.isInstallingTools == false
                && fixture.model?.requiresManualEngineRepair == true
        })
        #expect(fixture.model?.canPrepareEngine == true)
        #expect(fixture.model?.engineSetupActionLabel == "Recheck Engine")
        #expect(fixture.model?.missingToolsDescription.contains("manual repair") == true)
        #expect(fixture.model?.alert?.title == "Tool setup failed")
        fixture.model = nil
    }

    private func makeFixture(
        backend: any DownloadBackend = MutableSchedulerDownloadBackend(),
        manager: any DownloadEngineManaging,
        sleeper: ControlledSchedulerSleeper
    ) -> SchedulerModelFixture {
        let suiteName = "test.app-model-engine-scheduler.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let model = AppModel(
            downloadBackend: backend,
            engineManager: manager,
            preferences: DownloadPreferencesStore(
                defaults: defaults,
                fallbackDirectory: FileManager.default.temporaryDirectory
            ),
            defaults: defaults,
            engineUpdateSchedule: EngineUpdateSchedule(
                interval: .seconds(3_600),
                sleep: { duration in
                    try await sleeper.sleep(for: duration)
                }
            )
        )
        return SchedulerModelFixture(
            model: model,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func waitForCompletedChecks(
        _ expectedCount: Int,
        model: AppModel?,
        probe: EngineCheckProbe,
        sleeper: ControlledSchedulerSleeper
    ) async -> Bool {
        await eventually {
            let snapshot = await probe.snapshot()
            return snapshot.forceValues.count == expectedCount
                && snapshot.activeCount == 0
                && sleeper.pendingCount == 1
                && model?.isCheckingEngineUpdates == false
        }
    }

    private func eventually(
        _ condition: @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private final class SchedulerModelFixture {
    var model: AppModel?
    let defaults: UserDefaults
    let suiteName: String

    init(model: AppModel, defaults: UserDefaults, suiteName: String) {
        self.model = model
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func removeDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class ControlledSchedulerSleeper: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var cancelledBeforeRegistration: Set<UUID> = []
    private var intervals: [Duration] = []
    private var cancellations = 0

    var requestedIntervals: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return intervals
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func sleep(for interval: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var wasAlreadyCancelled = false
                lock.lock()
                intervals.append(interval)
                if cancelledBeforeRegistration.remove(id) != nil {
                    wasAlreadyCancelled = true
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
                lock.unlock()

                if wasAlreadyCancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancel(id: id)
        }
    }

    @discardableResult
    func wakeNext() -> Bool {
        let continuation: CheckedContinuation<Void, any Error>?
        lock.lock()
        if waiters.isEmpty {
            continuation = nil
        } else {
            continuation = waiters.removeFirst().continuation
        }
        lock.unlock()
        continuation?.resume()
        return continuation != nil
    }

    private func cancel(id: UUID) {
        let continuation: CheckedContinuation<Void, any Error>?
        lock.lock()
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            continuation = waiters.remove(at: index).continuation
            cancellations += 1
        } else {
            continuation = nil
            cancelledBeforeRegistration.insert(id)
        }
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private struct EngineCheckSnapshot: Sendable {
    let forceValues: [Bool]
    let activeCount: Int
    let maximumActiveCount: Int
}

private actor EngineCheckProbe {
    private let blocksChecks: Bool
    private var forceValues: [Bool] = []
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(blocksChecks: Bool = false) {
        self.blocksChecks = blocksChecks
    }

    func performCheck(force: Bool) async {
        forceValues.append(force)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)

        if blocksChecks {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        activeCount -= 1
    }

    func releaseNextCheck() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func snapshot() -> EngineCheckSnapshot {
        EngineCheckSnapshot(
            forceValues: forceValues,
            activeCount: activeCount,
            maximumActiveCount: maximumActiveCount
        )
    }
}

private final class SchedulerEngineManager: DownloadEngineManaging, @unchecked Sendable {
    let canPrepareAutomatically: Bool
    let setupGuideURL: URL? = nil

    private let probe: EngineCheckProbe
    private let preparationSleeper: ControlledSchedulerSleeper?

    init(
        probe: EngineCheckProbe,
        preparationSleeper: ControlledSchedulerSleeper? = nil
    ) {
        self.probe = probe
        self.preparationSleeper = preparationSleeper
        canPrepareAutomatically = preparationSleeper != nil
    }

    func currentStatus() -> DownloadEngineStatus {
        DownloadEngineStatus(isReady: true)
    }

    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {
        if let preparationSleeper {
            try await preparationSleeper.sleep(for: .zero)
        }
    }

    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        await probe.performCheck(force: force)
        return .upToDate(checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

private final class DelayedOutputEngineManager: DownloadEngineManaging, @unchecked Sendable {
    let canPrepareAutomatically = true
    let setupGuideURL: URL? = nil

    private let probe: EngineCheckProbe
    private let lock = NSLock()
    private var outputHandler: (@Sendable (String) -> Void)?

    init(probe: EngineCheckProbe) {
        self.probe = probe
    }

    func currentStatus() -> DownloadEngineStatus {
        DownloadEngineStatus(isReady: true)
    }

    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {
        storeOutputHandler(onOutput)
    }

    private func storeOutputHandler(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        outputHandler = handler
        lock.unlock()
    }

    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        await probe.performCheck(force: force)
        return .upToDate(checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func emitDelayedOutput(_ line: String) {
        let handler: (@Sendable (String) -> Void)?
        lock.lock()
        handler = outputHandler
        lock.unlock()
        handler?(line)
    }
}

private final class FailingRepairEngineManager: DownloadEngineManaging, @unchecked Sendable {
    let canPrepareAutomatically = true
    let setupGuideURL = URL(
        string: "https://github.com/etherman-os/vidindir#troubleshooting-the-preview"
    )

    func currentStatus() -> DownloadEngineStatus {
        DownloadEngineStatus(
            isReady: false,
            missingComponents: [ToolBinary.ffmpeg.displayName],
            recoveryKind: .repairUnhealthyComponents
        )
    }

    func prepare(onOutput: @escaping @Sendable (String) -> Void) async throws {
        throw DownloadEngineError.manualRepairRequired(
            components: [ToolBinary.ffmpeg.displayName]
        )
    }

    func checkForUpdates(force: Bool) async -> DownloadEngineUpdateResult {
        .failed(retryAfter: Date(timeIntervalSince1970: 1_800_021_600))
    }
}

private final class MutableSchedulerDownloadBackend: DownloadBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var downloading: Bool

    init(isDownloading: Bool = false) {
        downloading = isDownloading
    }

    var isDownloading: Bool {
        lock.lock()
        defer { lock.unlock() }
        return downloading
    }

    func setDownloading(_ value: Bool) {
        lock.lock()
        downloading = value
        lock.unlock()
    }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        throw CancellationError()
    }

    func cancelCurrentDownload() {}
}

private final class BlockingSchedulerDownloadBackend: DownloadBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var downloading = false
    private var continuation: CheckedContinuation<Void, Never>?

    var isDownloading: Bool {
        lock.lock()
        defer { lock.unlock() }
        return downloading
    }

    func download(
        _ request: DownloadRequest,
        onEvent: @escaping EventHandler
    ) async throws -> DownloadRecord {
        await withCheckedContinuation { continuation in
            store(continuation)
        }

        markFinished()
        return DownloadRecord(
            sourceURL: request.sourceURL,
            format: request.format,
            destinationDirectory: request.destinationDirectory,
            title: "Fixture",
            status: .completed
        )
    }

    private func store(_ pending: CheckedContinuation<Void, Never>) {
        lock.lock()
        downloading = true
        continuation = pending
        lock.unlock()
    }

    private func markFinished() {
        lock.lock()
        downloading = false
        lock.unlock()
    }

    func cancelCurrentDownload() {
        // Intentionally ignores cancellation to prove AppModel does not rely
        // on backend cooperation for its own lifetime.
    }

    func releaseDownload() {
        let pending: CheckedContinuation<Void, Never>?
        lock.lock()
        pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
