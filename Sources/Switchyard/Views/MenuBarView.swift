import AppKit
import RouterCore
import SwiftUI

struct MenuBarView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case rules = "Rules"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: AppSettings
    @State private var tab: Tab = .recent

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: MenuBarGlyph.image)
                    .foregroundStyle(.secondary)
                Text("Switchyard")
                    .font(.headline)
                if AppEnvironment.isRehearsal {
                    Text("REHEARSAL")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            .padding(12)

            Divider()

            if !settings.onboardingCompleted {
                Button {
                    OnboardingWindow.shared.show()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Finish setting up Switchyard")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.08))
                Divider()
            }

            Group {
                switch tab {
                case .recent: RecentView()
                case .rules: RulesView()
                case .settings: SettingsView()
                }
            }
            .frame(height: 470)

            Divider()

            HStack {
                Text(router.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 460)
        .onAppear { router.menuOpened() }
    }
}

// MARK: - Shared bits

private struct ProfilesOverrideKey: EnvironmentKey {
    static let defaultValue: [DiaProfile]? = nil
}

extension EnvironmentValues {
    /// Stand-in profiles (with their colors) for snapshots; nil means Dia's real profiles.
    var profilesOverride: [DiaProfile]? {
        get { self[ProfilesOverrideKey.self] }
        set { self[ProfilesOverrideKey.self] = newValue }
    }
}

struct ProfileChip: View {
    @EnvironmentObject private var monitor: DiaProfilesMonitor
    @Environment(\.profilesOverride) private var profilesOverride
    let name: String

    private static let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .teal, .indigo, .brown]

    /// Dia's profile color (0xAARRGGBB).
    static func color(argb: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255
        )
    }

    var body: some View {
        let profiles = profilesOverride ?? monitor.profiles
        let index = profiles.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let diaColor = index.flatMap { profiles[$0].colorARGB }.map(Self.color(argb:))
        let color = diaColor ?? index.map { Self.palette[$0 % Self.palette.count] } ?? .gray
        Text(name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .opacity(index == nil ? 0.6 : 1)
    }
}

extension RoutingRecord {
    var displayURL: String {
        let host = url.host ?? url.absoluteString
        let path = url.path == "/" ? "" : url.path
        return host + path
    }
}

// MARK: - Recent

struct RecentView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var router: Router

    var body: some View {
        if history.records.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No links routed yet")
                    .font(.headline)
                Text("Make Switchyard your default browser in Settings, then click a link anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let suggestion = router.appRuleSuggestion {
                        AppRuleSuggestionBanner(suggestion: suggestion)
                        Divider()
                    }
                    ForEach(history.records) { record in
                        RecentRow(record: record)
                        Divider()
                    }
                }
            }
        }
    }
}

struct RecentRow: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var profiles: DiaProfilesMonitor
    @EnvironmentObject private var rules: RuleStore
    let record: RoutingRecord

    private var currentProfile: String { record.finalProfileName }

    /// "Slack · 4 min ago · 0.6 ms"
    private var meta: String {
        let age = record.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return ([record.sourceApp, age, record.latencyLabel] as [String?]).compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayURL)
                    .lineLimit(1)
                    .truncationMode(.middle)
                let why = RoutingExplanation.explain(record, rule: rules.rule(id:))
                HStack(spacing: 4) {
                    if why.needsAttention {
                        Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
                    }
                    Text(why.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(why.needsAttention ? Color.orange : Color.secondary)
                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if let error = record.openError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if record.correctedTo != nil {
                Text(record.profileName)
                    .font(.caption)
                    .strikethrough()
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ProfileChip(name: currentProfile)
            Menu {
                correctionMenu
            } label: {
                Image(systemName: "arrow.uturn.right.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Should have opened somewhere else?")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu { correctionMenu }
    }

    /// "Always: <scope>" for each rule this link could save, sending it to `profile`.
    private func ruleButtons(_ options: [RuleKey], suggested: RuleKey?, to profile: String) -> some View {
        ForEach(options, id: \.self) { key in
            Button("Always: \(key.label)\(key == suggested ? "  (suggested)" : "")") {
                Task { await router.correct(recordID: record.id, to: profile, key: key) }
            }
        }
    }

    @ViewBuilder private var correctionMenu: some View {
        let urlOptions = LinkFeatures(url: record.url)?.correctionOptions ?? []
        let options = urlOptions + (record.source.map { [RuleKey.app($0)] } ?? [])
        let suggested = router.suggestedCorrectionKey(for: record)

        Section("Should have opened in…") {
            ForEach(profiles.names.filter { $0 != currentProfile }, id: \.self) { name in
                Menu(name) {
                    ruleButtons(options, suggested: suggested, to: name)
                    Divider()
                    Button("Just this once") {
                        Task { await router.correct(recordID: record.id, to: name, key: nil) }
                    }
                }
            }
        }
        Menu("\(currentProfile) was right: remember") {
            ruleButtons(options, suggested: suggested, to: currentProfile)
        }
        Divider()
        Button("Open again in \(currentProfile)") {
            Task { await router.openAgain(recordID: record.id) }
        }
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.url.absoluteString, forType: .string)
        }
    }
}

struct AppRuleSuggestionBanner: View {
    @EnvironmentObject private var router: Router
    let suggestion: AppRuleSuggestion.Suggestion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your last \(AppRuleSuggestion.streak) links from \(suggestion.source.name) opened in \(suggestion.profileName).")
                    .font(.callout)
                Text("Always open links from \(suggestion.source.name) there? Rules you've made or corrected still win.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Not now") { router.dismissSuggestion() }
                .controlSize(.small)
            Button("Always") { router.acceptSuggestion() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.yellow.opacity(0.08))
    }
}

// MARK: - Rules

struct RulesView: View {
    @EnvironmentObject private var rules: RuleStore
    @EnvironmentObject private var usage: RuleUsageStore
    @EnvironmentObject private var profiles: DiaProfilesMonitor
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var profileFilter: String?
    @State private var newProfile = ""

    var body: some View {
        let live = rules.ruleSet.liveRules
        let rows = RuleListing.arrange(rules: live, usage: usage.usage, query: query, profile: profileFilter)
        let addCandidate = RuleListing.addCandidate(for: query, existing: live)
        let counts = Dictionary(grouping: live, by: { $0.profileName.lowercased() }).mapValues(\.count)

        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search, or type a site to add a rule", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { if let addCandidate { add(addCandidate) } }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(nil, label: "All", count: live.count)
                        ForEach(profiles.names, id: \.self) { name in
                            filterChip(name, label: name, count: counts[name.lowercased()] ?? 0)
                        }
                    }
                }
            }
            .padding(10)
            .onAppear { if newProfile.isEmpty { newProfile = profileFilter ?? profiles.names.first ?? "" } }

            Divider()

            if let candidate = addCandidate {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    Text(candidate.label)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Picker("", selection: $newProfile) {
                        ForEach(profiles.names, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button("Add") { add(candidate) }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.06))
                Divider()
            }

            if rows.isEmpty {
                Text(emptyMessage(hasCandidate: addCandidate != nil))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            RuleRow(row: row)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text(footer(shown: rows.count, total: live.count))
                if let error = rules.lastError {
                    Text(error).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Button("Show File") {
                    NSWorkspace.shared.activateFileViewerSelecting([rules.fileURL])
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func footer(shown: Int, total count: Int) -> String {
        let total = "\(count) \(count == 1 ? "rule" : "rules")"
        let prefix = shown == count ? total : "\(shown) of \(total)"
        return "\(prefix) · synced with \(settings.rulesLocation.label)"
    }

    private func emptyMessage(hasCandidate: Bool) -> String {
        if rules.ruleSet.liveRules.isEmpty {
            return "No rules yet. Jev creates them as you click links, and corrections from Recent save them too."
        }
        if hasCandidate { return "No rule for that yet. Add it above." }
        return query.isEmpty ? "No rules for \(profileFilter ?? "this profile") yet." : "No rules match “\(query)”."
    }

    private func filterChip(_ profile: String?, label: String, count: Int) -> some View {
        let selected = profileFilter == profile
        return Button {
            profileFilter = profile
            if let profile { newProfile = profile }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func add(_ key: RuleKey) {
        guard !newProfile.isEmpty else { return }
        rules.upsert(key: key, profileName: newProfile, origin: .manual)
        query = ""
    }
}

struct RuleRow: View {
    @EnvironmentObject private var rules: RuleStore
    @EnvironmentObject private var profiles: DiaProfilesMonitor
    let row: RuleListing.Row

    private var rule: Rule { row.rule }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.key.label)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { rule.profileName },
                set: { newValue in
                    var updated = rule
                    updated.profileName = newValue
                    updated.origin = .manual
                    rules.update(updated)
                }
            )) {
                ForEach(profiles.names, id: \.self) { Text($0).tag($0) }
                if !profiles.names.contains(rule.profileName) {
                    Text(rule.profileName).tag(rule.profileName)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            Button {
                rules.delete(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .opacity(row.isStale ? 0.55 : 1)
        .help(row.isStale ? "Not used in 90 days" : "")
    }

    /// "Jev · used 2 hr. ago · 14×" / "yours · never used"
    private var detail: String {
        let whose = rule.origin == .learned ? "Jev" : "yours"
        guard let usage = row.usage else { return "\(whose) · never used" }
        let age = usage.lastUsed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(whose) · used \(age) · \(usage.count)×"
    }
}
