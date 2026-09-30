import AppKit
import RouterCore

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, browser, permission, profileList, jev, profiles, defaultBrowser, finish

        var id: Int { rawValue }

        var shortTitle: String {
            switch self {
            case .welcome: "Welcome"
            case .browser: "Browser"
            case .profileList: "Found"
            case .jev: "Jev"
            case .profiles: "Profiles"
            case .permission: "Permission"
            case .defaultBrowser: "Default"
            case .finish: "Done"
            }
        }
    }

    enum KeyState: Equatable {
        case empty
        /// A key was already in the Keychain when onboarding started.
        case saved
        case checking
        case connected(milliseconds: Double)
        case failed(String)

        var isReady: Bool {
            switch self {
            case .saved, .connected: true
            default: false
            }
        }
    }

    @Published var step: Step = .welcome
    /// The browser setup is configuring (mirrors AppSettings.browser).
    @Published var browser: BrowserKind
    @Published var installedBrowsers: [BrowserKind] = []
    @Published var browserInstalled = false
    @Published var profiles: [String] = []
    @Published var apiKeyDraft = ""
    @Published var keyState: KeyState = .empty
    /// nil until macOS has answered, so the step never flashes a wrong state.
    @Published var permission: BrowserPermission?
    @Published var isAskingPermission = false
    @Published var isDefaultBrowser = false
    @Published var currentBrowserName: String?
    @Published var launchAtLogin = true
    @Published var notifications = true
    @Published var rulesLocation: RulesLocation
    @Published var isGenerating = false
    @Published var generationNote: String?

    var onFinish: () -> Void = {}

    private let router = Router.shared
    private let settings = AppSettings.shared
    private let monitor = ProfilesMonitor.shared
    private var pollTask: Task<Void, Never>?
    private let isLive: Bool

    /// - Parameter live: false for snapshots: no polling, no system calls.
    init(live: Bool = true) {
        isLive = live
        browser = AppSettings.shared.browser
        rulesLocation = settings.rulesLocation
        notifications = settings.notificationsEnabled
        guard live else { return }
        keyState = router.hasAPIKey ? .saved : .empty
        let installed = Browsers.installed
        if !installed.contains(browser), let first = installed.first(where: \.isVerified) ?? installed.first {
            choose(first)
        }
        refresh()
    }

    // MARK: Navigation

    var canContinue: Bool {
        switch step {
        case .welcome, .profiles, .finish: true
        case .browser: installedBrowsers.contains(browser)
        case .profileList: browserInstalled && !profiles.isEmpty
        case .jev: keyState != .checking && (hasKeyDraft || keyState.isReady)
        case .permission: permission == .granted
        case .defaultBrowser: isDefaultBrowser
        }
    }

    /// Only the default browser can be put off: without Jev or the Automation grant Switchyard
    /// can't route anything, so those steps have no skip. (Closing the window keeps setup
    /// unfinished, and the menu offers to resume it.)
    var deferLabel: String? {
        step == .defaultBrowser && !isDefaultBrowser ? "Not yet" : nil
    }

    /// The primary button is busy (a quiet spinner beside it, nothing else changes).
    var isWorking: Bool {
        step == .jev && keyState == .checking
    }

    private var hasKeyDraft: Bool {
        !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The footer's one primary button. On the Jev step, a typed key is checked first and
    /// the step advances once TypeSafe accepts it.
    func primaryAction() {
        if step == .jev, hasKeyDraft {
            connect()
        } else {
            next()
        }
    }

    func next() {
        if step == .finish { finish(); return }
        guard var next = Step(rawValue: step.rawValue + 1) else { return }
        // Nothing to ask for when macOS already allows it (checked as soon as setup opens).
        if next == .permission, permission == .granted { next = .profileList }
        step = next
        refresh()
        entered(next)
    }

    func back() {
        guard var previous = Step(rawValue: step.rawValue - 1) else { return }
        if previous == .permission, permission == .granted { previous = .welcome }
        step = previous
    }

    private func entered(_ step: Step) {
        guard isLive else { return }
        switch step {
        case .permission:
            Task { permission = await router.browser.permission(ask: false) }
        case .profileList:
            Task {
                await monitor.refreshVisibleOrder(using: router.browser)
                refresh()
            }
        case .profiles:
            generateDescriptions(overwrite: false)
        default:
            break
        }
    }

    // MARK: Live state

    func start() {
        guard isLive, pollTask == nil else { return }
        // Know the Automation answer before the Welcome step is done, so an already-granted
        // permission step can be skipped without a flash.
        Task { permission = await router.browser.permission(ask: false) }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-read what setup shows. Runs every second while the window is open, so it only
    /// publishes values that changed (otherwise the whole window re-renders each tick).
    func refresh() {
        guard isLive else { return }
        update(\.installedBrowsers, to: Browsers.installed)
        update(\.browserInstalled, to: router.browser.isInstalled)
        update(\.profiles, to: monitor.refresh().map(\.name))
        update(\.isDefaultBrowser, to: DefaultBrowser.isDefault)
        update(\.currentBrowserName, to: DefaultBrowser.currentHandlerName)
        if !profiles.contains(settings.fallbackProfileName), let first = profiles.first {
            let preferred = ProfileDefaults.fallbackProfileName
            settings.fallbackProfileName = profiles.contains(preferred) ? preferred : first
        }
    }

    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<OnboardingModel, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func poll() async {
        refresh()
        if step == .permission, !isAskingPermission {
            update(\.permission, to: await router.browser.permission(ask: false))
        }
    }

    // MARK: Jev

    func connect() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyState = .checking
        Task {
            let features = LinkFeatures(url: URL(string: "https://github.com/")!)!
            let request = Jev.makeRequest(
                features: features,
                scheme: "https",
                profiles: settings.jevProfiles(for: profiles),
                openedFromApp: nil
            )
            let clock = ContinuousClock()
            let started = clock.now
            do {
                // A first request includes the TLS handshake; allow more than the routing deadline.
                _ = try await router.jev.ask(request, apiKey: key, deadline: .seconds(6))
                router.setAPIKey(key)
                apiKeyDraft = ""
                keyState = .connected(milliseconds: started.duration(to: clock.now).milliseconds)
                if step == .jev { next() }
            } catch let failure as JevFailure {
                keyState = .failed(Self.message(for: failure.reason))
            } catch {
                keyState = .failed("Something went wrong: \(error.localizedDescription)")
            }
        }
    }

    private static func message(for reason: FallbackReason) -> String {
        switch reason {
        case .unauthorized: "TypeSafe didn't accept that key. Check it and try again."
        case .offline: "Couldn't reach TypeSafe. Check your connection."
        case .timeout: "TypeSafe took too long to answer. Try again."
        case .rateLimited: "TypeSafe is rate-limiting this key. Try again in a moment."
        case .overloaded: "TypeSafe is busy right now. Try again in a moment."
        default: "TypeSafe returned an error (\(reason.label))."
        }
    }

    // MARK: Browser

    func choose(_ kind: BrowserKind) {
        guard isLive else { browser = kind; return }
        router.selectBrowser(kind)
        browser = kind
        permission = nil
        refresh()
        Task { permission = await router.browser.permission(ask: false) }
    }

    // MARK: Descriptions

    /// Draft descriptions from each profile's Google sign-in and distinctive sites, read locally.
    /// Without `overwrite`, only profiles that don't have a description yet are drafted.
    func generateDescriptions(overwrite: Bool) {
        let all = monitor.profiles
        let targets = Set(all.map(\.name).filter { overwrite || !settings.hasStoredDescription(for: $0) })
        guard !targets.isEmpty, !isGenerating else { return }
        isGenerating = true
        generationNote = nil
        let fallback = settings.fallbackProfileName

        Task {
            let browser = browser
            let signals = await Task.detached(priority: .userInitiated) {
                ProfileSignalsReader.signals(for: all, in: browser)
            }.value
            var drafted: [String] = []
            var blank: [String] = []
            for signal in signals where targets.contains(signal.name) {
                if let text = ProfileDescriber.describe(signal, among: signals, isFallback: signal.name == fallback) {
                    settings.setDescription(text, for: signal.name)
                    drafted.append(signal.name)
                } else {
                    // Not enough to go on: an empty description beats a wrong guess.
                    settings.setDescription("", for: signal.name)
                    blank.append(signal.name)
                }
            }
            generationNote = Self.generationNote(drafted: drafted, blank: blank)
            isGenerating = false
        }
    }

    static func generationNote(drafted: [String], blank: [String]) -> String {
        func names(_ list: [String]) -> String {
            list.count <= 1 ? (list.first ?? "") : list.dropLast().joined(separator: ", ") + " and " + list.last!
        }
        switch (drafted.isEmpty, blank.isEmpty) {
        case (false, true):
            return "Drafted on your Mac from the sites each profile uses most. Edit anything."
        case (false, false):
            return "Drafted on your Mac from the sites each profile uses most. Left \(names(blank)) blank: not enough history to go on."
        default:
            return "Not enough browsing history to draft descriptions yet. Write your own, or leave them blank for now."
        }
    }

    // MARK: Permission

    func askPermission() {
        isAskingPermission = true
        Task {
            // Dia's Automation prompt needs Dia running; Chrome's data-access prompt doesn't.
            if browser.opening == .appleScript { await router.browser.ensureRunning() }
            permission = await router.browser.permission(ask: true)
            isAskingPermission = false
            if permission == .granted {
                monitor.refresh()
                await monitor.refreshVisibleOrder(using: router.browser)
                refresh()
                if step == .permission { next() }
            }
        }
    }

    func openPrivacySettings() {
        let pane = browser.opening == .appleScript ? "?Privacy_Automation" : ""
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security\(pane)")!)
    }

    // MARK: Default browser

    func makeDefault() {
        Task {
            try? await DefaultBrowser.makeDefault()
            refresh()
        }
    }

    // MARK: Finish

    private func finish() {
        settings.notificationsEnabled = notifications
        if notifications { Notifier.shared.requestAuthorization() }
        if rulesLocation != settings.rulesLocation {
            RuleStore.shared.move(to: rulesLocation)
            settings.rulesLocation = rulesLocation
        }
        if launchAtLogin != LoginItem.isEnabled {
            try? LoginItem.set(enabled: launchAtLogin)
        }
        settings.onboardingCompleted = true
        stop()
        onFinish()
    }
}
