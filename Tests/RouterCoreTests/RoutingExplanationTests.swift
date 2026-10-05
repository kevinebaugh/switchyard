import Foundation
import Testing
@testable import RouterCore

@Suite struct RoutingExplanationTests {
    let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    func record(_ decision: Decision, learned: UUID? = nil, correctedTo: String? = nil) -> RoutingRecord {
        RoutingRecord(url: URL(string: "https://github.com/acme/web")!, profileName: "Work", decision: decision,
                      latencyMilliseconds: 1, learnedRuleID: learned, correctedTo: correctedTo)
    }

    @Test func rulesSayWhoseRuleAndWhichOne() {
        let yours = Rule(key: .app(slack), profileName: "Work", origin: .corrected)
        let learned = Rule(key: RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme"), profileName: "Work", origin: .learned)
        let rules = [yours.id: yours, learned.id: learned]

        #expect(RoutingExplanation.explain(record(.rule(id: yours.id, label: "x")), rule: { rules[$0] }).text
            == "Your rule: links from Slack")
        #expect(RoutingExplanation.explain(record(.rule(id: learned.id, label: "x")), rule: { rules[$0] }).text
            == "Learned rule: github.com/acme")
        #expect(RoutingExplanation.explain(record(.rule(id: UUID(), label: "old.example")), rule: { rules[$0] }).text
            == "Rule: old.example (since removed)")
    }

    @Test func jevSaysWhatItLearned() {
        let learned = Rule(key: RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme"), profileName: "Work", origin: .learned)
        let line = RoutingExplanation.explain(record(.jev(confidence: 0.84, scope: .firstPathSegment), learned: learned.id),
                                              rule: { $0 == learned.id ? learned : nil })
        #expect(line == .init(text: "Jev 0.84 · learned github.com/acme", needsAttention: false))
        #expect(RoutingExplanation.explain(record(.jev(confidence: 0.96, scope: LinkScope.none)), rule: { _ in nil }).text
            == "Jev 0.96 · nothing saved (too specific)")
    }

    @Test func unsureAndFallbackAskForAttentionUntilConfirmed() {
        #expect(RoutingExplanation.explain(record(.lowConfidence(confidence: 0.47)), rule: { _ in nil })
            == .init(text: "Jev unsure (0.47) · nothing saved", needsAttention: true))
        #expect(RoutingExplanation.explain(record(.fallback(.rateLimited)), rule: { _ in nil })
            == .init(text: "Fallback: Jev rate-limited", needsAttention: true))

        let confirmed = Rule(key: RuleKey(host: "game.example", hostMatch: .domain), profileName: "Work", origin: .corrected)
        let line = RoutingExplanation.explain(record(.lowConfidence(confidence: 0.47), learned: confirmed.id),
                                              rule: { $0 == confirmed.id ? confirmed : nil })
        #expect(line == .init(text: "Jev unsure (0.47) · you saved all of game.example", needsAttention: false))
    }

    @Test func correctionsSayWhatYouDid() {
        let saved = Rule(key: RuleKey(host: "shop.example", hostMatch: .domain), profileName: "Personal", origin: .corrected)
        #expect(RoutingExplanation.explain(record(.rule(id: UUID(), label: "x"), learned: saved.id, correctedTo: "Personal"),
                                           rule: { $0 == saved.id ? saved : nil }).text
            == "You moved it to Personal · saved all of shop.example")
        #expect(RoutingExplanation.explain(record(.jev(confidence: 0.9, scope: nil), correctedTo: "Personal"), rule: { _ in nil }).text
            == "You re-opened it in Personal")
    }
}
