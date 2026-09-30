import Foundation
import Testing
@testable import RouterCore

private func rule(_ key: RuleKey, _ profile: String) -> Rule {
    Rule(key: key, profileName: profile, origin: .manual)
}

private func url(_ string: String) -> URL {
    URL(string: string)!
}

@Suite struct RuleIndexTests {
    let index = RuleIndex(rules: [
        rule(RuleKey(host: "shortcut.com", hostMatch: .domain), "Personal"),
        rule(RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"), "Work"),
        rule(RuleKey(host: "slack.com", hostMatch: .domain), "Personal"),
        rule(RuleKey(host: "acme.slack.com", hostMatch: .exact), "Work"),
        rule(RuleKey(host: "mail.google.com", hostMatch: .exact), "Personal"),
        rule(RuleKey(host: "mail.google.com", hostMatch: .exact, query: ["authuser": "tester@example.com"]), "Test"),
        rule(RuleKey(host: "github.com", hostMatch: .domain, pathPrefix: "/Acme"), "Work"),
    ])

    @Test func pathPrefixBeatsDomain() {
        #expect(index.match(url("https://app.shortcut.com/acme/story/123"))?.profileName == "Work")
        #expect(index.match(url("https://app.shortcut.com/personal-project/story/1"))?.profileName == "Personal")
    }

    @Test func pathPrefixRespectsSegmentBoundaries() {
        #expect(index.match(url("https://app.shortcut.com/acmex"))?.profileName == "Personal")
        #expect(index.match(url("https://app.shortcut.com/acme"))?.profileName == "Work")
        #expect(index.match(url("https://app.shortcut.com/Acme/"))?.profileName == "Work")
    }

    @Test func exactSubdomainBeatsParentDomain() {
        #expect(index.match(url("https://acme.slack.com/archives/C1"))?.profileName == "Work")
        #expect(index.match(url("https://other.slack.com/archives/C1"))?.profileName == "Personal")
        #expect(index.match(url("https://slack.com/"))?.profileName == "Personal")
    }

    @Test func exactRuleDoesNotCoverSubdomains() {
        let index = RuleIndex(rules: [rule(RuleKey(host: "acme.slack.com", hostMatch: .exact), "Work")])
        #expect(index.match(url("https://x.acme.slack.com")) == nil)
    }

    @Test func queryIdentifierBeatsHost() {
        #expect(index.match(url("https://mail.google.com/mail/?authuser=Tester@Example.com"))?.profileName == "Test")
        #expect(index.match(url("https://mail.google.com/mail/?authuser=you@acme.com"))?.profileName == "Personal")
    }

    @Test func domainRuleWithPath() {
        #expect(index.match(url("https://github.com/Acme/web/pull/1"))?.profileName == "Work")
        #expect(index.match(url("https://github.com/kev/dotfiles")) == nil)
    }

    @Test func noMatchReturnsNil() {
        #expect(index.match(url("https://nytimes.com")) == nil)
    }

    @Test func deletedAndUnavailableRulesAreSkipped() {
        var deleted = rule(RuleKey(host: "a.com", hostMatch: .domain), "Work")
        deleted.deleted = true
        let index = RuleIndex(rules: [deleted, rule(RuleKey(host: "b.com", hostMatch: .domain), "Gone")])
        #expect(index.match(url("https://a.com")) == nil)
        #expect(index.match(url("https://b.com"), availableProfiles: ["personal", "work"]) == nil)
        #expect(index.match(url("https://b.com"), availableProfiles: ["gone"])?.profileName == "Gone")
    }

    @Test func hostNormalization() {
        #expect(index.match(url("https://ACME.Slack.COM./x"))?.profileName == "Work")
    }
}

@Suite struct PublicSuffixTests {
    @Test func registrableDomains() {
        #expect(PublicSuffix.registrableDomain(for: "docs.google.com") == "google.com")
        #expect(PublicSuffix.registrableDomain(for: "google.com") == "google.com")
        #expect(PublicSuffix.registrableDomain(for: "news.bbc.co.uk") == "bbc.co.uk")
        #expect(PublicSuffix.registrableDomain(for: "kev.github.io") == "kev.github.io")
        #expect(PublicSuffix.registrableDomain(for: "a.b.kev.github.io") == "kev.github.io")
        #expect(PublicSuffix.registrableDomain(for: "127.0.0.1") == "127.0.0.1")
        #expect(PublicSuffix.registrableDomain(for: "localhost") == "localhost")
    }
}
