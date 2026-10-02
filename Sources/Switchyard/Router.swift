import AppKit
import os
import RouterCore

private let log = Logger(subsystem: "com.kevinebaugh.switchyard", category: "router")

/// rule → Jev → open → record → learn.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published private(set) var status = "Ready"
    /// Links routed since the menu was last opened that still need a look (a fallback or an
    /// unsure pick nobody has confirmed or moved yet). Drives the menu-bar badge, and agrees
    /// with the orange rows in Recent.
    @Published private(set) var attentionCount = 0
    /// Opening the menu counts as having seen everything routed before it.
    private var acknowledgedAt = Date()
    /// "Your last 3 links from Slack opened in Work…" shown at the top of Recent.
    @Published private(set) var appRuleSuggestion: AppRuleSuggestion.Suggestion?

    let jev = JevClient()
    /// The selected browser's adapter (Dia via AppleScript, Chrome & co. via their profile flag).
    var browser: BrowserAdapter { Browsers.adapter(for: settings.browser) }

    private let settings = AppSettings.shared
    private let profiles = ProfilesMonitor.shared
    private let rules = RuleStore.shared
    private let history = HistoryStore.shared
    private let notifier = Notifier.shared

    @Published private var apiKey: String?
    var hasAPIKey: Bool { apiKey != nil }
    private var lastActivity = Date.distantPast
    private var keepWarmTask: Task<Void, Never>?

    private init() {
        apiKey = Keychain.readAPIKey()
        profiles.onRename = { [weak self] old, new in
            self?.rules.renameProfile(from: old, to: new)
        }
    }

    func start() {
        browser.prepare()
        // Dia's profile order can wait; don't queue it ahead of the link that launched us.
        Task {
            try? await Task.sleep(for: .seconds(3))
            await profiles.refreshVisibleOrder(using: browser)
        }
        notifier.setUp(profiles: profiles.names)
        if settings.onboardingCompleted, settings.notificationsEnabled {
            notifier.requestAuthorization()
        }
        touchActivity()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Router.shared.touchActivity() }
        }
    }

    /// Switch browsers (setup's browser step): profiles, rules and notification actions follow.
    func selectBrowser(_ kind: BrowserKind) {
        guard kind != settings.browser else { return }
        settings.browser = kind
        profiles.switchTo(kind)
        rules.browserChanged()
        notifier.registerCategories(for: profiles.names)
        browser.prepare()
    }

    func setAPIKey(_ key: String) {
        Keychain.saveAPIKey(key)
        apiKey = Keychain.readAPIKey()
        touchActivity()
    }

    func menuOpened() {
        acknowledgedAt = Date()
        refreshAttention()
        profiles.refresh()
        Task { await profiles.refreshVisibleOrder(using: browser) }
        rules.reloadIfChangedOnDisk()
        refreshSuggestion()
        touchActivity()
    }

    var fallbackProfileName: String {
        profiles.profileName(matching: settings.fallbackProfileName) ?? profiles.names.first ?? settings.fallbackProfileName
    }

    // MARK: Routing

    /// Entry point for every link macOS hands us.
    func handleIncoming(_ incoming: URL, source: SourceApp?) {
        if incoming.scheme?.lowercased() == "switchyard" {
            // The checkout's "after payment" redirect.
            if incoming.host?.lowercased() == "supported" {
                SupportReminder.shared.markSupported()
                status = "Thank you for supporting Switchyard ♥"
                return
            }
            guard let components = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
                  let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let url = URL(string: value) else {
                status = "Ignored malformed switchyard:// link"
                return
            }
            let profile = components.queryItems?.first(where: { $0.name == "profile" })?.value
            Task { await route(url, source: source, forcedProfile: profile) }
            return
        }
        Task { await route(incoming, source: source) }
    }

    func route(_ url: URL, source: SourceApp?, forcedProfile: String? = nil) async {
        let clock = ContinuousClock()
        let started = clock.now
        touchActivity()

        let verdict: Verdict
        if let forcedProfile, let name = profiles.profileName(matching: forcedProfile) {
            verdict = Verdict(profileName: name, decision: .explicit, learn: nil)
        } else {
            verdict = await decide(url, source: source)
        }
        let milliseconds = started.duration(to: clock.now).milliseconds

        var record = RoutingRecord(
            url: url,
            profileName: verdict.profileName,
            decision: verdict.decision,
            latencyMilliseconds: milliseconds,
            sourceApp: source
        )
        status = "\(url.displayHost) → \(verdict.profileName) (\(verdict.decision.badge), \(record.latencyLabel))"
        log.info("\(url.host ?? "?", privacy: .public) → \(verdict.profileName, privacy: .public) [\(verdict.decision.badge, privacy: .public)] in \(record.latencyLabel, privacy: .public)")

        if let error = await open(url, in: verdict.profileName) {
            record.openError = error
        }

        if case let .rule(id, _) = verdict.decision {
            RuleUsageStore.shared.recordUse(of: id)
        }

        if let learn = verdict.learn {
            record.learnedRuleID = rules.upsert(key: learn, profileName: verdict.profileName, origin: .learned).id
        }
        history.add(record)
        refreshSuggestion()
        refreshAttention()

        if record.decision.needsAttention {
            notifier.notify(about: record)
        }
        SupportReminder.shared.linkRouted()
    }

    /// The routing decision without side effects (other than calling Jev). Also used by "Test URL".
    func decide(_ url: URL, source: SourceApp?) async -> Verdict {
        profiles.refresh()
        rules.reloadIfChangedOnDisk()

        if let rule = rules.index.match(url, from: source?.bundleID, availableProfiles: profiles.availableNames) {
            return Verdict(profileName: rule.profileName, decision: .rule(id: rule.id, label: rule.key.label), learn: nil)
        }

        let fallback = fallbackProfileName
        guard let features = LinkFeatures(url: url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return DecisionPolicy.fallback(.invalidResponse, fallbackProfile: fallback)
        }
        guard let apiKey else {
            return DecisionPolicy.fallback(.noAPIKey, fallbackProfile: fallback)
        }

        // Jev and a cold Dia launch overlap.
        browser.warmUp()

        let request = Jev.makeRequest(
            features: features,
            scheme: url.scheme?.lowercased() ?? "https",
            profiles: settings.jevProfiles(for: profiles.names),
            openedFromApp: source?.name
        )
        do {
            let response = try await jev.ask(request, apiKey: apiKey)
            guard let outcome = JevOutcome(response: response) else {
                return DecisionPolicy.fallback(.invalidResponse, fallbackProfile: fallback)
            }
            return DecisionPolicy.verdict(
                for: outcome,
                features: features,
                knownProfiles: profiles.names,
                fallbackProfile: fallback,
                profileThreshold: settings.profileThreshold
            )
        } catch let failure as JevFailure {
            return DecisionPolicy.fallback(failure.reason, fallbackProfile: fallback)
        } catch {
            return DecisionPolicy.fallback(.invalidResponse, fallbackProfile: fallback)
        }
    }

    /// Returns an error message if the link couldn't be opened in the requested profile.
    private func open(_ url: URL, in profileName: String) async -> String? {
        do {
            guard let profile = profiles.profile(named: profileName) else {
                throw BrowserLaunchError.profileNotFound(profileName, settings.browser)
            }
            try await browser.open(url, in: profile)
            return nil
        } catch {
            let message = error.localizedDescription
            log.error("Open failed: \(message, privacy: .public)")
            notifier.notifySetupProblem(message)
            // Never lose the link: fall back to whatever profile Dia has focused.
            try? await browser.openInCurrentProfile(url)
            return message
        }
    }

    // MARK: Corrections

    /// The rule a one-click correction should save for this record.
    func suggestedCorrectionKey(for record: RoutingRecord) -> RuleKey? {
        guard let features = LinkFeatures(url: record.url) else { return nil }
        switch record.decision {
        case let .rule(id, _):
            if let rule = rules.rule(id: id) { return rule.key }
        case let .jev(_, scope):
            if let scope, let key = features.ruleKey(for: scope) { return key }
        default:
            break
        }
        return RuleKey(host: features.host, hostMatch: .exact)
    }

    /// "This should have opened in `profileName`." Re-opens the link there (unless it's
    /// already there) and, with a key, saves that rule, replacing any rule with the same key.
    func correct(recordID: UUID, to profileName: String, key: RuleKey?) async {
        guard let record = history.record(id: recordID) else { return }
        let alreadyThere = record.finalProfileName == profileName

        if !alreadyThere, let error = await open(record.url, in: profileName) {
            history.update(id: recordID) { $0.openError = error }
        }
        var savedRuleID: UUID?
        if let key {
            savedRuleID = rules.upsert(key: key, profileName: profileName, origin: .corrected).id
        }
        history.update(id: recordID) {
            if !alreadyThere { $0.correctedTo = profileName }
            if let savedRuleID { $0.learnedRuleID = savedRuleID }
        }
        refreshSuggestion()
        refreshAttention()
        if key != nil, let reason = rules.readOnlyReason {
            status = "Not saved: \(reason)"
        } else {
            status = key.map { "Saved: \($0.label) → \(profileName)" } ?? "Opened in \(profileName)"
        }
    }

    func correct(recordID: UUID, to profileName: String) async {
        guard let record = history.record(id: recordID) else { return }
        await correct(recordID: recordID, to: profileName, key: suggestedCorrectionKey(for: record))
    }

    func openAgain(recordID: UUID) async {
        guard let record = history.record(id: recordID) else { return }
        _ = await open(record.url, in: record.finalProfileName)
    }

    private func refreshAttention() {
        let count = history.records.filter { record in
            record.date > acknowledgedAt && RoutingExplanation.explain(record, rule: rules.rule(id:)).needsAttention
        }.count
        if count != attentionCount { attentionCount = count }
    }

    // MARK: App-rule suggestions

    private static let dismissedSuggestionsKey = "dismissedAppRuleSuggestions"

    private var dismissedSuggestions: Set<String> {
        get { Set(AppEnvironment.defaults.stringArray(forKey: Self.dismissedSuggestionsKey) ?? []) }
        set { AppEnvironment.defaults.set(Array(newValue).sorted(), forKey: Self.dismissedSuggestionsKey) }
    }

    func refreshSuggestion() {
        let index = rules.index
        let suggestion = AppRuleSuggestion.suggest(
            records: history.records,
            hasAppRule: { index.appRule(for: $0) != nil },
            dismissed: dismissedSuggestions
        )
        if suggestion != appRuleSuggestion { appRuleSuggestion = suggestion }
    }

    func acceptSuggestion() {
        guard let suggestion = appRuleSuggestion else { return }
        rules.upsert(key: .app(suggestion.source), profileName: suggestion.profileName, origin: .manual)
        status = "Saved: links from \(suggestion.source.name) → \(suggestion.profileName)"
        refreshSuggestion()
    }

    func dismissSuggestion() {
        guard let suggestion = appRuleSuggestion else { return }
        dismissedSuggestions.insert(suggestion.dismissalKey)
        refreshSuggestion()
    }

    // MARK: Keeping the Jev connection warm

    /// Pre-warm now, and keep the TLS connection alive for 15 minutes after the last activity,
    /// since link clicks tend to come in bursts.
    func touchActivity() {
        lastActivity = Date()
        guard hasAPIKey, keepWarmTask == nil else { return }
        keepWarmTask = Task { [weak self] in
            while let self, Date().timeIntervalSince(self.lastActivity) < 15 * 60 {
                await self.jev.prewarm()
                try? await Task.sleep(for: .seconds(50))
            }
            self?.keepWarmTask = nil
        }
    }
}

