import Foundation

/// How often a rule has decided a link, on this Mac. Kept locally, not in the synced rules
/// file, so routing never rewrites the file other Macs are syncing.
public struct RuleUsage: Codable, Equatable, Sendable {
    public var lastUsed: Date
    public var count: Int

    public init(lastUsed: Date, count: Int) {
        self.lastUsed = lastUsed
        self.count = count
    }
}

/// The Rules tab: one field to search and add, most recently used first, stale rules last.
public enum RuleListing {
    public static let staleAfter: TimeInterval = 90 * 24 * 60 * 60

    public struct Row: Equatable, Sendable, Identifiable {
        public let rule: Rule
        public let usage: RuleUsage?
        /// Not used for 90 days (or never used and at least 90 days old).
        public let isStale: Bool

        public var id: UUID { rule.id }
    }

    public static func arrange(
        rules: [Rule],
        usage: [UUID: RuleUsage],
        query: String,
        profile: String?,
        now: Date = Date()
    ) -> [Row] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return rules
            .filter { !$0.deleted }
            .filter { rule in
                profile.map { rule.profileName.caseInsensitiveCompare($0) == .orderedSame } ?? true
            }
            .filter { rule in
                let haystack = "\(rule.key.label) \(rule.profileName)".lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .map { rule in
                let used = usage[rule.id]
                let lastSeen = used?.lastUsed ?? rule.updatedAt
                return Row(rule: rule, usage: used, isStale: now.timeIntervalSince(lastSeen) > staleAfter)
            }
            .sorted { lhs, rhs in
                if lhs.isStale != rhs.isStale { return !lhs.isStale }
                switch (lhs.usage?.lastUsed, rhs.usage?.lastUsed) {
                case let (l?, r?) where l != r: return l > r
                case (.some, nil): return true
                case (nil, .some): return false
                default:
                    if lhs.rule.updatedAt != rhs.rule.updatedAt { return lhs.rule.updatedAt > rhs.rule.updatedAt }
                    return lhs.rule.key.label < rhs.rule.key.label
                }
            }
    }

    /// The rule to offer adding when the search text is itself a rule that doesn't exist yet.
    /// A bare registrable domain (`slack.com`) covers its subdomains; a subdomain
    /// (`acme.slack.com`) is exact; `*.` forces subdomains.
    public static func addCandidate(for query: String, existing: [Rule]) -> RuleKey? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(" "),
              let exact = RuleKey.parse(text, includeSubdomains: false) else { return nil }
        let key: RuleKey
        if exact.hostMatch == .domain || (exact.pathPrefix == nil && exact.query == nil
                                          && PublicSuffix.registrableDomain(for: exact.host) == exact.host) {
            key = RuleKey(host: exact.host, hostMatch: .domain, pathPrefix: exact.pathPrefix, query: exact.query)
        } else {
            key = exact
        }
        return existing.contains { !$0.deleted && $0.key == key } ? nil : key
    }
}
