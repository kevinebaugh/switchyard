import AppKit
import RouterCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var rules: RuleStore
    @EnvironmentObject private var profiles: ProfilesMonitor
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var updates = Updates.shared
    @ObservedObject private var support = SupportReminder.shared

    @State private var apiKeyDraft = ""
    @State private var testURL = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isDefaultBrowser = DefaultBrowser.isDefault
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var systemError: String?
    @State private var notificationAccess: Notifier.Access?
    @State private var copiedDiagnostics = false

    @State private var showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        _showsAdvanced = State(initialValue: showsAdvanced)
    }

    var body: some View {
        Form {
            Section("General") {
                BrowsersSetting()
                LabeledContent("Default browser") {
                    if isDefaultBrowser {
                        Label("Switchyard", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Text(DefaultBrowser.currentHandlerName ?? "Unknown")
                                .foregroundStyle(.secondary)
                            Button("Make Default") {
                                Task {
                                    do {
                                        try await DefaultBrowser.makeDefault()
                                    } catch {
                                        systemError = error.localizedDescription
                                    }
                                    isDefaultBrowser = DefaultBrowser.isDefault
                                }
                            }
                        }
                    }
                }
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        do {
                            try LoginItem.set(enabled: enabled)
                        } catch {
                            systemError = error.localizedDescription
                        }
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                Toggle("Notify on fallbacks, outages and errors", isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled {
                    notificationAccessRow
                }
                if let systemError {
                    Text(systemError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Jev") {
                HStack {
                    SecureField(router.hasAPIKey ? "API key saved in Keychain" : "TypeSafe API key", text: $apiKeyDraft)
                        .onSubmit(saveKey)
                    Button(router.hasAPIKey && apiKeyDraft.isEmpty ? "Remove" : "Save", action: saveKey)
                        .disabled(!router.hasAPIKey && apiKeyDraft.isEmpty)
                }
                if !router.hasAPIKey {
                    HStack {
                        Text("Optional. Without a key, Switchyard asks where each new site should open and remembers your answer.")
                            .foregroundStyle(.secondary)
                        Link("Get a key", destination: URL(string: "https://console.typesafe.ai/keys")!)
                    }
                    .font(.caption)
                } else {
                    if router.isAPIKeyRejected {
                        Label("TypeSafe rejected this key. Paste a working one, or remove it to have Switchyard ask instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Picker("Jev decides", selection: Binding(
                        get: { router.jevDecides },
                        set: { router.setJevDecides($0) }
                    )) {
                        Text("Only suggests (you pick)").tag(false)
                        Text("Links it's confident about").tag(true)
                    }
                    Picker("When Jev is unsure", selection: $settings.askWhenUnsure) {
                        Text("Ask me").tag(true)
                        Text("Open its best guess").tag(false)
                    }
                }
            }

            if support.isEnabled {
                Section {
                    if support.isSupporter {
                        Label("Thank you for supporting Switchyard.", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free and open source. Pay what you want, once.")
                                Label {
                                    Text(SupportReminder.climateNote).foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "leaf.fill").foregroundStyle(.green)
                                }
                                .font(.caption)
                            }
                            Spacer()
                            Button("Support…") { support.openCheckout() }
                        }
                    }
                }
            }

            Section("Advanced", isExpanded: $showsAdvanced) {
                LabeledContent("Learn a rule at confidence") {
                    HStack {
                        Slider(value: $settings.profileThreshold, in: 0.5...0.95, step: 0.05)
                        Text(String(format: "%.2f", settings.profileThreshold))
                            .monospacedDigit()
                            .frame(width: 34)
                    }
                }
                .disabled(!router.hasAPIKey)
                Toggle("Also notify when Jev is unsure", isOn: $settings.notifyLowConfidence)
                    .disabled(!settings.notificationsEnabled || !router.hasAPIKey)
                Picker("Rules folder", selection: Binding(
                    get: { settings.rulesLocation },
                    set: { newValue in
                        rules.move(to: newValue)
                        settings.rulesLocation = newValue
                    }
                )) {
                    ForEach(RulesLocation.allCases) { location in
                        Text(location.label + (location.isAvailable ? "" : " (not set up)"))
                            .tag(location)
                            .disabled(!location.isAvailable)
                    }
                }
                Text(rules.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                LabeledContent("Test a link") {
                    HStack {
                        TextField("URL", text: $testURL, prompt: Text("https://…"))
                            .labelsHidden()
                            .onSubmit(runTest)
                        Button(isTesting ? "…" : "Test", action: runTest)
                            .disabled(isTesting || URL(string: testURL)?.host == nil)
                    }
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                }
                HStack {
                    Button("Run Setup Again…") { OnboardingWindow.shared.show() }
                    Button("Copy Diagnostics") { Task { await copyDiagnostics() } }
                        .help("Copies app, browser and permission details for a bug report. No links, profile names or keys.")
                    Spacer()
                    if copiedDiagnostics {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if support.isEnabled, !support.isSupporter {
                    Link("Paid but still seeing support reminders?", destination: SupportReminder.paidButStillSeeingURL)
                        .font(.caption)
                }
            }

            Section {
                HStack {
                    Text("Switchyard \(Self.versionString)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updates.isAvailable {
                        Button("Check for Updates…", action: updates.checkForUpdates)
                            .disabled(!updates.canCheck)
                    }
                    Button("About") { AboutPanel.show() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isDefaultBrowser = DefaultBrowser.isDefault
            launchAtLogin = LoginItem.isEnabled
        }
        // Also on returning from System Settings.
        .task { notificationAccess = await Notifier.shared.access() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { notificationAccess = await Notifier.shared.access() }
        }
    }

    /// Shown only when macOS is holding notifications back.
    @ViewBuilder private var notificationAccessRow: some View {
        switch notificationAccess {
        case nil, .allowed:
            EmptyView()
        case .quiet:
            HStack {
                Text("macOS allows them, but banners are off").font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("Open Settings…", action: Notifier.openSystemSettings).controlSize(.small)
            }
        case .denied:
            HStack {
                Text("macOS has notifications off for Switchyard").font(.caption).foregroundStyle(.orange)
                Spacer()
                Button("Open Settings…", action: Notifier.openSystemSettings).controlSize(.small)
            }
        case .notAsked:
            HStack {
                Text("macOS hasn't been asked yet").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Allow Notifications…") {
                    Task {
                        await Notifier.shared.requestAuthorizationNow()
                        notificationAccess = await Notifier.shared.access()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func copyDiagnostics() async {
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        let jev: String = if !router.hasAPIKey {
            "not used (no key)"
        } else {
            router.connectivity.state.skipReason?.label ?? "reachable"
        }
        let report = DiagnosticsReport(
            appVersion: Self.versionString,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            browser: settings.browser.displayName,
            installedBrowsers: Browsers.installed.map(\.displayName),
            browserPermission: String(describing: await router.browser.permission(ask: false)),
            notifications: String(describing: await Notifier.shared.access()),
            hasKey: router.hasAPIKey,
            keyRejected: router.isAPIKeyRejected,
            jev: jev,
            rulesFolder: settings.rulesLocation.label,
            rules: rules.browserRules.count,
            rulesReadOnly: rules.readOnlyReason,
            profiles: profiles.names.count,
            isRehearsal: AppEnvironment.isRehearsal,
            recentDecisions: DiagnosticsReport.decisions(from: HistoryStore.shared.records)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdown, forType: .string)
        withAnimation { copiedDiagnostics = true }
        try? await Task.sleep(for: .seconds(3))
        withAnimation { copiedDiagnostics = false }
    }

    private func saveKey() {
        router.setAPIKey(apiKeyDraft)
        apiKeyDraft = ""
    }

    private func runTest() {
        guard let url = URL(string: testURL.contains("://") ? testURL : "https://" + testURL) else { return }
        isTesting = true
        Task {
            let clock = ContinuousClock()
            let started = clock.now
            let verdict = await router.decide(url, source: nil)
            let milliseconds = started.duration(to: clock.now).milliseconds

            var lines = ["→ \(verdict.profileName)   \(verdict.decision.badge)   \(String(format: "%.1f ms", milliseconds))"]
            if case let .rule(_, label) = verdict.decision { lines.append("matched rule: \(label)") }
            if case let .jev(_, scope) = verdict.decision { lines.append("scope: \(scope?.rawValue ?? "?")") }
            lines.append("would save: \(verdict.learn?.label ?? "nothing")")
            testResult = lines.joined(separator: "\n")
            isTesting = false
        }
    }
}

/// The browsers links can open in. The first is the one Switchyard was set up with; more can be
/// added, each asking once for whatever macOS permission it needs (none for Safari).
private struct BrowsersSetting: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: AppSettings
    @State private var adding: BrowserKind?
    @State private var problem: String?
    @State private var blocked: BrowserKind?

    var body: some View {
        let addable = Browsers.installed.filter { !settings.browsers.contains($0) }
        LabeledContent("Browsers") {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(settings.browsers, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Text(kind.displayName)
                        if kind == settings.browsers.first, settings.isMultiBrowser {
                            Text("main").font(.caption).foregroundStyle(.secondary)
                                .help("The browser Switchyard was set up with. Its profiles keep their plain names.")
                        }
                        if settings.isMultiBrowser {
                            Button {
                                router.setBrowsers(settings.browsers.filter { $0 != kind })
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop opening links in \(kind.displayName). Its rules are kept.")
                            .accessibilityLabel("Remove \(kind.displayName)")
                        }
                    }
                }
                if !addable.isEmpty {
                    Menu(adding.map { "Adding \($0.displayName)…" } ?? "Add Browser…") {
                        ForEach(addable, id: \.self) { kind in
                            Button(kind.displayName) { add(kind) }
                        }
                    }
                    .fixedSize()
                    .disabled(adding != nil)
                }
            }
        }
        if let problem {
            VStack(alignment: .leading, spacing: 6) {
                Text(problem).font(.caption).foregroundStyle(.red)
                if let blocked {
                    HStack {
                        Button(PermissionHelp.buttonTitle(for: blocked)) { NSWorkspace.shared.open(PermissionHelp.settingsURL(for: blocked)) }
                        Button("Try Again") { add(blocked) }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func add(_ kind: BrowserKind) {
        adding = kind
        problem = nil
        blocked = nil
        Task {
            let adapter = Browsers.adapter(for: kind)
            if kind.opening == .appleScript { await adapter.ensureRunning() }
            let permission = await adapter.permission(ask: true)
            adding = nil
            guard permission == .granted else {
                blocked = kind
                problem = PermissionHelp.instructions(for: kind)
                return
            }
            router.setBrowsers(settings.browsers + [kind])
        }
    }
}
