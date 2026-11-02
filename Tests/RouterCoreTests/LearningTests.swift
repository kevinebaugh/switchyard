import Foundation
import Testing
@testable import RouterCore

@Suite struct JevTrustTests {
    @Test func tenAgreementsInARowEarnAnOffer() {
        var trust = JevTrust(decidesConfidentLinks: false)
        var offers: [Int] = []
        for pick in 1...25 {
            if trust.recordPick(jevGuess: "Work", picked: "work") { offers.append(pick) }
        }
        #expect(offers == [10, 20])   // "Not now" just waits for the next ten
    }

    @Test func aDisagreementStartsOver() {
        var trust = JevTrust(decidesConfidentLinks: false)
        for _ in 1...9 { _ = trust.recordPick(jevGuess: "Work", picked: "Work") }
        _ = trust.recordPick(jevGuess: "Work", picked: "Personal")
        #expect(trust.streak == 0)
        // Picks where Jev wasn't confident (or wasn't asked) don't count either way.
        _ = trust.recordPick(jevGuess: nil, picked: "Personal")
        #expect(trust.streak == 0)
    }

    @Test func noOfferOnceTrusted() {
        var trust = JevTrust(decidesConfidentLinks: true)
        var offered = false
        for _ in 1...10 { offered = trust.recordPick(jevGuess: "Work", picked: "Work") || offered }
        #expect(!offered)
    }
}

@Suite struct DomainRuleSuggestionTests {
    let work = Destination(browser: .safari, profile: "Safari")

    func exact(_ host: String, _ destination: Destination) -> Rule {
        Rule(key: RuleKey(host: host, hostMatch: .exact), profileName: destination.profile, origin: .corrected, browser: destination.browser)
    }

    @Test func threeHostsToOneDestinationSuggestTheDomain() {
        let rules = ["wiki.acme.com", "jira.acme.com", "build.acme.com"].map { exact($0, work) }
        let suggestion = DomainRuleSuggestion.suggest(rules: rules, dismissed: [])
        #expect(suggestion?.domain == "acme.com")
        #expect(suggestion?.destination == work)
        #expect(suggestion?.key == RuleKey(host: "acme.com", hostMatch: .domain))
        #expect(DomainRuleSuggestion.suggest(rules: rules, dismissed: [suggestion!.dismissalKey]) == nil)
    }

    @Test func noSuggestionWhenRulesDisagreeOrTheDomainIsCovered() {
        let personal = Destination(browser: .firefox, profile: "Personal")
        let mixed = ["a.acme.com", "b.acme.com", "c.acme.com"].map { exact($0, work) } + [exact("d.acme.com", personal)]
        #expect(DomainRuleSuggestion.suggest(rules: mixed, dismissed: []) == nil)

        let covered = ["a.acme.com", "b.acme.com", "c.acme.com"].map { exact($0, work) }
            + [Rule(key: RuleKey(host: "acme.com", hostMatch: .domain), profileName: "Safari", origin: .corrected, browser: .safari)]
        #expect(DomainRuleSuggestion.suggest(rules: covered, dismissed: []) == nil)

        let two = ["a.acme.com", "b.acme.com"].map { exact($0, work) }
        #expect(DomainRuleSuggestion.suggest(rules: two, dismissed: []) == nil)
    }
}
