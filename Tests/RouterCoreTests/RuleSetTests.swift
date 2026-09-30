import Foundation
import Testing
@testable import RouterCore

@Suite struct RuleSetTests {
    let key = RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func upsertReplacesSameKey() {
        var set = RuleSet()
        let learned = set.upsert(key: key, profileName: "Personal", origin: .learned, now: t0)
        let corrected = set.upsert(key: RuleKey(host: "APP.shortcut.com", hostMatch: .exact, pathPrefix: "/Acme/"),
                                   profileName: "Work", origin: .corrected, now: t0 + 1)
        #expect(set.liveRules.count == 1)
        #expect(corrected.id == learned.id)
        #expect(set.rule(for: key)?.profileName == "Work")
        #expect(set.rule(for: key)?.origin == .corrected)
    }

    @Test func mergeKeepsNewerEdit() {
        var ours = RuleSet()
        let rule = ours.upsert(key: key, profileName: "Personal", origin: .learned, now: t0)
        var theirs = ours
        theirs.upsert(key: key, profileName: "Work", origin: .corrected, now: t0 + 10)

        #expect(RuleSet.merge(ours, theirs, now: t0 + 20).rule(for: key)?.profileName == "Work")
        #expect(RuleSet.merge(theirs, ours, now: t0 + 20).rule(for: key)?.profileName == "Work")
        #expect(RuleSet.merge(ours, theirs, now: t0 + 20).rules.map(\.id) == [rule.id])
    }

    @Test func tombstoneBeatsOlderLiveCopy() {
        var ours = RuleSet()
        let rule = ours.upsert(key: key, profileName: "Work", origin: .learned, now: t0)
        var theirs = ours
        theirs.delete(id: rule.id, now: t0 + 5)

        let merged = RuleSet.merge(ours, theirs, now: t0 + 10)
        #expect(merged.liveRules.isEmpty)
        #expect(merged.rules.count == 1)
    }

    @Test func oldTombstonesArePruned() {
        var set = RuleSet()
        let rule = set.upsert(key: key, profileName: "Work", origin: .learned, now: t0)
        set.delete(id: rule.id, now: t0)
        let merged = RuleSet.merge(set, RuleSet(), now: t0 + RuleSet.tombstoneLifetime + 1)
        #expect(merged.rules.isEmpty)
    }

    @Test func duplicateKeysFromTwoMacsCollapseToNewest() {
        var macA = RuleSet()
        macA.upsert(key: key, profileName: "Personal", origin: .learned, now: t0)
        var macB = RuleSet()
        macB.upsert(key: key, profileName: "Work", origin: .learned, now: t0 + 3)

        let merged = RuleSet.merge(macA, macB, now: t0 + 10)
        #expect(merged.liveRules.count == 1)
        #expect(merged.rule(for: key)?.profileName == "Work")
    }

    @Test func renameFollowsDia() {
        var set = RuleSet()
        set.upsert(key: key, profileName: "Work", origin: .learned, now: t0)
        set.upsert(key: RuleKey(host: "nytimes.com", hostMatch: .domain), profileName: "Personal", origin: .learned, now: t0)
        set.renameProfile(from: "work", to: "Job", now: t0 + 1)
        #expect(set.rule(for: key)?.profileName == "Job")
        #expect(set.rule(for: RuleKey(host: "nytimes.com", hostMatch: .domain))?.profileName == "Personal")
    }

    @Test func roundTripsThroughJSON() throws {
        var set = RuleSet()
        set.upsert(key: RuleKey(host: "mail.google.com", hostMatch: .exact, query: ["authuser": "tester@example.com"]),
                   profileName: "Test", origin: .corrected, now: t0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RuleSet.self, from: encoder.encode(set))
        #expect(decoded == set)
    }
}

@Suite struct ChromiumLocalStateTests {
    let json = """
    {"profile": {
      "info_cache": {
        "Profile 4": {"name": "Work", "active_time": 3, "profile_color_seed": -16730235,
                      "user_name": "you@acme.com", "hosted_domain": "acme.com"},
        "Profile 2": {"name": "Personal", "user_name": "", "hosted_domain": "NO_HOSTED_DOMAIN"},
        "Profile 3": {"name": "Test"}
      },
      "profiles_order": ["Profile 2", "Profile 3", "Profile 4"],
      "last_used": "Profile 4"
    }}
    """

    @Test func parsesProfilesInDiaOrder() {
        let profiles = ChromiumLocalState.profiles(from: Data(json.utf8))
        #expect(profiles.map(\.name) == ["Personal", "Test", "Work"])
        #expect(profiles.map(\.directory) == ["Profile 2", "Profile 3", "Profile 4"])
    }

    @Test func readsColorAndAccount() {
        let profiles = ChromiumLocalState.profiles(from: Data(json.utf8))
        let work = profiles.first { $0.name == "Work" }
        #expect(work?.colorARGB == 0xFF00B785)
        #expect(work?.account == ProfileAccount(email: "you@acme.com", workspaceDomain: "acme.com"))
        #expect(profiles.first { $0.name == "Personal" }?.account == nil)
    }

    @Test func sortsByDiaVisibleOrder() {
        let profiles = ChromiumLocalState.profiles(from: Data(json.utf8))
        #expect(ChromiumLocalState.sorted(profiles, visibleOrder: ["Personal", "Work", "Test"]).map(\.name) == ["Personal", "Work", "Test"])
        #expect(ChromiumLocalState.sorted(profiles, visibleOrder: ["work"]).map(\.name) == ["Work", "Personal", "Test"])
        #expect(ChromiumLocalState.sorted(profiles, visibleOrder: []).map(\.name) == ["Personal", "Test", "Work"])
    }

    @Test func detectsRenames() {
        let old = [BrowserProfile(directory: "Profile 4", name: "Work"), BrowserProfile(directory: "Profile 2", name: "Personal")]
        let new = [BrowserProfile(directory: "Profile 4", name: "Job"), BrowserProfile(directory: "Profile 2", name: "Personal")]
        let renames = ChromiumLocalState.renames(from: old, to: new)
        #expect(renames.count == 1)
        #expect(renames.first?.from == "Work")
        #expect(renames.first?.to == "Job")
    }

    @Test func garbageYieldsNoProfiles() {
        #expect(ChromiumLocalState.profiles(from: Data("nope".utf8)).isEmpty)
    }
}

@Suite struct RuleKeyParseTests {
    @Test func parsesHandTypedRules() {
        #expect(RuleKey.parse("app.shortcut.com/acme/", includeSubdomains: false)
            == RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(RuleKey.parse("*.slack.com", includeSubdomains: false) == RuleKey(host: "slack.com", hostMatch: .domain))
        #expect(RuleKey.parse("https://Slack.com", includeSubdomains: true) == RuleKey(host: "slack.com", hostMatch: .domain))
        #expect(RuleKey.parse("mail.google.com?authuser=tester%40example.com", includeSubdomains: false)
            == RuleKey(host: "mail.google.com", hostMatch: .exact, query: ["authuser": "tester@example.com"]))
        #expect(RuleKey.parse("not a host", includeSubdomains: true) == nil)
        #expect(RuleKey.parse("", includeSubdomains: true) == nil)
    }
}
