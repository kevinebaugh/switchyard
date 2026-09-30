import Foundation

public enum HostMatch: String, Codable, Sendable, CaseIterable {
    /// The host and every subdomain of it (`slack.com` covers `acme.slack.com`).
    case domain
    /// Only this exact host.
    case exact
}

public enum RuleOrigin: String, Codable, Sendable {
    case learned
    case corrected
    case manual
}

/// The app a link was clicked in. Identified by bundle ID (stable across Macs and
/// languages); the name is only for display.
public struct SourceApp: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public static func == (lhs: SourceApp, rhs: SourceApp) -> Bool {
        lhs.bundleID.lowercased() == rhs.bundleID.lowercased()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID.lowercased())
    }
}

/// The part of a rule that decides which URLs it matches. Two rules with the same key
/// are the same rule; upserting a key replaces the existing rule's profile.
///
/// An *app rule* has no host, only a `sourceApp`: "links from Slack".
public struct RuleKey: Hashable, Codable, Sendable {
    public var host: String
    public var hostMatch: HostMatch
    public var pathPrefix: String?
    public var query: [String: String]?
    public var sourceApp: SourceApp?

    public init(
        host: String,
        hostMatch: HostMatch,
        pathPrefix: String? = nil,
        query: [String: String]? = nil,
        sourceApp: SourceApp? = nil
    ) {
        self.host = Self.normalizeHost(host)
        self.hostMatch = hostMatch
        self.pathPrefix = Self.normalizePath(pathPrefix)
        self.query = Self.normalizeQuery(query)
        self.sourceApp = sourceApp
    }

    /// "Every link clicked in this app."
    public static func app(_ sourceApp: SourceApp) -> RuleKey {
        RuleKey(host: "", hostMatch: .exact, sourceApp: sourceApp)
    }

    public var isAppRule: Bool {
        host.isEmpty && sourceApp != nil
    }

    static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    static func normalizePath(_ path: String?) -> String? {
        guard var path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        if !path.hasPrefix("/") { path = "/" + path }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path == "/" ? nil : path.lowercased()
    }

    static func normalizeQuery(_ query: [String: String]?) -> [String: String]? {
        guard let query, !query.isEmpty else { return nil }
        var normalized: [String: String] = [:]
        for (name, value) in query {
            normalized[name.lowercased()] = value.lowercased()
        }
        return normalized
    }

    /// Parse a hand-typed rule: `app.shortcut.com/acme`, `*.slack.com`,
    /// `https://mail.google.com/?authuser=tester@example.com`.
    public static func parse(_ text: String, includeSubdomains: Bool) -> RuleKey? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        var hostMatch: HostMatch = includeSubdomains ? .domain : .exact
        if text.hasPrefix("*.") {
            text.removeFirst(2)
            hostMatch = .domain
        }

        var query: [String: String]?
        if let questionMark = text.firstIndex(of: "?") {
            let queryText = text[text.index(after: questionMark)...]
            text = String(text[..<questionMark])
            var pairs: [String: String] = [:]
            for pair in queryText.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[0].isEmpty else { continue }
                pairs[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
            query = pairs.isEmpty ? nil : pairs
        }

        let slash = text.firstIndex(of: "/")
        let host = slash.map { String(text[..<$0]) } ?? text
        let path = slash.map { String(text[$0...]) }
        guard !host.isEmpty, !host.contains(" "), host.contains(".") || host == "localhost" else { return nil }
        return RuleKey(host: host, hostMatch: hostMatch, pathPrefix: path, query: query)
    }

    public var pathDepth: Int {
        pathPrefix?.split(separator: "/").count ?? 0
    }

    /// Human-readable description, e.g. `app.shortcut.com/acme` or `all of slack.com`.
    public var label: String {
        if isAppRule, let sourceApp { return "links from \(sourceApp.name)" }
        var text = hostMatch == .domain ? "all of \(host)" : host
        if let pathPrefix { text += pathPrefix }
        if let query {
            let pairs = query.keys.sorted().map { "\($0)=\(query[$0] ?? "")" }
            text += " ?" + pairs.joined(separator: "&")
        }
        if let sourceApp { text += " from \(sourceApp.name)" }
        return text
    }
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var host: String
    public var hostMatch: HostMatch
    public var pathPrefix: String?
    public var query: [String: String]?
    public var sourceApp: SourceApp?
    /// Profile *name*, not directory: directories differ between Macs, names sync.
    public var profileName: String
    /// The browser this rule opens links in. nil in rules written before Switchyard supported
    /// more than Dia; those are Dia rules.
    public var browser: BrowserKind?
    public var origin: RuleOrigin
    public var updatedAt: Date
    public var deleted: Bool

    public init(
        id: UUID = UUID(),
        key: RuleKey,
        profileName: String,
        origin: RuleOrigin,
        browser: BrowserKind? = nil,
        updatedAt: Date = Date(),
        deleted: Bool = false
    ) {
        self.id = id
        self.host = key.host
        self.hostMatch = key.hostMatch
        self.pathPrefix = key.pathPrefix
        self.query = key.query
        self.sourceApp = key.sourceApp
        self.profileName = profileName
        self.origin = origin
        self.browser = browser
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    public var effectiveBrowser: BrowserKind { browser ?? .dia }

    public var key: RuleKey {
        get { RuleKey(host: host, hostMatch: hostMatch, pathPrefix: pathPrefix, query: query, sourceApp: sourceApp) }
        set {
            host = newValue.host
            hostMatch = newValue.hostMatch
            pathPrefix = newValue.pathPrefix
            query = newValue.query
            sourceApp = newValue.sourceApp
        }
    }
}
