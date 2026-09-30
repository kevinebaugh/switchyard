import Foundation

/// A browser Switchyard can route links into.
public enum BrowserKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dia
    case chrome
    case brave
    case edge
    case vivaldi

    public var id: String { rawValue }

    public enum Opening: Sendable {
        /// Dia ignores `--profile-directory`, so tabs are opened through its AppleScript dictionary.
        case appleScript
        /// Chromium's `--profile-directory=<dir>` flag, handed to the running browser.
        case profileDirectoryFlag
    }

    public var bundleIdentifier: String {
        switch self {
        case .dia: "company.thebrowser.dia"
        case .chrome: "com.google.Chrome"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .vivaldi: "com.vivaldi.Vivaldi"
        }
    }

    public var displayName: String {
        switch self {
        case .dia: "Dia"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .vivaldi: "Vivaldi"
        }
    }

    /// The browser's Chromium "User Data" folder, relative to ~/Library/Application Support.
    public var userDataPath: String {
        switch self {
        case .dia: "Dia/User Data"
        case .chrome: "Google/Chrome"
        case .brave: "BraveSoftware/Brave-Browser"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        }
    }

    public var opening: Opening {
        self == .dia ? .appleScript : .profileDirectoryFlag
    }

    /// Verified end to end (profile listing and opening in a chosen profile).
    public var isVerified: Bool {
        self == .dia || self == .chrome
    }

    public func userDataDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(userDataPath, isDirectory: true)
    }
}
