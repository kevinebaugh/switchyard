/// Every key Switchyard stores in its settings (UserDefaults), in one place.
///
/// These names are a promise (docs/COMPATIBILITY.md): a key never changes name or meaning
/// between versions, because settings outlive updates. To change what a setting means, add a
/// new key and migrate from the old one once.
enum SettingsKey: String, CaseIterable {
    case browser
    case rulesLocation
    case profileThreshold
    case fallbackProfileName
    case notificationsEnabled
    case notifyLowConfidence
    case onboardingCompleted
    case profileDescriptions
    case diaProfileOrder
    case dismissedAppRuleSuggestions
    case isSupporter
    case supportCardShowing
    case supportNudge
    case supportCheckoutSession
    case rejectedKeyFingerprint

    /// Per-browser keys: a browser's profile order (Dia's is `diaProfileOrder`, from before
    /// other browsers), and whether setup has asked for its data folder.
    static func profileOrder(_ browser: String) -> String { "profileOrder.\(browser)" }
    static func askedDataAccess(_ browser: String) -> String { "askedDataAccess.\(browser)" }
}
