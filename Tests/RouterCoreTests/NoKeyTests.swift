import Foundation
import Testing
@testable import RouterCore

@Suite struct NoKeyTests {
    let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    func record(_ decision: Decision, profile: String = "Work", at offset: TimeInterval = 0,
                source: SourceApp? = nil, learned: UUID? = nil) -> RoutingRecord {
        RoutingRecord(url: URL(string: "https://example.com/a")!, date: t0 + offset, profileName: profile, decision: decision,
                      latencyMilliseconds: 0.3, sourceApp: source, learnedRuleID: learned)
    }

    @Test func havingNoKeyIsntAProblem() {
        #expect(!FallbackReason.noAPIKey.isSetupProblem)
        #expect(FallbackReason.unauthorized.isSetupProblem)
        #expect(!Decision.fallback(.noAPIKey).needsAttention)
        #expect(Decision.fallback(.timeout).needsAttention)
        #expect(!Decision.asked(remembered: true).needsAttention)
        #expect(Decision.asked(remembered: false).badge == "asked")
    }

    @Test func pickedLinksExplainThemselvesQuietly() {
        let saved = Rule(key: RuleKey(host: "example.com", hostMatch: .domain), profileName: "Work", origin: .corrected)
        let rules = [saved.id: saved]
        #expect(RoutingExplanation.explain(record(.asked(remembered: true), learned: saved.id), rule: { rules[$0] })
            == .init(text: "You picked it · saved all of example.com", needsAttention: false))
        #expect(RoutingExplanation.explain(record(.asked(remembered: false)), rule: { _ in nil })
            == .init(text: "You picked it", needsAttention: false))
        #expect(RoutingExplanation.explain(record(.fallback(.noAPIKey)), rule: { _ in nil })
            == .init(text: "No rule yet · opened in your default profile", needsAttention: false))
    }

    @Test func aRejectedKeyIsFlaggedButDoesntBadgeEveryLink() {
        let line = RoutingExplanation.explain(record(.fallback(.unauthorized)), rule: { _ in nil })
        #expect(line.needsAttention)
        #expect(!line.badges)
    }

    @Test func picksCountTowardAppRuleSuggestions() {
        let picks = (0..<AppRuleSuggestion.streak).map {
            record(.asked(remembered: false), profile: "Work", at: Double($0), source: slack)
        }
        let suggestion = AppRuleSuggestion.suggest(records: picks.reversed(), hasAppRule: { _ in false }, dismissed: [])
        #expect(suggestion?.source == slack)
        #expect(suggestion?.profileName == "Work")

        let escapes = (0..<AppRuleSuggestion.streak).map {
            record(.fallback(.noAPIKey), profile: "Personal", at: Double($0), source: slack)
        }
        #expect(AppRuleSuggestion.suggest(records: escapes, hasAppRule: { _ in false }, dismissed: []) == nil)
    }
}
