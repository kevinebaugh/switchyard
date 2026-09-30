import Foundation
import Testing
@testable import RouterCore

@Suite struct RuleListingTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let day: TimeInterval = 86_400

    func rule(_ host: String, _ profile: String, origin: RuleOrigin = .learned, age: TimeInterval = 0) -> Rule {
        Rule(key: RuleKey(host: host, hostMatch: .domain), profileName: profile, origin: origin,
             updatedAt: now.addingTimeInterval(-age))
    }

    @Test func mostRecentlyUsedFirstThenUnusedThenStale() {
        let hot = rule("hot.com", "Work", age: 200 * day)
        let warm = rule("warm.com", "Work", age: 200 * day)
        let fresh = rule("fresh.com", "Personal", age: 1 * day)          // never used, but new
        let stale = rule("stale.com", "Personal", age: 10 * day)          // used long ago
        let old = rule("old.com", "Personal", age: 120 * day)             // never used, old
        let usage: [UUID: RuleUsage] = [
            hot.id: RuleUsage(lastUsed: now.addingTimeInterval(-60), count: 14),
            warm.id: RuleUsage(lastUsed: now.addingTimeInterval(-3 * day), count: 2),
            stale.id: RuleUsage(lastUsed: now.addingTimeInterval(-100 * day), count: 9),
        ]
        let rows = RuleListing.arrange(rules: [old, stale, fresh, warm, hot], usage: usage, query: "", profile: nil, now: now)
        #expect(rows.map(\.rule.host) == ["hot.com", "warm.com", "fresh.com", "stale.com", "old.com"])
        #expect(rows.map(\.isStale) == [false, false, false, true, true])
    }

    @Test func filtersByTextAndProfile() {
        let rules = [rule("github.com", "Work"), rule("gitlab.com", "Personal"), rule("slack.com", "Work"),
                     Rule(key: .app(SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")), profileName: "Work", origin: .manual)]
        #expect(RuleListing.arrange(rules: rules, usage: [:], query: "git", profile: nil, now: now).count == 2)
        #expect(RuleListing.arrange(rules: rules, usage: [:], query: "git", profile: "work", now: now).map(\.rule.host) == ["github.com"])
        #expect(RuleListing.arrange(rules: rules, usage: [:], query: "slack", profile: nil, now: now).count == 2)
        #expect(RuleListing.arrange(rules: rules, usage: [:], query: "from slack", profile: nil, now: now).map(\.rule.key.isAppRule) == [true])
        #expect(RuleListing.arrange(rules: rules, usage: [:], query: "personal", profile: nil, now: now).map(\.rule.host) == ["gitlab.com"])
    }

    @Test func deletedRulesAreHidden() {
        var gone = rule("gone.com", "Work")
        gone.deleted = true
        #expect(RuleListing.arrange(rules: [gone], usage: [:], query: "", profile: nil, now: now).isEmpty)
    }

    @Test func addCandidates() {
        let existing = [rule("slack.com", "Work")]
        #expect(RuleListing.addCandidate(for: "slack.com", existing: existing) == nil)
        #expect(RuleListing.addCandidate(for: "nytimes.com", existing: existing) == RuleKey(host: "nytimes.com", hostMatch: .domain))
        #expect(RuleListing.addCandidate(for: "acme.slack.com", existing: existing) == RuleKey(host: "acme.slack.com", hostMatch: .exact))
        #expect(RuleListing.addCandidate(for: "*.acme.dev", existing: existing) == RuleKey(host: "acme.dev", hostMatch: .domain))
        #expect(RuleListing.addCandidate(for: "app.shortcut.com/acme", existing: existing)
            == RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(RuleListing.addCandidate(for: "git", existing: existing) == nil)
        #expect(RuleListing.addCandidate(for: "from slack", existing: existing) == nil)
    }
}
