import AppKit
import RouterCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: model.step)
                .padding(.top, 18)
                .padding(.bottom, 6)

            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .browser: BrowserStep(model: model)
                case .profileList: ProfileListStep(model: model)
                case .jev: JevStep(model: model)
                case .profiles: ProfilesStep(model: model)
                case .permission: PermissionStep(model: model)
                case .defaultBrowser: DefaultBrowserStep(model: model)
                case .finish: FinishStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44)
            .padding(.top, 14)

            Divider()
            HStack {
                if model.step != .welcome {
                    Button("Back", action: model.back)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if let later = model.deferLabel {
                    Button(later, action: model.next)
                        .buttonStyle(.link)
                        .padding(.trailing, 8)
                }
                if model.isWorking {
                    ProgressView().controlSize(.small).padding(.trailing, 4)
                }
                Button(primaryTitle, action: model.primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canContinue)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 640, height: 560)
        .environmentObject(ProfilesMonitor.shared)
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: "Get Started"
        case .finish: "Start Using Switchyard"
        default: "Continue"
        }
    }
}

// MARK: - Chrome

private struct StepIndicator: View {
    let current: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: step == current ? 28 : 14, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingModel.Step.allCases.count): \(current.shortTitle)")
    }
}

private struct StepHeader: View {
    var symbol: String?
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 36)
            }
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 480)
        .padding(.bottom, symbol == nil ? 12 : 18)
    }
}

private struct StatusRow: View {
    enum Kind { case good, waiting, problem, neutral }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch kind {
            case .good: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .waiting: ProgressView().controlSize(.small)
            case .problem: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .neutral: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// A spinner that only appears if the wait is long enough to notice, so fast checks show nothing.
private struct PendingRow: View {
    let text: String
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.callout)
        .opacity(isVisible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeIn(duration: 0.2)) { isVisible = true }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.top, 10)
            Text("Welcome to Switchyard")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 8)
            Text("Every link on the right track in your browser.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 16) {
                feature("arrow.triangle.branch", "The right profile, every time",
                        "Links from other apps open in the browser profile they belong to.")
                feature("bolt", "Instant once it's learned",
                        "Rules answer in microseconds. For new sites, Jev decides in a fraction of a second.")
                feature("arrow.uturn.backward", "Easy to correct",
                        "Opened in the wrong profile? Fix it from the menu bar, and Switchyard remembers.")
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.top, 28)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BrowserStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                symbol: "safari",
                title: "Which browser do you use?",
                subtitle: "Switchyard opens each link in the right profile of this browser."
            )
            if model.installedBrowsers.isEmpty {
                Card {
                    StatusRow(kind: .problem, text: "No supported browser found. Switchyard works with \(BrowserKind.allCases.map(\.displayName).joined(separator: ", ")).")
                    HStack {
                        Spacer()
                        Button("Check Again", action: model.refresh)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(model.installedBrowsers) { kind in
                        BrowserChoice(kind: kind, isSelected: model.browser == kind) { model.choose(kind) }
                    }
                }
                let others = BrowserKind.allCases.filter { !model.installedBrowsers.contains($0) }
                if !others.isEmpty {
                    Text("Also works with \(others.map(\.displayName).joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
        }
    }
}

private struct BrowserChoice: View {
    let kind: BrowserKind
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                if let url = Browsers.adapter(for: kind).applicationURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName).font(.headline)
                    if !kind.isVerified {
                        Text("Should work; not yet tested").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                (isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileListStep: View {
    @ObservedObject var model: OnboardingModel

    private var name: String { model.browser.displayName }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                symbol: "person.2.crop.square.stack",
                title: "Your \(name) profiles",
                subtitle: "Switchyard routes links between the profiles you already have in \(name). Add or rename them in \(name) any time; Switchyard follows along."
            )
            Card {
                if !model.browserInstalled {
                    StatusRow(kind: .problem, text: "\(name) isn't installed.")
                    HStack {
                        Spacer()
                        Button("Check Again", action: model.refresh)
                    }
                } else if model.profiles.isEmpty {
                    StatusRow(kind: .problem, text: "\(name) is installed, but no profiles were found. Open \(name) once, then check again.")
                    HStack {
                        Spacer()
                        Button("Check Again", action: model.refresh)
                    }
                } else {
                    StatusRow(kind: .good, text: "Found \(model.profiles.count) \(model.profiles.count == 1 ? "profile" : "profiles") in \(name)")
                    FlowChips(names: model.profiles)
                        .animation(.easeInOut(duration: 0.25), value: model.profiles)
                    if model.profiles.count == 1 {
                        Text("With one profile there's nothing to route yet. Create more in \(name) (for example Work and Personal), and they'll appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct FlowChips: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(names, id: \.self) { ProfileChip(name: $0).font(.body) }
        }
    }
}

private struct JevStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                symbol: "sparkles",
                title: "Connect Jev",
                subtitle: "Links you haven't taught Switchyard yet are decided by Jev, TypeSafe's fast decision model. Its confident answers become rules, so each kind of link is asked about once."
            )
            Card {
                switch model.keyState {
                case .saved:
                    StatusRow(kind: .good, text: "A TypeSafe API key is already saved in your Keychain.")
                    keyField(prompt: "Paste a new key to replace it")
                case let .connected(milliseconds):
                    StatusRow(kind: .good, text: "Connected. Jev answered in \(Int(milliseconds.rounded())) ms.")
                default:
                    keyField(prompt: "TypeSafe API key")
                    if case let .failed(message) = model.keyState {
                        StatusRow(kind: .problem, text: message)
                    }
                }
            }
            Text("Jev sees only a link's site, its first few path segments and the names of its query parameters, never their values. Links that match a rule never leave your Mac. Your key is kept in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)
        }
    }

    private func keyField(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(prompt, text: $model.apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.primaryAction)
                .disabled(model.keyState == .checking)
            Link("Get an API key from the TypeSafe console →", destination: URL(string: "https://console.typesafe.ai/keys")!)
                .font(.callout)
        }
    }
}

private struct ProfilesStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Describe your profiles",
                subtitle: "Jev only knows what these say. Switchyard drafts them from what each profile is signed in to and uses most; name any workspaces or tools it missed."
            )

            HStack(spacing: 8) {
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                    Text("Drafting descriptions from your \(model.browser.displayName) profiles…")
                } else if let note = model.generationNote {
                    Image(systemName: "wand.and.sparkles").foregroundStyle(Color.accentColor)
                    Text(note)
                }
                Spacer()
                Button("Redraft All") { model.generateDescriptions(overwrite: true) }
                    .controlSize(.small)
                    .disabled(model.isGenerating)
                    .help("Replace every description with a fresh draft from \(model.browser.displayName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.profiles, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            ProfileChip(name: name)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: Binding(
                                    get: { settings.description(for: name) },
                                    set: { settings.setDescription($0, for: name) }
                                ))
                                .font(.callout)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                if settings.description(for: name).isEmpty {
                                    // verbatim: don't turn the example email into a link.
                                    Text(verbatim: "e.g. \"Acme Corp: you@acme.com Google Workspace, Acme's Slack and Linear, the acme GitHub org.\"")
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .allowsHitTesting(false)
                                }
                            }
                            .frame(height: 64)
                            .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("When Jev is unsure or offline, open links in")
                    Picker("", selection: $settings.fallbackProfileName) {
                        ForEach(model.profiles, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                .font(.callout)
                Text("Your history is read only on this Mac. These descriptions are sent to Jev with each new link, so edit out anything you'd rather not share.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }
}

private struct PermissionStep: View {
    @ObservedObject var model: OnboardingModel

    /// Dia needs Automation to open tabs; Chrome & co. and Firefox only need Switchyard to read
    /// their (macOS-protected) profile list.
    private struct Copy {
        let title, subtitle, action, granted, denied, footnote: String
    }

    private var copy: Copy {
        let name = model.browser.displayName
        switch model.browser.opening {
        case .appleScript:
            return Copy(
                title: "Let Switchyard open tabs in \(name)",
                subtitle: "Switchyard asks \(name) to open each link in the right profile, and to list your profiles in \(name)'s order. macOS will ask you to allow this once.",
                action: "Allow Switchyard to Control \(name)…",
                granted: "Switchyard can open tabs in \(name).",
                denied: "macOS is blocking Switchyard from controlling \(name). Turn on \(name) under Switchyard in Privacy & Security → Automation.",
                footnote: "This lets Switchyard send commands to \(name) only. It can't see or control other apps."
            )
        case .profileDirectoryFlag, .firefoxProfile:
            return Copy(
                title: "Let Switchyard read your \(name) profiles",
                subtitle: "Switchyard reads \(name)'s profile list, and on this Mac only the sites each profile uses most, so it can set itself up. macOS will ask you to allow this once.",
                action: "Allow Access to \(name) Profiles…",
                granted: "Switchyard can read your \(name) profiles.",
                denied: "macOS is blocking Switchyard from reading \(name)'s data. Allow Switchyard in System Settings → Privacy & Security (App Data, or Full Disk Access), then check again.",
                footnote: model.browser == .firefox
                    ? "Links open with Firefox's own profile switch, so Switchyard doesn't need to control Firefox or any other app. Each Firefox profile runs as its own window in the Dock."
                    : "Links open with \(name)'s own profile switch, so Switchyard doesn't need to control \(name) or any other app."
            )
        }
    }

    var body: some View {
        let copy = copy
        VStack(spacing: 0) {
            StepHeader(symbol: "hand.raised", title: copy.title, subtitle: copy.subtitle)
            Card {
                switch model.permission {
                case nil:
                    PendingRow(text: "Checking with macOS…")
                    // Reserve the button row the answer will need, so the card doesn't grow.
                    Button(copy.action) {}
                        .buttonStyle(.borderedProminent)
                        .hidden()
                        .accessibilityHidden(true)
                case .granted:
                    StatusRow(kind: .good, text: copy.granted)
                case .denied:
                    StatusRow(kind: .problem, text: copy.denied)
                    HStack {
                        Button("Open Privacy & Security", action: model.openPrivacySettings)
                        if model.browser.opensWithArguments {
                            Button("Check Again", action: model.askPermission)
                        }
                    }
                case .browserNotRunning where !model.isAskingPermission:
                    StatusRow(kind: .neutral, text: "\(model.browser.displayName) isn't running. Switchyard will open it to ask.")
                    Button(copy.action, action: model.askPermission)
                        .buttonStyle(.borderedProminent)
                default:
                    if model.isAskingPermission {
                        StatusRow(kind: .waiting, text: "Waiting for your answer in the macOS dialog…")
                    } else {
                        StatusRow(kind: .neutral, text: "Not allowed yet.")
                        Button(copy.action, action: model.askPermission)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            // A soft cross-fade between states.
            .animation(.easeInOut(duration: 0.2), value: model.permission)
            Text(copy.footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }
}

private struct DefaultBrowserStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                symbol: "link",
                title: "Make Switchyard your default browser",
                subtitle: "Links you click in other apps come to Switchyard first, then open in \(model.browser.displayName), in the right profile. Links you click inside \(model.browser.displayName) stay there."
            )
            Card {
                if model.isDefaultBrowser {
                    StatusRow(kind: .good, text: "Switchyard is your default browser.")
                } else {
                    StatusRow(kind: .neutral, text: "Your default browser is \(model.currentBrowserName ?? "another app").")
                    Button("Make Switchyard the Default…", action: model.makeDefault)
                        .buttonStyle(.borderedProminent)
                    Text("macOS will ask you to confirm. Choose “Use Switchyard”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("To switch back later: System Settings → Desktop & Dock → Default web browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
    }
}

private struct FinishStep: View {
    @ObservedObject var model: OnboardingModel

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                symbol: "checkmark.seal",
                title: "You're all set",
                subtitle: "Click a link in Slack, Mail or anywhere else. Switchyard lives in your menu bar, where you can see recent links and fix any that opened in the wrong profile."
            )
            HStack(spacing: 10) {
                Image(nsImage: MenuBarGlyph.image)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Look for this in your menu bar")
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .padding(.bottom, 20)

            Card {
                settingRow("Open Switchyard at login") {
                    Toggle("", isOn: $model.launchAtLogin).labelsHidden()
                }
                Divider()
                settingRow("Notify me when a link falls back or needs attention") {
                    Toggle("", isOn: $model.notifications).labelsHidden()
                }
                Divider()
                settingRow("Sync rules between Macs with") {
                    Picker("", selection: $model.rulesLocation) {
                        ForEach(RulesLocation.allCases) { location in
                            Text(location.label).tag(location).disabled(!location.isAvailable)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .toggleStyle(.switch)
        }
    }
}
