import Foundation
import RouterCore

enum RulesLocation: String, CaseIterable, Identifiable {
    case iCloud
    case dropbox
    case local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iCloud: "iCloud Drive"
        case .dropbox: "Dropbox"
        case .local: "This Mac only"
        }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// The folder that must already exist for this location to be usable.
    var providerRoot: URL {
        switch self {
        case .iCloud: Self.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        case .dropbox: Self.home.appendingPathComponent("Dropbox")
        case .local: AppEnvironment.dataDirectory
        }
    }

    var directory: URL {
        // Rehearsals write "synced" rules into their throwaway directory instead.
        if AppEnvironment.isIsolated {
            return AppEnvironment.dataDirectory.appendingPathComponent("sync-\(rawValue)", isDirectory: true)
        }
        return switch self {
        case .iCloud: providerRoot.appendingPathComponent("Switchyard")
        // Not Dropbox/Apps: that's Dropbox's own app-folder area, and when it's excluded with
        // Selective Sync, Dropbox moves anything created there aside ("Apps (Selective Sync
        // Conflict)"), taking the rules with it.
        case .dropbox: providerRoot.appendingPathComponent("Switchyard")
        case .local: AppEnvironment.dataDirectory
        }
    }

    /// Rules files from earlier versions' folders for this location, to merge in once:
    /// Dropbox/Apps/Switchyard and any copies Dropbox moved aside as Selective Sync conflicts.
    var legacyRulesFiles: [URL] {
        guard self == .dropbox, !AppEnvironment.isIsolated else { return [] }
        // Check the known names rather than listing the Dropbox folder: a listing makes Dropbox
        // enumerate everything (online-only folders included) and can take minutes.
        let names = ["Apps", "Apps (Selective Sync Conflict)"] + (1...30).map { "Apps (Selective Sync Conflict \($0))" }
        return names
            .map { providerRoot.appendingPathComponent($0).appendingPathComponent("Switchyard/rules.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var rulesFile: URL {
        directory.appendingPathComponent("rules.json")
    }

    var isAvailable: Bool {
        self == .local || FileManager.default.fileExists(atPath: providerRoot.path)
    }

    static var automatic: RulesLocation {
        [.iCloud, .dropbox].first(where: \.isAvailable) ?? .local
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = AppEnvironment.defaults

    /// Every browser links can open in (Switchyard 2), in order. The first is the original one:
    /// its profiles keep their plain names, descriptions and rules from 1.x. Installs from 1.x
    /// start with their one browser; installs from before multi-browser support with Dia.
    @Published var browsers: [BrowserKind] {
        didSet {
            if browsers.isEmpty { browsers = [.dia]; return }
            defaults.set(browsers.map(\.rawValue), forKey: SettingsKey.browsers.rawValue)
            // 1.x reads this one: keep it pointing at the original browser so a downgrade works.
            defaults.set(browsers[0].rawValue, forKey: SettingsKey.browser.rawValue)
        }
    }

    /// The original (first) browser. Setting it makes it the only one.
    var browser: BrowserKind {
        get { browsers.first ?? .dia }
        set { browsers = [newValue] }
    }

    var isMultiBrowser: Bool { browsers.count > 1 }

    @Published var rulesLocation: RulesLocation {
        didSet { defaults.set(rulesLocation.rawValue, forKey: SettingsKey.rulesLocation.rawValue) }
    }

    @Published var profileThreshold: Double {
        didSet { defaults.set(profileThreshold, forKey: SettingsKey.profileThreshold.rawValue) }
    }

    @Published var fallbackProfileName: String {
        didSet { defaults.set(fallbackProfileName, forKey: SettingsKey.fallbackProfileName.rawValue) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: SettingsKey.notificationsEnabled.rawValue) }
    }

    @Published var notifyLowConfidence: Bool {
        didSet { defaults.set(notifyLowConfidence, forKey: SettingsKey.notifyLowConfidence.rawValue) }
    }

    /// When Jev is unsure: ask with the picker (Jev's guess marked, Esc takes it), or just open
    /// its guess and flag the row.
    @Published var askWhenUnsure: Bool {
        didSet { defaults.set(askWhenUnsure, forKey: SettingsKey.askWhenUnsure.rawValue) }
    }

    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: SettingsKey.onboardingCompleted.rawValue) }
    }

    /// Jev criteria per profile, keyed by lowercased profile name. Missing = seeded default.
    @Published private(set) var profileDescriptions: [String: String] {
        didSet { defaults.set(profileDescriptions, forKey: SettingsKey.profileDescriptions.rawValue) }
    }

    private init() {
        let legacyBrowser = defaults.string(forKey: SettingsKey.browser.rawValue).flatMap(BrowserKind.init(rawValue:)) ?? .dia
        let stored = (defaults.stringArray(forKey: SettingsKey.browsers.rawValue) ?? []).compactMap(BrowserKind.init(rawValue:))
        browsers = stored.isEmpty ? [legacyBrowser] : stored
        rulesLocation = defaults.string(forKey: SettingsKey.rulesLocation.rawValue).flatMap(RulesLocation.init(rawValue:))
            ?? RulesLocation.automatic
        profileThreshold = defaults.object(forKey: SettingsKey.profileThreshold.rawValue) as? Double ?? DecisionPolicy.defaultProfileThreshold
        fallbackProfileName = defaults.string(forKey: SettingsKey.fallbackProfileName.rawValue) ?? ProfileDefaults.fallbackProfileName
        notificationsEnabled = defaults.object(forKey: SettingsKey.notificationsEnabled.rawValue) as? Bool ?? true
        notifyLowConfidence = defaults.object(forKey: SettingsKey.notifyLowConfidence.rawValue) as? Bool ?? false
        profileDescriptions = defaults.dictionary(forKey: SettingsKey.profileDescriptions.rawValue) as? [String: String] ?? [:]
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted.rawValue)
        askWhenUnsure = defaults.object(forKey: SettingsKey.askWhenUnsure.rawValue) as? Bool ?? true

        // Persist the automatic choice so the rules file doesn't move if another provider appears later.
        defaults.set(rulesLocation.rawValue, forKey: SettingsKey.rulesLocation.rawValue)
    }

    /// Jev's profile criteria: each profile with its current description.
    func jevProfiles(for names: [String]) -> [Jev.Profile] {
        names.map { Jev.Profile(name: $0, description: description(for: $0)) }
    }

    func hasStoredDescription(for profileName: String) -> Bool {
        profileDescriptions[profileName.lowercased()] != nil
    }

    func description(for profileName: String) -> String {
        if let stored = profileDescriptions[profileName.lowercased()] { return stored }
        // "Dia · Personal" for the original browser keeps the description "Personal" had in 1.x.
        if let plain = plainName(ofOriginalBrowserLabel: profileName), let stored = profileDescriptions[plain.lowercased()] {
            return stored
        }
        return ProfileDefaults.description(for: profileName)
    }

    /// "Personal" for "Dia · Personal" when Dia is the original browser.
    func plainName(ofOriginalBrowserLabel label: String) -> String? {
        let prefix = "\(browser.displayName) · "
        guard isMultiBrowser, label.hasPrefix(prefix) else { return nil }
        return String(label.dropFirst(prefix.count))
    }

    func setDescription(_ description: String, for profileName: String) {
        profileDescriptions[profileName.lowercased()] = description
    }
}
