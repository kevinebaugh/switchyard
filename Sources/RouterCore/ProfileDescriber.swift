import Foundation

/// A Google account signed in to a Dia profile.
public struct ProfileAccount: Hashable, Sendable {
    public var email: String
    /// Google Workspace domain (e.g. `acme.com`), nil for consumer accounts.
    public var workspaceDomain: String?

    public init(email: String, workspaceDomain: String?) {
        self.email = email
        let domain = workspaceDomain?.trimmingCharacters(in: .whitespaces).lowercased()
        self.workspaceDomain = (domain?.isEmpty ?? true) || domain == "no_hosted_domain" ? nil : domain
    }
}

/// What Switchyard can learn about a profile locally: who it's signed in as and where it goes.
public struct ProfileSignals: Sendable, Equatable {
    public var name: String
    public var accounts: [ProfileAccount]
    /// Site key (`host` or `host/segment`) → visits.
    public var siteVisits: [String: Int]

    public init(name: String, accounts: [ProfileAccount], siteVisits: [String: Int]) {
        self.name = name
        self.accounts = accounts
        self.siteVisits = siteVisits
    }
}

/// Writes Jev's profile criteria from local signals, so setup doesn't start from a blank page.
public enum ProfileDescriber {
    static let maxSites = 8
    /// A site needs this many visits in a profile to say anything about it.
    static let minVisits = 3
    /// Without a signed-in account, a profile needs this many distinctive sites to be described
    /// at all. Less than that is a guess, and an empty description is better than a wrong one.
    static let minSites = 3
    /// Share of a site's visits (across all profiles) that must happen in one profile.
    static let distinctiveShare = 0.6

    /// Sites where the signed-in account, not the site, decides the profile (every profile uses
    /// Google), plus local development servers.
    static let accountDecidedDomains: Set<String> = [
        "google.com", "gmail.com", "googleusercontent.com", "gstatic.com",
        "microsoftonline.com", "live.com", "office.com", "microsoft.com",
        "localhost", "127.0.0.1",
    ]

    /// Path segments that are routes, not account or workspace names.
    static let routeWords: Set<String> = [
        "a", "about", "account", "accounts", "admin", "analytics", "api", "app", "apps", "archive", "archives",
        "auth", "billing", "blog", "c", "calendar", "cars", "cart", "channel", "channels", "checkout", "d",
        "dashboard", "dashboards", "docs", "document", "dp", "drive", "edit", "embed", "en", "explore", "feed",
        "file", "files", "flights", "forms", "go", "gp", "help", "home", "hotels", "i", "inbox", "index", "issue",
        "issues", "item", "l", "link", "login", "mail", "maps", "messages", "metric", "metrics", "new", "news",
        "notifications", "oauth", "open", "orders", "org", "orgs", "out", "p", "people", "playlist",
        "presentation", "product", "products", "profile", "project", "projects", "pull", "pulls", "r",
        "redirect", "report", "reports", "results", "s", "search", "settings", "share", "shop", "shorts",
        "signin", "sign", "spreadsheets", "status", "support", "t", "team", "teams", "trips", "u", "url", "us",
        "user", "users", "video", "videos", "view", "watch", "wiki", "workspace", "workspaces",
    ]

    /// Aggregate history rows into site keys: every host (`github.com`), plus `host/segment`
    /// for first path segments that look like account or workspace names (`github.com/acme`).
    public static func siteVisits(from rows: [(url: String, visits: Int)]) -> [String: Int] {
        var result: [String: Int] = [:]
        for row in rows {
            guard let components = URLComponents(string: row.url),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  var host = components.host?.lowercased(), !host.isEmpty else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            let visits = max(row.visits, 1)
            result[host, default: 0] += visits
            // Paths match case-insensitively everywhere else, so github.com/Acme and /acme are one site.
            if let segment = components.path.split(separator: "/").first.map({ $0.lowercased() }), looksLikeName(segment) {
                result["\(host)/\(segment)", default: 0] += visits
            }
        }
        return result
    }

    static func looksLikeName(_ segment: String) -> Bool {
        let lowered = segment.lowercased()
        guard (2...40).contains(segment.count), !lowered.contains("."), !lowered.hasPrefix("@") else { return false }
        let words = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard !words.contains(where: routeWords.contains) else { return false }
        let digits = segment.filter(\.isNumber).count
        // Ids and hashes, not names.
        return digits * 3 < segment.count && !(segment.count >= 16 && segment.allSatisfy(\.isHexDigit))
    }

    static func isAccountDecided(_ host: String) -> Bool {
        accountDecidedDomains.contains(PublicSuffix.registrableDomain(for: host))
    }

    /// Sites that get most of their visits in this profile, most distinctive first. A host only
    /// this profile uses is listed as-is (`acme.slack.com`); a host other profiles use too is
    /// listed by its distinctive workspace paths (`github.com/acme`) when it has any.
    public static func distinctiveSites(for profile: ProfileSignals, among all: [ProfileSignals]) -> [String] {
        let profilesWithHistory = all.filter { !$0.siteVisits.isEmpty }.count

        func score(_ key: String) -> Double? {
            guard let visits = profile.siteVisits[key], visits >= minVisits else { return nil }
            let total = all.reduce(0) { $0 + ($1.siteVisits[key] ?? 0) }
            let share = Double(visits) / Double(max(total, 1))
            guard profilesWithHistory <= 1 || share >= distinctiveShare else { return nil }
            return Double(visits) * share
        }

        var candidates: [(String, Double)] = []
        for host in profile.siteVisits.keys where !host.contains("/") && !isAccountDecided(host) {
            let segments = profile.siteVisits.keys
                .filter { $0.hasPrefix(host + "/") }
                .compactMap { key in score(key).map { (key, $0) } }
            let usedElsewhere = all.contains { $0.name != profile.name && ($0.siteVisits[host] ?? 0) >= minVisits }

            // A host other profiles use too is told apart by its workspace paths, when there are any.
            if usedElsewhere, !segments.isEmpty {
                candidates += segments
            } else if let hostScore = score(host) {
                candidates.append((host, hostScore))
            }
        }
        return candidates
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(maxSites)
            .map(\.0)
    }

    /// A description for Jev, or nil when there's nothing to go on.
    public static func describe(_ profile: ProfileSignals, among all: [ProfileSignals], isFallback: Bool) -> String? {
        var sentences: [String] = []

        let accounts = profile.accounts.map { account in
            account.workspaceDomain.map { "\(account.email) (\($0) Google Workspace)" } ?? account.email
        }
        if !accounts.isEmpty {
            sentences.append("Signed in to Google as \(list(accounts)).")
        }

        let sites = distinctiveSites(for: profile, among: all)
        let enoughSites = sites.count >= minSites
        if enoughSites || (!accounts.isEmpty && !sites.isEmpty) {
            sentences.append("Sites used mostly in this profile: \(sites.joined(separator: ", ")).")
        }

        // Too little to go on: leave it blank rather than guess.
        guard !accounts.isEmpty || enoughSites else { return nil }
        if isFallback {
            sentences.append("Also the default for anything that doesn't clearly belong to another profile.")
        }
        return sentences.joined(separator: " ")
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
