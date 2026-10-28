import Foundation
import Testing
@testable import RouterCore

/// The promise in docs/COMPATIBILITY.md, enforced: rules files written by every version of
/// Switchyard keep reading the same way, and a file this version doesn't fully understand is
/// never written back. These fixtures are frozen; add new ones, never edit old ones.
@Suite struct CompatibilityTests {
    func load(_ name: String) throws -> RuleSet {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuleSet.self, from: Data(contentsOf: url))
    }

    func roundTrip(_ set: RuleSet) throws -> RuleSet {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuleSet.self, from: encoder.encode(set))
    }

    @Test func version1FilesAreDiaRules() throws {
        let set = try load("rules-v1")
        #expect(set.version == 1)
        #expect(set.isSafeToWrite)
        #expect(set.rules.count == 2)
        #expect(set.rules.allSatisfy { $0.browser == nil && $0.effectiveBrowser == .dia })
        #expect(set.rules[1].key == RuleKey(host: "github.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(set.rules[1].origin == .corrected)
        // Written back as the current format, losing nothing.
        let written = try roundTrip(set)
        #expect(written.version == RuleSet.currentVersion)
        #expect(written.rules == set.rules)
    }

    @Test func version2FilesReadEveryKindOfRule() throws {
        let set = try load("rules-v2")
        #expect(set.isSafeToWrite)
        #expect(set.rules.map(\.effectiveBrowser) == [.dia, .chrome, .firefox, .dia])
        #expect(set.rules[0].key == .app(SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")))
        #expect(set.rules[1].key.query == ["authuser": "me@example.com"])
        #expect(set.rules[3].deleted)
        #expect(set.liveRules(for: .dia).count == 1)
        #expect(try roundTrip(set) == set)
    }

    @Test func aNewerFormatIsReadButNeverWritten() throws {
        let set = try load("rules-newer-version")
        #expect(set.version == 3)
        #expect(!set.isSafeToWrite)
        #expect(set.rules.count == 1)   // still routes with what it understands
    }

    @Test func aRuleThisVersionCantReadMakesTheFileReadOnly() throws {
        let set = try load("rules-unknown-browser")
        #expect(set.rules.map(\.host) == ["example.com"])
        #expect(set.unreadableRuleCount == 1)
        #expect(!set.isSafeToWrite)
    }

    @Test func theFormatVersionOnlyMovesForward() {
        // Bumping this needs a new fixture for the new format, and docs/COMPATIBILITY.md updated.
        #expect(RuleSet.currentVersion == 2)
    }
}
