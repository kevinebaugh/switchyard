import AppKit
import Sparkle

/// In-app updates via Sparkle. The feed is the appcast attached to the latest GitHub release;
/// every update is signed with Switchyard's EdDSA key (`SUPublicEDKey` in Info.plist), so only
/// genuine releases install.
@MainActor
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    @Published private(set) var canCheck = false
    @Published var automaticallyChecks = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    private var observation: NSKeyValueObservation?

    /// Rehearsals and snapshots never update, and neither does a build without a public key
    /// (a local build that isn't set up for releases).
    var isAvailable: Bool { updater != nil }

    func start() {
        let hasKey = !(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        guard !AppEnvironment.isIsolated, hasKey, controller == nil else { return }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        // Sparkle updates this on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // Switchyard is a menu-bar app with no Dock icon: bring Sparkle's windows to the front.
    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in NSApp.activate() }
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
