import Foundation

/// A browser Switchyard can route links into.
public enum BrowserKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dia
    case chrome
    case brave
    case edge
    case vivaldi
    case firefox

    public var id: String { rawValue }

    public enum Opening: Sendable {
        /// Dia ignores `--profile-directory`, so tabs are opened through its AppleScript dictionary.
        case appleScript
        /// Chromium's `--profile-directory=<dir>` flag, handed to the running browser.
        case profileDirectoryFlag
        /// Firefox's `-profile <path> -new-tab <url>`: Firefox hands it to that profile's running
        /// instance, or starts one (each Firefox profile runs as its own app).
        case firefoxProfile
    }

    public var bundleIdentifier: String {
        switch self {
        case .dia: "company.thebrowser.dia"
        case .chrome: "com.google.Chrome"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .firefox: "org.mozilla.firefox"
        }
    }

    public var displayName: String {
        switch self {
        case .dia: "Dia"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .vivaldi: "Vivaldi"
        case .firefox: "Firefox"
        }
    }

    /// The browser's data folder (Chromium's "User Data"; Firefox's folder holding `profiles.ini`),
    /// relative to ~/Library/Application Support.
    public var userDataPath: String {
        switch self {
        case .dia: "Dia/User Data"
        case .chrome: "Google/Chrome"
        case .brave: "BraveSoftware/Brave-Browser"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .firefox: "Firefox"
        }
    }

    public var opening: Opening {
        switch self {
        case .dia: .appleScript
        case .firefox: .firefoxProfile
        default: .profileDirectoryFlag
        }
    }

    /// Opens through a new app instance with launch arguments (everything but Dia).
    public var opensWithArguments: Bool {
        opening != .appleScript
    }

    /// Verified end to end (profile listing and opening in a chosen profile).
    public var isVerified: Bool {
        self == .dia || self == .chrome
    }

    public func userDataDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(userDataPath, isDirectory: true)
    }

    /// The file listing the browser's profiles: Chromium's `Local State`, Firefox's `profiles.ini`.
    /// Reading it is what macOS's "data from other apps" permission covers.
    public func profileListFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        userDataDirectory(home: home).appendingPathComponent(self == .firefox ? "profiles.ini" : "Local State")
    }

    /// The browser's profiles, from the contents of `profileListFile`.
    public func profiles(fromProfileList data: Data, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserProfile] {
        switch self {
        case .firefox: FirefoxProfiles.profiles(fromINI: String(decoding: data, as: UTF8.self), root: userDataDirectory(home: home))
        default: ChromiumLocalState.profiles(from: data)
        }
    }

    /// A profile's folder. Chromium profiles are named folders inside the data folder; Firefox
    /// profiles are stored by full path (they can live anywhere).
    public func profileFolder(_ profile: BrowserProfile, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        profile.directory.hasPrefix("/")
            ? URL(fileURLWithPath: profile.directory, isDirectory: true)
            : userDataDirectory(home: home).appendingPathComponent(profile.directory, isDirectory: true)
    }

    /// Arguments for a new instance of the browser that open `url` in `profile`.
    public func launchArguments(opening url: URL, in profile: BrowserProfile) -> [String] {
        switch opening {
        case .firefoxProfile: ["-profile", profile.directory, "-new-tab", url.absoluteString]
        default: ["--profile-directory=\(profile.directory)", url.absoluteString]
        }
    }
}
