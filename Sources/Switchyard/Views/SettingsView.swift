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
                        Text("Without a key, unmatched links open in \(router.fallbackProfileName).")
                            .foregroundStyle(.secondary)
                        Link("Get a key", destination: URL(string: "https://console.typesafe.ai/keys")!)
                    }
                    .font(.caption)
                }
                LabeledContent("Learn a rule at confidence") {
                    HStack {
                        Slider(value: $settings.profileThreshold, in: 0.5...0.95, step: 0.05)
                        Text(String(format: "%.2f", settings.profileThreshold))
                            .monospacedDigit()
                            .frame(width: 34)
                    }
                }
                Picker("When unsure or offline", selection: $settings.fallbackProfileName) {
                    ForEach(profiles.names, id: \.self) { Text($0).tag($0) }
                    if !profiles.names.contains(settings.fallbackProfileName) {
                        Text(settings.fallbackProfileName).tag(settings.fallbackProfileName)
                    }
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

            Section {
                ForEach(profiles.names, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ProfileChip(name: name)
                            Spacer()
                            if !ProfileDefaults.description(for: name).isEmpty,
                               settings.description(for: name) != ProfileDefaults.description(for: name) {
                                Button("Reset") { settings.setDescription(ProfileDefaults.description(for: name), for: name) }
                                    .controlSize(.small)
                            }
                        }
                        TextEditor(text: Binding(
                            get: { settings.description(for: name) },
                            set: { settings.setDescription($0, for: name) }
                        ))
                        .font(.callout)
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            } header: {
                Text("What each profile is for")
            } footer: {
                Text("Profiles come from \(settings.browser.displayName). Jev reads these descriptions to decide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("Notify on fallbacks and errors", isOn: $settings.notificationsEnabled)
                Toggle("Also notify when Jev is unsure", isOn: $settings.notifyLowConfidence)
                    .disabled(!settings.notificationsEnabled)
                if let systemError {
                    Text(systemError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isDefaultBrowser = DefaultBrowser.isDefault
            launchAtLogin = LoginItem.isEnabled
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
