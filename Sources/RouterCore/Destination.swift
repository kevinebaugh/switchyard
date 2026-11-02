import Foundation

/// Where a link opens: a browser and one of its profiles ("Firefox · Personal"), or a browser
/// without profiles Switchyard can choose (Safari, whose "profile" is just "Safari").
///
/// Rules already store both halves (`Rule.browser`, `Rule.profileName`), so a destination is a
/// way of looking at them, not a new stored format.
public struct Destination: Hashable, Codable, Sendable, Identifiable {
    public var browser: BrowserKind
    public var profile: String

    public init(browser: BrowserKind, profile: String) {
        self.browser = browser
        self.profile = profile
    }

    /// Safari's one destination.
    public static let safari = Destination(browser: .safari, profile: BrowserKind.safari.displayName)

    /// Stable and case-insensitive: "firefox/personal".
    public var id: String { "\(browser.rawValue)/\(profile.lowercased())" }

    /// "Personal" when only one browser is in use (exactly as before multi-browser); otherwise
    /// "Firefox · Personal", or just "Safari" for a browser without profiles.
    public func label(multiBrowser: Bool) -> String {
        guard multiBrowser else { return profile }
        return browser.hasProfiles ? "\(browser.displayName) · \(profile)" : browser.displayName
    }
}

extension Rule {
    public var destination: Destination {
        Destination(browser: effectiveBrowser, profile: profileName)
    }
}
