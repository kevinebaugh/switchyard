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
        case .dropbox: providerRoot.appendingPathComponent("Apps/Switchyard")
        case .local: AppEnvironment.dataDirectory
        }
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

    /// The browser links open in. Installs from before multi-browser support are Dia.
    @Published var browser: BrowserKind {
        didSet { defaults.set(browser.rawValue, forKey: "browser") }
    }

    @Published var rulesLocation: RulesLocation {
        didSet { defaults.set(rulesLocation.rawValue, forKey: "rulesLocation") }
    }

    @Published var profileThreshold: Double {
        didSet { defaults.set(profileThreshold, forKey: "profileThreshold") }
    }

    @Published var fallbackProfileName: String {
        didSet { defaults.set(fallbackProfileName, forKey: "fallbackProfileName") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var notifyLowConfidence: Bool {
        didSet { defaults.set(notifyLowConfidence, forKey: "notifyLowConfidence") }
    }

    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: "onboardingCompleted") }
    }

    /// Jev criteria per profile, keyed by lowercased profile name. Missing = seeded default.
    @Published private(set) var profileDescriptions: [String: String] {
        didSet { defaults.set(profileDescriptions, forKey: "profileDescriptions") }
    }

    private init() {
        browser = defaults.string(forKey: "browser").flatMap(BrowserKind.init(rawValue:)) ?? .dia
        rulesLocation = defaults.string(forKey: "rulesLocation").flatMap(RulesLocation.init(rawValue:))
            ?? RulesLocation.automatic
        profileThreshold = defaults.object(forKey: "profileThreshold") as? Double ?? DecisionPolicy.defaultProfileThreshold
        fallbackProfileName = defaults.string(forKey: "fallbackProfileName") ?? ProfileDefaults.fallbackProfileName
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        notifyLowConfidence = defaults.object(forKey: "notifyLowConfidence") as? Bool ?? false
        profileDescriptions = defaults.dictionary(forKey: "profileDescriptions") as? [String: String] ?? [:]
        onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")

        // Persist the automatic choice so the rules file doesn't move if another provider appears later.
        defaults.set(rulesLocation.rawValue, forKey: "rulesLocation")
    }

    /// Jev's profile criteria: each profile with its current description.
    func jevProfiles(for names: [String]) -> [Jev.Profile] {
        names.map { Jev.Profile(name: $0, description: description(for: $0)) }
    }

    func hasStoredDescription(for profileName: String) -> Bool {
        profileDescriptions[profileName.lowercased()] != nil
    }

    func description(for profileName: String) -> String {
        profileDescriptions[profileName.lowercased()] ?? ProfileDefaults.description(for: profileName)
    }

    func setDescription(_ description: String, for profileName: String) {
        profileDescriptions[profileName.lowercased()] = description
    }
}
