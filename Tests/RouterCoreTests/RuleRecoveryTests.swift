import Foundation
import Testing
@testable import RouterCore

@Suite struct RuleRecoveryTests {
    let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    func record(_ url: String, _ decision: Decision, profile: String = "Work", at offset: TimeInterval = 0,
                source: SourceApp? = nil, learned: UUID? = nil, correctedTo: String? = nil) -> RoutingRecord {
        RoutingRecord(url: URL(string: url)!, date: t0 + offset, profileName: profile, decision: decision,
                      latencyMilliseconds: 1, sourceApp: source, learnedRuleID: learned, correctedTo: correctedTo)
    }

    @Test func rebuildsRulesTheHistoryPinsDown() {
        let byLabel = UUID(), appRule = UUID(), learned = UUID(), kept = UUID()
        let records = [
            // Decided by a path rule; the label picks the key among the URL's options.
            record("https://github.com/Acme/web/pull/1", .rule(id: byLabel, label: "github.com/acme"), at: 30),
            // Decided by an app rule.
            record("https://example.com/x", .rule(id: appRule, label: "links from Slack"), at: 20, source: slack),
            // Jev learned a rule at a scope.
            record("https://app.shortcut.com/acme/story/1", .jev(confidence: 0.9, scope: .firstPathSegment), at: 10, learned: learned),
            // A rule that still exists isn't touched.
            record("https://kept.example/", .rule(id: kept, label: "all of kept.example"), at: 5),
        ]
        let rules = RuleRecovery.rebuild(from: records, existing: [kept], browser: .dia)
        #expect(Set(rules.map(\.id)) == [byLabel, appRule, learned])

        let rule = rules.first { $0.id == byLabel }!
        #expect(rule.key == RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(rule.profileName == "Work")
        #expect(rule.updatedAt == t0 + 30)
        #expect(rules.first { $0.id == appRule }!.key == .app(slack))
        #expect(rules.first { $0.id == appRule }!.origin == .manual)
        #expect(rules.first { $0.id == learned }!.key == RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(rules.first { $0.id == learned }!.origin == .learned)
    }

    @Test func leavesAmbiguousOrUnknownRulesAlone() {
        let unknownLabel = UUID(), correctedOnly = UUID()
        let records = [
            record("https://example.com/a", .rule(id: unknownLabel, label: "something.else/entirely")),
            // A correction's chosen scope isn't recorded on the row, so it can't be rebuilt.
            record("https://example.com/b", .jev(confidence: 0.9, scope: .domain), learned: correctedOnly, correctedTo: "Personal"),
        ]
        #expect(RuleRecovery.rebuild(from: records, existing: [], browser: .dia).isEmpty)
    }
}
