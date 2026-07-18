import Foundation
import Testing
@testable import Vidindir

@Suite("App update installation gate")
@MainActor
struct AppUpdateInstallationGateTests {
    @Test("implements Sparkle's postponement delegate selector")
    func implementsSparkleDelegateSelector() {
        let controller = AppUpdateController(bundle: .main)
        let selector = NSSelectorFromString(
            "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:"
        )

        #expect(controller.responds(to: selector))
    }

    @Test("does not intercept installation while the app is idle")
    func doesNotPostponeWhileIdle() {
        let gate = AppUpdateInstallationGate()
        var installationCalls = 0

        let postponed = gate.shouldPostponeInstallation(isBusy: false) {
            installationCalls += 1
        }

        #expect(!postponed)
        #expect(installationCalls == 0)
    }

    @Test("postpones installation until active work finishes")
    func postponesUntilIdle() {
        let gate = AppUpdateInstallationGate()
        var installationCalls = 0

        let postponed = gate.shouldPostponeInstallation(isBusy: true) {
            installationCalls += 1
        }

        #expect(postponed)
        gate.resumeInstallationIfPossible(isBusy: true)
        #expect(installationCalls == 0)

        gate.resumeInstallationIfPossible(isBusy: false)
        #expect(installationCalls == 1)

        gate.resumeInstallationIfPossible(isBusy: false)
        #expect(installationCalls == 1)
    }
}
