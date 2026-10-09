import Foundation
import Testing
@testable import RouterCore

@Suite struct BrowserRuleTests {
    let key = RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func legacyRulesAreDiaRules() throws {
        let json = """
        {"version":1,"rules":[{"id":"\(UUID().uuidString)","host":"slack.com","hostMatch":"domain",
          "profileName":"Work","origin":"learned","updatedAt":"2026-09-30T16:00:00Z","deleted":false}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let set = try decoder.decode(RuleSet.self, from: Data(json.utf8))
        #expect(set.rules.first?.browser == nil)
        #expect(set.rules.first?.effectiveBrowser == .dia)
        #expect(set.liveRules(for: .dia).count == 1)
        #expect(set.liveRules(for: .chrome).isEmpty)
    }

    @Test func eachBrowserKeepsItsOwnRuleForAKey() {
        var set = RuleSet()
        let dia = set.upsert(key: key, profileName: "Work", origin: .learned, browser: .dia, now: t0)
        let chrome = set.upsert(key: key, profileName: "Acme", origin: .learned, browser: .chrome, now: t0)
        #expect(dia.id != chrome.id)
        #expect(set.rule(for: key, browser: .dia)?.profileName == "Work")
        #expect(set.rule(for: key, browser: .chrome)?.profileName == "Acme")

        set.upsert(key: key, profileName: "Personal", origin: .corrected, browser: .chrome, now: t0 + 1)
        #expect(set.rule(for: key, browser: .chrome)?.profileName == "Personal")
        #expect(set.rule(for: key, browser: .dia)?.profileName == "Work")
        #expect(RuleSet.merge(set, RuleSet(), now: t0 + 2).liveRules.count == 2)
    }

    @Test func indexOnlyUsesTheSelectedBrowsersRules() {
        let rules = [
            Rule(key: RuleKey(host: "slack.com", hostMatch: .domain), profileName: "Work", origin: .manual),
            Rule(key: RuleKey(host: "slack.com", hostMatch: .domain), profileName: "Acme", origin: .manual, browser: .chrome),
        ]
        let url = URL(string: "https://acme.slack.com/archives")!
        #expect(RuleIndex(rules: rules).match(url)?.profileName == "Work")
        #expect(RuleIndex(rules: rules, browser: .chrome).match(url)?.profileName == "Acme")
        #expect(RuleIndex(rules: rules, browser: .brave).match(url) == nil)
    }

    @Test func renameOnlyTouchesThatBrowser() {
        var set = RuleSet()
        set.upsert(key: key, profileName: "Work", origin: .learned, browser: .dia, now: t0)
        set.upsert(key: key, profileName: "Work", origin: .learned, browser: .chrome, now: t0)
        set.renameProfile(from: "Work", to: "Acme", browser: .chrome, now: t0 + 1)
        #expect(set.rule(for: key, browser: .dia)?.profileName == "Work")
        #expect(set.rule(for: key, browser: .chrome)?.profileName == "Acme")
    }
}

@Suite struct BrowserKindTests {
    @Test func eachBrowserOpensItsOwnWay() {
        #expect(BrowserKind.dia.opening == .appleScript)
        #expect(BrowserKind.firefox.opening == .firefoxProfile)
        for kind in BrowserKind.allCases where kind != .dia && kind != .firefox {
            #expect(kind.opening == .profileDirectoryFlag)
        }
        #expect(BrowserKind.allCases.filter { !$0.opensWithArguments } == [.dia])
    }

    @Test func dataFoldersAreDistinct() {
        let folders = BrowserKind.allCases.map(\.userDataPath)
        #expect(Set(folders).count == folders.count)
        #expect(BrowserKind.chrome.userDataDirectory(home: URL(fileURLWithPath: "/Users/x")).path
            == "/Users/x/Library/Application Support/Google/Chrome")
    }

    @Test func chromeProfileColorsFallBackPastUnsetValues() {
        let json = """
        {"profile": {"info_cache": {
          "Default": {"name": "Personal", "profile_highlight_color": -16777216, "default_avatar_fill_color": -12345678},
          "Profile 1": {"name": "Work", "profile_color_seed": -16730235, "profile_highlight_color": -1},
          "Profile 2": {"name": "Plain", "profile_highlight_color": -16777216}
        }}}
        """
        let profiles = ChromiumLocalState.profiles(from: Data(json.utf8))
        #expect(profiles.first { $0.name == "Personal" }?.colorARGB == UInt32(truncatingIfNeeded: Int64(-12345678)))
        #expect(profiles.first { $0.name == "Work" }?.colorARGB == 0xFF00B785)
        #expect(profiles.first { $0.name == "Plain" }?.colorARGB == nil)
    }
}
