import Foundation

/// One entry in the menu's recent routings. Stays on this Mac (it holds full URLs).
public struct RoutingRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var url: URL
    public var date: Date
    public var profileName: String
    public var decision: Decision
    public var latencyMilliseconds: Double
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var learnedRuleID: UUID?
    public var correctedTo: String?
    public var openError: String?
    /// Jev's answer once it could be reached again, for a link that fell back because it couldn't.
    public var catchUp: CatchUp?

    public struct CatchUp: Codable, Hashable, Sendable {
        public var profileName: String
        public var confidence: Double
        /// Confident enough to act on (the profile threshold at the time).
        public var isConfident: Bool
        public var scope: LinkScope?
        public var date: Date

        public init(profileName: String, confidence: Double, isConfident: Bool, scope: LinkScope?, date: Date = Date()) {
            self.profileName = profileName
            self.confidence = confidence
            self.isConfident = isConfident
            self.scope = scope
            self.date = date
        }

        /// Jev is sure the link belonged in another profile than `openedIn`.
        public func suggestsMove(from openedIn: String) -> Bool {
            isConfident && profileName.caseInsensitiveCompare(openedIn) != .orderedSame
        }
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        date: Date = Date(),
        profileName: String,
        decision: Decision,
        latencyMilliseconds: Double,
        sourceApp: SourceApp? = nil,
        learnedRuleID: UUID? = nil,
        correctedTo: String? = nil,
        openError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.date = date
        self.profileName = profileName
        self.decision = decision
        self.latencyMilliseconds = latencyMilliseconds
        self.sourceApp = sourceApp?.name
        self.sourceBundleID = sourceApp?.bundleID
        self.learnedRuleID = learnedRuleID
        self.correctedTo = correctedTo
        self.openError = openError
    }

    public var source: SourceApp? {
        guard let sourceBundleID else { return nil }
        return SourceApp(bundleID: sourceBundleID, name: sourceApp ?? sourceBundleID)
    }

    /// Fell back because Jev couldn't be reached, and Jev hasn't been asked since.
    public var isAwaitingCatchUp: Bool {
        guard case let .fallback(reason) = decision, reason.isNetworkFailure else { return false }
        return catchUp == nil && correctedTo == nil && learnedRuleID == nil
    }

    /// Where the link ended up after any correction.
    public var finalProfileName: String {
        correctedTo ?? profileName
    }

    public var latencyLabel: String {
        latencyMilliseconds < 10
            ? String(format: "%.1f ms", latencyMilliseconds)
            : String(format: "%.0f ms", latencyMilliseconds)
    }
}

public enum ProfileDefaults {
    public static let fallbackProfileName = "Personal"

    /// Starter descriptions for Jev's profile criteria, keyed by lowercased profile name,
    /// for profiles with common names. Everyone should tailor these in Settings: they're
    /// the only thing Jev knows about what each profile is for.
    public static let descriptions: [String: String] = [
        "work": """
            Work: the employer's Google Workspace or Microsoft 365 account (email, calendar, documents, meetings), \
            the company chat workspace, issue trackers, the company's code hosting organization, monitoring and analytics \
            dashboards, internal admin tools, and SaaS used for the job. Links opened from work chat apps are usually work.
            """,
        "personal": """
            Personal life: personal email and accounts, banking, shopping, news, social media, entertainment, travel, \
            hobbies and side projects. The default for anything not clearly work or testing.
            """,
        "test": """
            A test account used to try products as an ordinary new user: sign-up and onboarding flows, consumer pages, \
            and OAuth connections made with test accounts.
            """,
    ]

    public static func description(for profileName: String) -> String {
        descriptions[profileName.lowercased()] ?? ""
    }
}

/// "Your last 3 links from Slack opened in Work. Always open links from Slack there?"
public enum AppRuleSuggestion {
    public static let streak = 3

    public struct Suggestion: Equatable, Sendable {
        public let source: SourceApp
        public let profileName: String

        public var dismissalKey: String {
            AppRuleSuggestion.dismissalKey(bundleID: source.bundleID, profileName: profileName)
        }
    }

    public static func dismissalKey(bundleID: String, profileName: String) -> String {
        "\(bundleID.lowercased())→\(profileName.lowercased())"
    }

    /// - Parameters:
    ///   - records: newest first.
    ///   - hasAppRule: whether an app rule already exists for a bundle ID.
    ///   - dismissed: dismissal keys the user said "not now" to.
    public static func suggest(
        records: [RoutingRecord],
        hasAppRule: (String) -> Bool,
        dismissed: Set<String>
    ) -> Suggestion? {
        var seen = Set<String>()
        for record in records {
            guard let source = record.source, seen.insert(source.bundleID.lowercased()).inserted else { continue }
            guard !hasAppRule(source.bundleID) else { continue }

            let recent = records
                .filter { $0.source == source && counts($0) }
                .prefix(streak)
            guard recent.count == streak,
                  let profile = recent.first?.finalProfileName,
                  recent.allSatisfy({ $0.finalProfileName.caseInsensitiveCompare(profile) == .orderedSame }) else { continue }

            let suggestion = Suggestion(source: source, profileName: profile)
            if !dismissed.contains(suggestion.dismissalKey) { return suggestion }
        }
        return nil
    }

    /// Fallbacks and explicit opens say nothing about intent unless the user corrected them.
    private static func counts(_ record: RoutingRecord) -> Bool {
        if record.correctedTo != nil { return true }
        switch record.decision {
        case .fallback, .explicit: return false
        default: return true
        }
    }
}
