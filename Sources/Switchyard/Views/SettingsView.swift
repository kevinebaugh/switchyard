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
    @State private var testURL = "https://app.shortcut.com/acme/story/1"
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isDefaultBrowser = DefaultBrowser.isDefault
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var systemError: String?
    @State private var notificationAccess: Notifier.Access?
    @State private var copiedDiagnostics = false

    var body: some View {
        Form {
            Section("Jev") {
                HStack {
                    SecureField(router.hasAPIKey ? "API key saved in Keychain" : "TypeSafe API key", text: $apiKeyDraft)
                        .onSubmit(saveKey)
                    Button(router.hasAPIKey && apiKeyDraft.isEmpty ? "Remove" : "Save", action: saveKey)
                        .disabled(!router.hasAPIKey && apiKeyDraft.isEmpty)
                }
                if !router.hasAPIKey {
                    HStack {
                        Text("Optional. Without a key, Switchyard asks where each new site should open and remembers your answer. With one, Jev picks for you.")
                            .foregroundStyle(.secondary)
                        Link("Get a key", destination: URL(string: "https://console.typesafe.ai/keys")!)
                    }
                    .font(.caption)
                } else if router.isAPIKeyRejected {
                    Label("TypeSafe rejected this key. Paste a working one, or remove it to have Switchyard ask instead.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Learn a rule at confidence") {
                    HStack {
                        Slider(value: $settings.profileThreshold, in: 0.5...0.95, step: 0.05)
                        Text(String(format: "%.2f", settings.profileThreshold))
                            .monospacedDigit()
                            .frame(width: 34)
                    }
                }
                LabeledContent("Profile descriptions") {
                    Button("Edit in Profiles") { MenuNavigation.shared.tab = .profiles }
                }
            }

            Section("Test a link") {
                HStack {
                    TextField("URL", text: $testURL)
                        .onSubmit(runTest)
                    Button(isTesting ? "…" : "Test", action: runTest)
                        .disabled(isTesting || URL(string: testURL)?.host == nil)
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Rules sync") {
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
                    .textSelection(.enabled)
            }

            Section("System") {
                LabeledContent("Browser") {
                    HStack {
                        Text(settings.browser.displayName)
                        Button("Change…") { OnboardingWindow.shared.show() }
                            .help("Setup lets you pick another browser")
                    }
                }
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
                HStack {
                    Button("Run Setup Again…") { OnboardingWindow.shared.show() }
                    Spacer()
                    Button("About Switchyard") { AboutPanel.show() }
                }
                HStack {
                    Button("Copy Diagnostics") { Task { await copyDiagnostics() } }
                        .help("Copies app, browser and permission details for a bug report. No links, profile names or keys.")
                    if copiedDiagnostics {
                        Label("Copied: paste it into a GitHub issue", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if let systemError {
                    Text(systemError).font(.caption).foregroundStyle(.red)
                }
            }

            if support.isEnabled {
                Section("Support") {
                    if support.isSupporter {
                        Label("Thank you for supporting Switchyard.", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    } else {
                        HStack {
                            Text("Free and open source. Pay what you want, once.")
                            Spacer()
                            Button("Support…") { support.openCheckout() }
                        }
                        HStack {
                            Label {
                                Text(SupportReminder.climateNote).foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "leaf.fill").foregroundStyle(.green)
                            }
                            Spacer()
                        }
                        .font(.caption)
                        HStack {
                            Link("Paid but still seeing reminders?", destination: SupportReminder.paidButStillSeeingURL)
                            Spacer()
                            Button("I've already supported") { support.markSupported() }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                LabeledContent("Version", value: Self.versionString)
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                    Button("Check for Updates…", action: updates.checkForUpdates)
                        .disabled(!updates.canCheck)
                } else {
                    Text("Updates are off in this build (it isn't set up for releases).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            }

            Section {
                LabeledContent("macOS") {
                    switch notificationAccess {
                    case nil:
                        ProgressView().controlSize(.small)
                    case .allowed:
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .quiet:
                        HStack {
                            Text("Allowed, but banners are off").foregroundStyle(.orange)
                            Button("Open Settings…", action: Notifier.openSystemSettings)
                        }
                    case .denied:
                        HStack {
                            Text("Off for Switchyard").foregroundStyle(.orange)
                            Button("Open Settings…", action: Notifier.openSystemSettings)
                        }
                    case .notAsked:
                        Button("Allow Notifications…") {
                            Task {
                                await Notifier.shared.requestAuthorizationNow()
                                notificationAccess = await Notifier.shared.access()
                            }
                        }
                    }
                }
                Toggle("Notify on fallbacks, outages and errors", isOn: $settings.notificationsEnabled)
                Toggle("Also notify when Jev is unsure", isOn: $settings.notifyLowConfidence)
                    .disabled(!settings.notificationsEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                Text("A Focus can hold notifications back; they still collect in Notification Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
