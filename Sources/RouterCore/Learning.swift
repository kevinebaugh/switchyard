import Foundation

/// Whether Jev may route links on its own. A new Switchyard starts by asking about every new site
/// (the picker, with Jev's guess preselected when there's a key). Each pick where Jev was
/// confident counts: agreeing extends a streak, disagreeing resets it. At every
/// `streakForOffer` agreements in a row, Switchyard offers to let Jev decide confident links.
public struct JevTrust: Codable, Equatable, Sendable {
    public static let streakForOffer = 10

    /// Jev decides links it's confident about; otherwise it only suggests in the picker.
    public var decidesConfidentLinks: Bool
    /// Consecutive confident guesses you agreed with.
    public private(set) var streak = 0

    public init(decidesConfidentLinks: Bool, streak: Int = 0) {
        self.decidesConfidentLinks = decidesConfidentLinks
        self.streak = streak
    }

    /// You answered the picker. `jevGuess` is Jev's pick when it was confident (nil when Jev wasn't
    /// asked, or was unsure: those don't count either way). Returns true when it's time to offer.
    public mutating func recordPick(jevGuess: String?, picked: String) -> Bool {
        guard let jevGuess else { return false }
        guard jevGuess.caseInsensitiveCompare(picked) == .orderedSame else {
            streak = 0
            return false
        }
        streak += 1
        return !decidesConfidentLinks && streak % Self.streakForOffer == 0
    }
}

/// "Send all of acme.com to Work?": offered when three or more single-host rules under one domain
/// all send their host to the same destination, and nothing else on that domain says otherwise.
public enum DomainRuleSuggestion {
    public static let minimumHosts = 3

    public struct Suggestion: Equatable, Sendable {
        public let domain: String
        public let destination: Destination

        public var dismissalKey: String { "\(domain)→\(destination.id)" }
        public var key: RuleKey { RuleKey(host: domain, hostMatch: .domain) }
    }

    public static func suggest(rules: [Rule], dismissed: Set<String>) -> Suggestion? {
        let live = rules.filter { !$0.deleted }
        // Every URL rule, grouped by the domain it falls under.
        let byDomain = Dictionary(grouping: live.filter { !$0.key.isAppRule }) {
            PublicSuffix.registrableDomain(for: $0.host)
        }
        for (domain, domainRules) in byDomain.sorted(by: { $0.key < $1.key }) {
            // Already covered by a domain-wide rule, or rules on it disagree: nothing to offer.
            guard !domainRules.contains(where: { $0.hostMatch == .domain && $0.host == domain }) else { continue }
            let destinations = Set(domainRules.map(\.destination))
            guard destinations.count == 1, let destination = destinations.first else { continue }

            let plainHosts = Set(domainRules
                .filter { $0.hostMatch == .exact && $0.pathPrefix == nil && $0.query == nil && $0.sourceApp == nil }
                .map(\.host))
            guard plainHosts.count >= minimumHosts else { continue }

            let suggestion = Suggestion(domain: domain, destination: destination)
            if !dismissed.contains(suggestion.dismissalKey) { return suggestion }
        }
        return nil
    }
}
