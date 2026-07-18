import AppKit
import Combine
import Foundation
import Sparkle

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    init?(infoDictionary: [String: Any]?) {
        guard
            let infoDictionary,
            let feedString = infoDictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feedString),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            let publicEDKey = infoDictionary["SUPublicEDKey"] as? String,
            let decodedKey = Data(base64Encoded: publicEDKey),
            decodedKey.count == 32,
            infoDictionary["SUAllowsAutomaticUpdates"] as? Bool == true,
            infoDictionary["SURequireSignedFeed"] as? Bool == true,
            infoDictionary["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
            infoDictionary["SUEnableAutomaticChecks"] as? Bool == true,
            infoDictionary["SUAutomaticallyUpdate"] as? Bool == true
        else {
            return nil
        }

        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }
}

/// Supplies only the activity state Sparkle needs to make a safe installation
/// decision. Update checks and downloads are intentionally not gated.
@MainActor
protocol AppUpdateActivityProviding: AnyObject {
    var shouldDeferAppUpdateInstallation: Bool { get }
    var appUpdateActivityChanges: AnyPublisher<Void, Never> { get }
}

/// Retains Sparkle's one-shot continuation while product work is still active.
/// Keeping this policy independent from Sparkle makes its behavior deterministic
/// and unit-testable.
@MainActor
final class AppUpdateInstallationGate {
    private var pendingInstallHandler: (() -> Void)?

    func shouldPostponeInstallation(
        isBusy: Bool,
        installHandler: @escaping () -> Void
    ) -> Bool {
        guard isBusy else { return false }
        pendingInstallHandler = installHandler
        return true
    }

    func resumeInstallationIfPossible(isBusy: Bool) {
        guard !isBusy, let installHandler = pendingInstallHandler else { return }
        pendingInstallHandler = nil
        installHandler()
    }
}

/// Owns Sparkle's standard updater for the lifetime of the application.
///
/// Sparkle only starts when the host bundle contains the complete strict update
/// policy, an HTTPS appcast URL, and a valid Ed25519 public key. `swift run` and
/// tests remain usable without an application bundle and explain that limitation
/// if the user invokes the menu command.
@MainActor
final class AppUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController?
    private weak var activityProvider: (any AppUpdateActivityProviding)?
    private let installationGate = AppUpdateInstallationGate()
    private var activityObservation: AnyCancellable?

    init(
        bundle: Bundle = .main,
        activityProvider: (any AppUpdateActivityProviding)? = nil
    ) {
        self.activityProvider = activityProvider
        super.init()

        activityObservation = activityProvider?.appUpdateActivityChanges
            .sink { [weak self] in
                // @Published emits before its stored value changes. Moving the
                // final decision to the next actor turn ensures all operation
                // cleanup has completed before Sparkle is allowed to relaunch.
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.resumePendingInstallationIfPossible()
                }
            }

        guard AppUpdateConfiguration(infoDictionary: bundle.infoDictionary) != nil else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard let updaterController else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Updates are unavailable in this build"
            alert.informativeText = "Install an official signed Vidindir release to receive automatic updates. Local development builds do not connect to the release feed."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        installationGate.shouldPostponeInstallation(
            isBusy: activityProvider?.shouldDeferAppUpdateInstallation ?? false,
            installHandler: installHandler
        )
    }

    private func resumePendingInstallationIfPossible() {
        installationGate.resumeInstallationIfPossible(
            isBusy: activityProvider?.shouldDeferAppUpdateInstallation ?? false
        )
    }
}
