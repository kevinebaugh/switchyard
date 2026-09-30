import Foundation
import Testing
@testable import RouterCore

@Suite struct ProfileDescriberTests {
    @Test func siteKeysKeepHostsAndNameLikeSegments() {
        let visits = ProfileDescriber.siteVisits(from: [
            ("https://github.com/acme/web/pull/1", 6),
            ("https://github.com/Acme/api", 3),
            ("https://github.com/notifications", 1),
            ("https://www.nytimes.com/2026/09/30/world/story.html", 4),
            ("https://acme.slack.com/archives/C123", 5),
            ("https://app.datadoghq.com/metric/explorer", 4),
            ("https://claude.ai/admin-settings/members", 2),
            ("https://www.youtube.com/watch?v=abc", 9),
            ("https://example.com/0f3a9b2c4d5e6f708192a3b4c5d6e7f8", 7),
            ("chrome://settings", 3),
        ])
        #expect(visits["github.com"] == 10)
        #expect(visits["github.com/acme"] == 9)
        #expect(visits["nytimes.com"] == 4)
        #expect(visits["acme.slack.com"] == 5)
        #expect(visits["acme.slack.com/archives"] == nil)       // route, not a name
        #expect(visits["app.datadoghq.com/metric"] == nil)
        #expect(visits["claude.ai/admin-settings"] == nil)       // any route word disqualifies
        #expect(visits["youtube.com/watch"] == nil)
        #expect(visits["example.com/0f3a9b2c4d5e6f708192a3b4c5d6e7f8"] == nil)
        #expect(visits.keys.contains { $0.hasPrefix("chrome") } == false)
    }

    let work = ProfileSignals(name: "Work", accounts: [], siteVisits: [
        "github.com": 50, "github.com/acme": 40,
        "acme.slack.com": 30, "app.datadoghq.com": 12, "app.shortcut.com": 9, "app.shortcut.com/acme": 9,
        "mail.google.com": 50, "docs.google.com": 30, "nytimes.com": 1,
    ])
    let personal = ProfileSignals(name: "Personal", accounts: [], siteVisits: [
        "github.com": 20, "github.com/kev": 18,
        "mail.google.com": 60, "nytimes.com": 20, "bank.example": 8, "strava.com": 5,
    ])
    let sparse = ProfileSignals(name: "Test", accounts: [], siteVisits: ["example.com": 2, "shop.example": 4])

    @Test func distinctiveHostsWinSharedHostsFallBackToWorkspaces() {
        let all = [work, personal, sparse]
        #expect(ProfileDescriber.distinctiveSites(for: work, among: all)
            == ["github.com/acme", "acme.slack.com", "app.datadoghq.com", "app.shortcut.com"])
        #expect(ProfileDescriber.distinctiveSites(for: personal, among: all)
            == ["nytimes.com", "github.com/kev", "bank.example", "strava.com"])
    }

    @Test func accountDecidedHostsAreNeverListed() {
        let all = [work, personal, sparse]
        let listed = ProfileDescriber.distinctiveSites(for: work, among: all) + ProfileDescriber.distinctiveSites(for: personal, among: all)
        #expect(!listed.contains { $0.contains("google.com") })
    }

    @Test func describesProfilesWithEnoughEvidence() {
        let all = [work, personal, sparse]
        #expect(ProfileDescriber.describe(work, among: all, isFallback: false) ==
            "Sites used mostly in this profile: github.com/acme, acme.slack.com, app.datadoghq.com, app.shortcut.com.")
        #expect(ProfileDescriber.describe(personal, among: all, isFallback: true) ==
            "Sites used mostly in this profile: nytimes.com, github.com/kev, bank.example, strava.com. Also the default for anything that doesn't clearly belong to another profile.")
    }

    @Test func thinEvidenceStaysBlank() {
        // One qualifying site (example.com has too few visits) is a guess, not a description.
        let all = [work, personal, sparse]
        #expect(ProfileDescriber.distinctiveSites(for: sparse, among: all) == ["shop.example"])
        #expect(ProfileDescriber.describe(sparse, among: all, isFallback: false) == nil)
        #expect(ProfileDescriber.describe(sparse, among: all, isFallback: true) == nil)
        let empty = ProfileSignals(name: "Empty", accounts: [], siteVisits: [:])
        #expect(ProfileDescriber.describe(empty, among: [empty], isFallback: false) == nil)
    }

    @Test func anAccountIsEnoughOnItsOwn() {
        let profile = ProfileSignals(name: "X", accounts: [
            ProfileAccount(email: "a@x.com", workspaceDomain: nil),
            ProfileAccount(email: "b@y.com", workspaceDomain: "y.com"),
            ProfileAccount(email: "c@z.com", workspaceDomain: "NO_HOSTED_DOMAIN"),
        ], siteVisits: ["one.example": 5])
        #expect(ProfileDescriber.describe(profile, among: [profile], isFallback: false) ==
            "Signed in to Google as a@x.com, b@y.com (y.com Google Workspace), and c@z.com. Sites used mostly in this profile: one.example.")
    }

    @Test func singleProfileKeepsAllItsSites() {
        let only = ProfileSignals(name: "Solo", accounts: [], siteVisits: ["a.com": 5, "b.com": 4, "c.com": 3, "d.com": 1])
        #expect(ProfileDescriber.distinctiveSites(for: only, among: [only]) == ["a.com", "b.com", "c.com"])
    }
}
