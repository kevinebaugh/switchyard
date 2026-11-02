import Foundation
import Testing
@testable import RouterCore

@Suite struct DestinationTests {
    @Test func labelsStayPlainWithOneBrowser() {
        let personal = Destination(browser: .firefox, profile: "Personal")
        #expect(personal.label(multiBrowser: false) == "Personal")   // exactly as before 2.0
        #expect(personal.label(multiBrowser: true) == "Firefox · Personal")
        #expect(Destination.safari.label(multiBrowser: true) == "Safari")
        #expect(personal.id == "firefox/personal")
        #expect(Destination(browser: .firefox, profile: "PERSONAL").id == personal.id)
    }

    @Test func safariIsOneDestinationWithoutProfilesOrArguments() {
        #expect(!BrowserKind.safari.hasProfiles)
        #expect(!BrowserKind.safari.opensWithArguments)
        #expect(BrowserKind.safari.opening == .plain)
        #expect(BrowserKind.allCases.filter { !$0.hasProfiles } == [.safari])
    }

    @Test func rulesMatchAcrossEveryBrowserInUse() {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        let rules = [
            Rule(key: RuleKey(host: "example.com", hostMatch: .domain), profileName: "Personal", origin: .corrected, browser: .firefox, updatedAt: t0),
            Rule(key: RuleKey(host: "acme.com", hostMatch: .domain), profileName: "Safari", origin: .corrected, browser: .safari, updatedAt: t0),
            Rule(key: RuleKey(host: "side.dev", hostMatch: .domain), profileName: "Projects", origin: .learned, browser: .chrome, updatedAt: t0),
        ]
        let index = RuleIndex(rules: rules, browsers: [.firefox, .safari, .chrome])
        func url(_ s: String) -> URL { URL(string: s)! }
        #expect(index.match(url("https://www.example.com/x"))?.destination == Destination(browser: .firefox, profile: "Personal"))
        #expect(index.match(url("https://acme.com/wiki"))?.destination == .safari)
        #expect(index.match(url("https://side.dev"))?.destination == Destination(browser: .chrome, profile: "Projects"))

        // A browser that isn't in use is skipped, like a profile that doesn't exist.
        #expect(RuleIndex(rules: rules, browsers: [.firefox]).match(url("https://acme.com")) == nil)
        let available: Set<String> = ["firefox/personal", "safari/safari"]
        #expect(index.match(url("https://side.dev"), availableDestinations: available) == nil)
        #expect(index.match(url("https://acme.com"), availableDestinations: available)?.destination == .safari)
    }

    @Test func oldRecordsOpenedInTheBrowserInUse() {
        let record = RoutingRecord(url: URL(string: "https://a.example")!, profileName: "Work",
                                   decision: .jev(confidence: 0.9, scope: nil), latencyMilliseconds: 1)
        #expect(record.browser == nil)
        #expect(record.destination(defaultBrowser: .dia) == Destination(browser: .dia, profile: "Work"))
    }
}
