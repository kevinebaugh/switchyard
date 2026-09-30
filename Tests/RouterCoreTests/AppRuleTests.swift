import Foundation
import Testing
@testable import RouterCore

private let slack = SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
private let mail = SourceApp(bundleID: "com.apple.mail", name: "Mail")

private func url(_ string: String) -> URL {
    URL(string: string)!
}

@Suite struct AppRulePrecedenceTests {
    let index = RuleIndex(rules: [
        Rule(key: .app(slack), profileName: "Work", origin: .corrected),
        Rule(key: RuleKey(host: "nytimes.com", hostMatch: .domain), profileName: "Personal", origin: .learned),
        Rule(key: RuleKey(host: "bank.com", hostMatch: .domain), profileName: "Personal", origin: .manual),
        Rule(key: RuleKey(host: "shop.example.com", hostMatch: .domain, pathPrefix: "/explore"), profileName: "Test", origin: .corrected),
    ])

    @Test func appRuleBeatsLearnedURLRule() {
        #expect(index.match(url("https://nytimes.com/a"), from: slack.bundleID)?.profileName == "Work")
        #expect(index.match(url("https://nytimes.com/a"), from: mail.bundleID)?.profileName == "Personal")
        #expect(index.match(url("https://nytimes.com/a"))?.profileName == "Personal")
    }

    @Test func yourURLRulesBeatAppRule() {
        #expect(index.match(url("https://bank.com"), from: slack.bundleID)?.profileName == "Personal")
        #expect(index.match(url("https://shop.example.com/explore/x"), from: slack.bundleID)?.profileName == "Test")
    }

    @Test func appRuleCoversUnknownURLs() {
        #expect(index.match(url("https://example.org"), from: slack.bundleID)?.key.isAppRule == true)
        #expect(index.match(url("https://example.org"), from: mail.bundleID) == nil)
        #expect(index.match(url("https://example.org")) == nil)
    }

    @Test func bundleIDMatchingIsCaseInsensitive() {
        #expect(index.match(url("https://example.org"), from: "COM.tinyspeck.SlackMacGap")?.profileName == "Work")
    }

    @Test func appRuleForMissingProfileIsSkipped() {
        #expect(index.match(url("https://example.org"), from: slack.bundleID, availableProfiles: ["personal"]) == nil)
    }

    @Test func appRuleLabelAndKeyIdentity() {
        #expect(RuleKey.app(slack).label == "links from Slack")
        #expect(RuleKey.app(slack) == RuleKey.app(SourceApp(bundleID: "COM.TINYSPECK.SLACKMACGAP", name: "Slack (old name)")))
        var set = RuleSet()
        set.upsert(key: .app(slack), profileName: "Personal", origin: .corrected)
        set.upsert(key: .app(slack), profileName: "Work", origin: .corrected)
        #expect(set.liveRules.count == 1)
        #expect(set.rule(for: .app(slack))?.profileName == "Work")
    }

    @Test func rulesWithoutSourceAppStillDecode() throws {
        let json = """
        {"version":1,"rules":[{"id":"\(UUID().uuidString)","host":"slack.com","hostMatch":"domain",
          "profileName":"Work","origin":"learned","updatedAt":"2026-09-30T16:00:00Z","deleted":false}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(RuleSet.self, from: Data(json.utf8))
        #expect(set.rules.first?.sourceApp == nil)
        #expect(set.rules.first?.key == RuleKey(host: "slack.com", hostMatch: .domain))
    }
}

@Suite struct AppRuleSuggestionTests {
    func record(_ profile: String, from source: SourceApp?, decision: Decision = .jev(confidence: 0.9, scope: .domain),
                correctedTo: String? = nil) -> RoutingRecord {
        RoutingRecord(url: url("https://example.com"), profileName: profile, decision: decision,
                      latencyMilliseconds: 1, sourceApp: source, correctedTo: correctedTo)
    }

    @Test func threeInARowSuggests() {
        let records = [record("Work", from: slack), record("Work", from: slack), record("Personal", from: mail),
                       record("Work", from: slack)]
        let suggestion = AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: [])
        #expect(suggestion == AppRuleSuggestion.Suggestion(source: slack, profileName: "Work"))
    }

    @Test func correctionsCountAsTheirFinalProfile() {
        let records = [record("Personal", from: slack, correctedTo: "Work"), record("Work", from: slack),
                       record("Work", from: slack, decision: .lowConfidence(confidence: 0.6))]
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: [])?.profileName == "Work")
    }

    @Test func mixedProfilesDoNotSuggest() {
        let records = [record("Work", from: slack), record("Personal", from: slack), record("Work", from: slack)]
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: []) == nil)
    }

    @Test func fallbacksAndExplicitOpensAreIgnored() {
        let records = [record("Personal", from: slack, decision: .fallback(.timeout)), record("Work", from: slack),
                       record("Personal", from: slack, decision: .explicit), record("Work", from: slack)]
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: []) == nil)
        let more = [record("Work", from: slack)] + records
        #expect(AppRuleSuggestion.suggest(records: more, hasAppRule: { _ in false }, dismissed: [])?.profileName == "Work")
    }

    @Test func existingRuleOrDismissalSuppresses() {
        let records = Array(repeating: record("Work", from: slack), count: 3)
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { $0 == slack.bundleID }, dismissed: []) == nil)
        let key = AppRuleSuggestion.dismissalKey(bundleID: slack.bundleID, profileName: "Work")
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: [key]) == nil)
    }

    @Test func recordsWithoutSourceNeverSuggest() {
        let records = Array(repeating: record("Work", from: nil), count: 5)
        #expect(AppRuleSuggestion.suggest(records: records, hasAppRule: { _ in false }, dismissed: []) == nil)
    }
}
