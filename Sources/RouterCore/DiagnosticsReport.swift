import Foundation

/// What "Copy Diagnostics" puts on the clipboard, for a GitHub issue. Deliberately free of
/// anything personal: no URLs or hosts, no profile names or descriptions, no key. Decisions are
/// listed by kind and timing only.
public struct DiagnosticsReport: Sendable {
    public var appVersion: String
    public var macOS: String
    public var architecture: String
    public var browser: String
    public var installedBrowsers: [String]
    public var browserPermission: String
    public var notifications: String
    public var hasKey: Bool
    public var keyRejected: Bool
    public var jev: String
    public var rulesFolder: String
    public var rules: Int
    public var rulesReadOnly: String?
    public var profiles: Int
    public var isRehearsal: Bool
    /// Newest first: `Decision.badge` and the record's latency.
    public var recentDecisions: [(decision: String, latency: String)]

    public init(appVersion: String, macOS: String, architecture: String, browser: String, installedBrowsers: [String],
                browserPermission: String, notifications: String, hasKey: Bool, keyRejected: Bool, jev: String,
                rulesFolder: String, rules: Int, rulesReadOnly: String?, profiles: Int, isRehearsal: Bool,
                recentDecisions: [(decision: String, latency: String)]) {
        self.appVersion = appVersion
        self.macOS = macOS
        self.architecture = architecture
        self.browser = browser
        self.installedBrowsers = installedBrowsers
        self.browserPermission = browserPermission
        self.notifications = notifications
        self.hasKey = hasKey
        self.keyRejected = keyRejected
        self.jev = jev
        self.rulesFolder = rulesFolder
        self.rules = rules
        self.rulesReadOnly = rulesReadOnly
        self.profiles = profiles
        self.isRehearsal = isRehearsal
        self.recentDecisions = recentDecisions
    }

    /// Recent decisions as records, keeping only what's safe to share.
    public static func decisions(from records: [RoutingRecord], limit: Int = 10) -> [(decision: String, latency: String)] {
        records.prefix(limit).map { record in
            let corrected = record.correctedTo == nil ? "" : " · corrected"
            return (record.decision.badge + corrected, record.latencyLabel)
        }
    }

    public var markdown: String {
        var lines = [
            "### Switchyard diagnostics",
            "",
            "- Switchyard: \(appVersion)\(isRehearsal ? " (rehearsal)" : "")",
            "- macOS: \(macOS) (\(architecture))",
            "- Browser: \(browser) · installed: \(installedBrowsers.isEmpty ? "none found" : installedBrowsers.joined(separator: ", "))",
            "- Browser permission: \(browserPermission)",
            "- Notifications: \(notifications)",
            "- TypeSafe key: \(hasKey ? (keyRejected ? "saved, rejected" : "saved") : "none (asks with the picker)")",
            "- Jev: \(jev)",
            "- Rules: \(rules) in \(rulesFolder)\(rulesReadOnly.map { " · read-only: \($0)" } ?? "")",
            "- Profiles: \(profiles)",
        ]
        if !recentDecisions.isEmpty {
            lines += ["", "Recent decisions (newest first, no links):"]
            lines += recentDecisions.map { "- \($0.decision) · \($0.latency)" }
        }
        return lines.joined(separator: "\n")
    }
}
