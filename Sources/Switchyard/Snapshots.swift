import AppKit
import RouterCore
import SwiftUI

/// `--snapshot-onboarding <dir>`: render every setup step and the menu's Recent and Rules tabs,
/// in light and dark, to PNGs, then quit.
/// Uses fixture state, so no system calls, network or permissions are involved.
@MainActor
enum Snapshots {
    /// Made-up profiles with Dia-style colors, so renders never show real ones.
    static let profiles = [
        BrowserProfile(directory: "Profile 1", name: "Personal", colorARGB: 0xFFEDA900),
        BrowserProfile(directory: "Profile 2", name: "Work", colorARGB: 0xFF00B785),
        BrowserProfile(directory: "Profile 3", name: "Test", colorARGB: 0xFFFCE4EC),   // a pale Chrome-style pastel
    ]

    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        renderRecent(to: directory)
        renderRules(to: directory)

        for step in OnboardingModel.Step.allCases {
            for variant in variants(for: step) {
                let model = OnboardingModel(live: false)
                model.step = step
                model.browserInstalled = true
                model.installedBrowsers = [.dia, .chrome]
                model.profiles = profiles.map(\.name)
                model.currentBrowserName = "Dia"
                variant.configure(model)

                let name = String(format: "%02d-%@%@", step.rawValue + 1, step.shortTitle.lowercased(), variant.suffix)
                writeBothAppearances(OnboardingView(model: model), size: NSSize(width: 640, height: 560), to: directory, name: name)
            }
        }
    }

    /// The menu's Recent list with made-up links, one per kind of explanation.
    static func renderRecent(to directory: URL) {
        let rules = RuleStore.shared
        let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        let appRule = rules.upsert(key: .app(slack), profileName: "Work", origin: .corrected)
        let learned = rules.upsert(key: RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme"), profileName: "Work", origin: .learned)
        let confirmed = rules.upsert(key: RuleKey(host: "game.example", hostMatch: .domain), profileName: "Personal", origin: .corrected)
        let moved = rules.upsert(key: RuleKey(host: "shop.example", hostMatch: .domain), profileName: "Personal", origin: .corrected)
        let now = Date()
        func url(_ s: String) -> URL { URL(string: s)! }
        let records = [
            RoutingRecord(url: url("https://app.example-bank.com/e/er"), date: now.addingTimeInterval(-16), profileName: "Work",
                          decision: .rule(id: appRule.id, label: appRule.key.label), latencyMilliseconds: 0.6, sourceApp: slack),
            RoutingRecord(url: url("https://trk.email.shop.example/c/m"), date: now.addingTimeInterval(-36), profileName: "Work",
                          decision: .rule(id: appRule.id, label: appRule.key.label), latencyMilliseconds: 1.0, sourceApp: slack,
                          learnedRuleID: moved.id, correctedTo: "Personal"),
            RoutingRecord(url: url("https://github.com/acme/web"), date: now.addingTimeInterval(-240), profileName: "Work",
                          decision: .jev(confidence: 0.84, scope: .firstPathSegment), latencyMilliseconds: 169,
                          sourceApp: SourceApp(bundleID: "com.apple.MobileSMS", name: "Messages"), learnedRuleID: learned.id),
            RoutingRecord(url: url("https://www.example.edu/courses/intro-to-ceramics"), date: now.addingTimeInterval(-265),
                          profileName: "Personal", decision: .jev(confidence: 0.96, scope: LinkScope.none), latencyMilliseconds: 195,
                          sourceApp: SourceApp(bundleID: "com.apple.MobileSMS", name: "Messages")),
            RoutingRecord(url: url("https://game.example/join/room-42"), date: now.addingTimeInterval(-300), profileName: "Personal",
                          decision: .lowConfidence(confidence: 0.47), latencyMilliseconds: 183,
                          sourceApp: SourceApp(bundleID: "com.apple.MobileSMS", name: "Messages"), learnedRuleID: confirmed.id),
            RoutingRecord(url: url("https://news.example.org/story"), date: now.addingTimeInterval(-448), profileName: "Personal",
                          decision: .lowConfidence(confidence: 0.61), latencyMilliseconds: 289),
            RoutingRecord(url: url("https://status.example.com"), date: now.addingTimeInterval(-3300), profileName: "Personal",
                          decision: .fallback(.timeout), latencyMilliseconds: 1201),
        ]
        let list = VStack(spacing: 0) {
            ForEach(records) { record in
                RecentRow(record: record)
                Divider()
            }
        }
        .frame(width: 460)
        .environmentObject(Router.shared)
        .environmentObject(rules)
        writeBothAppearances(list, size: NSSize(width: 460, height: 420), to: directory, name: "menu-recent")
    }

    /// The Rules tab with made-up rules and usage (call after renderRecent, which adds rules).
    static func renderRules(to directory: URL) {
        let rules = RuleStore.shared
        let usage = RuleUsageStore.shared
        let now = Date()
        let extra = [
            rules.upsert(key: RuleKey(host: "example.edu", hostMatch: .domain), profileName: "Personal", origin: .learned),
            rules.upsert(key: RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/kev"), profileName: "Personal", origin: .learned),
            rules.upsert(key: RuleKey(host: "acme.slack.com", hostMatch: .exact), profileName: "Work", origin: .learned),
            rules.upsert(key: RuleKey(host: "old-vendor.example", hostMatch: .domain), profileName: "Work", origin: .learned),
        ]
        let all = rules.browserRules
        for (index, rule) in all.enumerated() where rule.id != extra[3].id {
            for hit in 0...(index % 4) {
                usage.recordUse(of: rule.id, at: now.addingTimeInterval(-Double(index * 3_600 + hit * 60)))
            }
        }
        usage.recordUse(of: extra[3].id, at: now.addingTimeInterval(-120 * 86_400))

        let view = RulesView()
            .frame(width: 460, height: 470)
            .environmentObject(rules)
            .environmentObject(usage)
            .environmentObject(AppSettings.shared)
        writeBothAppearances(view, size: NSSize(width: 460, height: 470), to: directory, name: "menu-rules")
    }

    private struct Variant {
        var suffix = ""
        var configure: (OnboardingModel) -> Void = { _ in }
    }

    private static func variants(for step: OnboardingModel.Step) -> [Variant] {
        switch step {
        case .browser:
            [Variant(), Variant(suffix: "-chrome") { $0.browser = .chrome }]
        case .profileList:
            [Variant(), Variant(suffix: "-missing") { $0.browserInstalled = false; $0.profiles = [] }]
        case .jev:
            [Variant(),
             Variant(suffix: "-failed") { $0.apiKeyDraft = "ts_live_xxxxxxxx"; $0.keyState = .failed("TypeSafe didn't accept that key. Check it and try again.") },
             Variant(suffix: "-connected") { $0.keyState = .connected(milliseconds: 184) }]
        case .profiles:
            [Variant { model in
                model.generationNote = OnboardingModel.generationNote(drafted: ["Personal", "Work", "Test"], blank: [])
                let settings = AppSettings.shared
                settings.setDescription("Signed in to Google as you@example.com. Sites used mostly in this profile: nytimes.com, bank.example, strava.com. Also the default for anything that doesn't clearly belong to another profile.", for: "Personal")
                settings.setDescription("Signed in to Google as you@acme.com (acme.com Google Workspace). Sites used mostly in this profile: github.com/acme, app.shortcut.com/acme, acme.slack.com, app.datadoghq.com.", for: "Work")
                settings.setDescription("Signed in to Google as tester@example.com. Sites used mostly in this profile: shop.example.com, accounts.example.com.", for: "Test")
            },
             Variant(suffix: "-drafting") { $0.isGenerating = true }]
        case .permission:
            [Variant { $0.permission = .notDetermined }, Variant(suffix: "-denied") { $0.permission = .denied },
             Variant(suffix: "-chrome") { $0.browser = .chrome; $0.permission = .notDetermined },
             Variant(suffix: "-granted") { $0.permission = .granted }]
        case .defaultBrowser:
            [Variant(), Variant(suffix: "-done") { $0.isDefaultBrowser = true }]
        default:
            [Variant()]
        }
    }

    /// `<name>-light.png` and `<name>-dark.png`, with the made-up profiles.
    private static func writeBothAppearances<V: View>(_ view: V, size: NSSize, to directory: URL, name: String) {
        let view = view
            .environmentObject(ProfilesMonitor.shared)
            .environment(\.profilesOverride, profiles)
            .background(Color(nsColor: .windowBackgroundColor))
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            write(view, appearance: appearance, size: size, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    private static func write<V: View>(_ view: V, appearance: NSAppearance.Name, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
