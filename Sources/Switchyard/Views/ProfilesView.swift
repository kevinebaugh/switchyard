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
                            ProfileChip(name: name)
                            let count = counts[name.lowercased()] ?? 0
                            Text(count == 1 ? "1 rule" : "\(count) rules")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if !ProfileDefaults.description(for: name).isEmpty,
                               settings.description(for: name) != ProfileDefaults.description(for: name) {
                                Button("Reset") { settings.setDescription(ProfileDefaults.description(for: name), for: name) }
                                    .controlSize(.small)
                                    .help("Go back to Switchyard's starter description for \(name)")
                            }
                        }
                        ProfileDescriptionEditor(name: name, height: 72)
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

/// A profile's description, edited in place (it's saved as you type), with an example when empty.
/// Shared by setup and the Profiles tab.
struct ProfileDescriptionEditor: View {
    // Not an environment object: setup's window doesn't provide one.
    @ObservedObject private var settings = AppSettings.shared
    let name: String
    var height: CGFloat = 64

    var body: some View {
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
        .frame(height: height)
        .background(.background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
        .accessibilityLabel("What \(name) is for")
    }
}
