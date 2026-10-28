import RouterCore
import SwiftUI

/// Which menu tab is showing; shared so other parts of the menu can jump to a tab.
@MainActor
final class MenuNavigation: ObservableObject {
    static let shared = MenuNavigation()
    @Published var tab: MenuBarView.Tab = .recent
}

/// The Profiles tab: what each profile is for (what Jev reads), and where links go when Jev
/// can't decide.
struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfilesMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var rules: RuleStore
    @Environment(\.profilesOverride) private var profilesOverride

    private var names: [String] { profilesOverride?.map(\.name) ?? profiles.names }

    /// The profile whose description was just saved, for a moment's "Saved".
    @State private var savedName: String?
    @State private var hideSaved: Task<Void, Never>?

    private func showSaved(_ name: String) {
        withAnimation(.easeOut(duration: 0.15)) { savedName = name }
        hideSaved?.cancel()
        hideSaved = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { savedName = nil }
        }
    }

    var body: some View {
        let names = names
        let counts = Dictionary(grouping: rules.browserRules, by: { $0.profileName.lowercased() }).mapValues(\.count)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Jev reads these to decide where links without a rule go. Name the accounts, workspaces and tools each profile is for. Changes save as you type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if names.isEmpty {
                    Text("No \(settings.browser.displayName) profiles found yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(names, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ProfileDot(name: name)
                            Text(name).font(.headline)
                            let count = counts[name.lowercased()] ?? 0
                            Text(count == 1 ? "1 rule" : "\(count) rules")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if savedName == name {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                            Spacer()
                            if !ProfileDefaults.description(for: name).isEmpty,
                               settings.description(for: name) != ProfileDefaults.description(for: name) {
                                Button("Reset") { settings.setDescription(ProfileDefaults.description(for: name), for: name) }
                                    .controlSize(.small)
                                    .help("Go back to Switchyard's starter description for \(name)")
                            }
                        }
                        ProfileDescriptionEditor(name: name, onSaved: { showSaved(name) })
                    }
                }

                Divider()

                HStack {
                    Text("When Jev is unsure or offline, open links in")
                    Picker("", selection: $settings.fallbackProfileName) {
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                        if !names.contains(settings.fallbackProfileName) {
                            Text(settings.fallbackProfileName).tag(settings.fallbackProfileName)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text("Profiles come from \(settings.browser.displayName); add or rename them there. Descriptions are sent to Jev with each new link and stay out of the synced rules file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }
}

/// A profile's description, edited in place. Every change is stored as it's typed; Return (or a
/// pause in typing) confirms it with `onSaved`, but only if something actually changed. Return
/// also leaves the field; Option-Return adds a line.
/// Shared by setup and the Profiles tab.
struct ProfileDescriptionEditor: View {
    // Not an environment object: setup's window doesn't provide one.
    @ObservedObject private var settings = AppSettings.shared
    let name: String
    var onSaved: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var pause: Task<Void, Never>?
    /// Changed since "Saved" was last shown: only then is there anything to confirm.
    @State private var unconfirmed = false

    var body: some View {
        TextField(
            text: Binding(
                get: { settings.description(for: name) },
                set: { newValue in
                    guard newValue != settings.description(for: name) else { return }
                    settings.setDescription(newValue, for: name)
                    unconfirmed = true
                    confirmAfterPause()
                }
            ),
            // verbatim: don't turn the example email into a link.
            prompt: Text(verbatim: "e.g. \"Acme Corp: you@acme.com Google Workspace, Acme's Slack and Linear, the acme GitHub org.\"")
                .foregroundStyle(.tertiary),
            axis: .vertical
        ) {
            Text("What \(name) is for")
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(.callout)
        .lineLimit(3...6)
        .focused($focused)
        .onSubmit {
            pause?.cancel()
            focused = false
            confirm()
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3))
        )
    }

    private func confirmAfterPause() {
        pause?.cancel()
        pause = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            confirm()
        }
    }

    private func confirm() {
        guard unconfirmed else { return }
        unconfirmed = false
        onSaved?()
    }
}

/// A profile's colour, as a dot beside its name.
struct ProfileDot: View {
    @EnvironmentObject private var monitor: ProfilesMonitor
    @Environment(\.profilesOverride) private var profilesOverride
    let name: String

    var body: some View {
        let profiles = profilesOverride ?? monitor.profiles
        let index = profiles.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let color = index.flatMap { profiles[$0].colorARGB }.map(ProfileChip.color(argb:))
            ?? index.map { ProfileChip.palette[$0 % ProfileChip.palette.count] } ?? .gray
        Circle().fill(color).frame(width: 10, height: 10)
            .accessibilityHidden(true)   // the name is always right beside it
    }
}
