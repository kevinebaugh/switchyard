import Foundation
import Testing
@testable import RouterCore

@Suite struct LinkFeaturesTests {
    @Test func sanitizedURLDropsQueryFragmentAndDeepPath() throws {
        let features = try #require(LinkFeatures(url: URL(string:
            "https://app.shortcut.com/acme/story/123/some-title/extra?token=SECRET&authuser=me@x.com#frag")!))
        #expect(features.sanitizedURL == "app.shortcut.com/acme/story/123")
        #expect(features.queryNames == ["authuser", "token"])
        #expect(!features.sanitizedURL.contains("SECRET"))
    }

    @Test func scopeRuleKeys() throws {
        let features = try #require(LinkFeatures(url: URL(string: "https://app.shortcut.com/acme/story/1?authuser=2")!))
        #expect(features.ruleKey(for: .domain) == RuleKey(host: "shortcut.com", hostMatch: .domain))
        #expect(features.ruleKey(for: .subdomain) == RuleKey(host: "app.shortcut.com", hostMatch: .exact))
        #expect(features.ruleKey(for: .firstPathSegment) == RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"))
        #expect(features.ruleKey(for: .queryIdentifier) == RuleKey(host: "app.shortcut.com", hostMatch: .exact, query: ["authuser": "2"]))
        #expect(features.ruleKey(for: .none) == nil)
    }

    @Test func scopesThatDontApplyReturnNil() throws {
        let features = try #require(LinkFeatures(url: URL(string: "https://nytimes.com")!))
        #expect(features.ruleKey(for: .firstPathSegment) == nil)
        #expect(features.ruleKey(for: .queryIdentifier) == nil)
    }

    @Test func correctionOptions() throws {
        let features = try #require(LinkFeatures(url: URL(string: "https://app.shortcut.com/acme/story/1?authuser=2")!))
        #expect(features.correctionOptions.map(\.label) == [
            "all of shortcut.com",
            "app.shortcut.com",
            "app.shortcut.com/acme",
            "app.shortcut.com/acme/story",
            "app.shortcut.com ?authuser=2",
        ])

        let plain = try #require(LinkFeatures(url: URL(string: "https://nytimes.com/")!))
        #expect(plain.correctionOptions.map(\.label) == ["all of nytimes.com"])
    }
}

@Suite struct DecisionPolicyTests {
    let features = LinkFeatures(url: URL(string: "https://app.shortcut.com/acme/story/1")!)!
    let profiles = ["Personal", "Test", "Work"]

    @Test func confidentAnswerLearnsScopedRule() {
        let verdict = DecisionPolicy.verdict(
            for: JevOutcome(profile: "work", profileConfidence: 0.9, scope: .firstPathSegment, scopeConfidence: 0.8),
            features: features, knownProfiles: profiles, fallbackProfile: "Personal"
        )
        #expect(verdict.profileName == "Work")
        #expect(verdict.decision == .jev(confidence: 0.9, scope: .firstPathSegment))
        #expect(verdict.learn == RuleKey(host: "app.shortcut.com", hostMatch: .exact, pathPrefix: "/acme"))
    }

    @Test func unsureScopeOpensButDoesNotLearn() {
        let verdict = DecisionPolicy.verdict(
            for: JevOutcome(profile: "Work", profileConfidence: 0.9, scope: .domain, scopeConfidence: 0.3),
            features: features, knownProfiles: profiles, fallbackProfile: "Personal"
        )
        #expect(verdict.profileName == "Work")
        #expect(verdict.learn == nil)
    }

    @Test func noneScopeDoesNotLearn() {
        let verdict = DecisionPolicy.verdict(
            for: JevOutcome(profile: "Work", profileConfidence: 0.95, scope: LinkScope.none, scopeConfidence: 0.9),
            features: features, knownProfiles: profiles, fallbackProfile: "Personal"
        )
        #expect(verdict.learn == nil)
    }

    @Test func lowConfidenceOpensTopPickWithoutLearning() {
        let verdict = DecisionPolicy.verdict(
            for: JevOutcome(profile: "Test", profileConfidence: 0.55, scope: .domain, scopeConfidence: 0.9),
            features: features, knownProfiles: profiles, fallbackProfile: "Personal"
        )
        #expect(verdict.profileName == "Test")
        #expect(verdict.decision == .lowConfidence(confidence: 0.55))
        #expect(verdict.learn == nil)
        #expect(verdict.decision.needsAttention)
    }

    @Test func unknownProfileFallsBack() {
        let verdict = DecisionPolicy.verdict(
            for: JevOutcome(profile: "Gone", profileConfidence: 0.99, scope: .domain, scopeConfidence: 0.9),
            features: features, knownProfiles: profiles, fallbackProfile: "Personal"
        )
        #expect(verdict.profileName == "Personal")
        #expect(verdict.decision == .fallback(.unknownProfile("Gone")))
    }

    @Test func fallbackReasonsAreLabelled() {
        let reasons: [FallbackReason] = [.noAPIKey, .timeout, .offline, .unauthorized, .rateLimited, .overloaded, .http(500), .invalidResponse]
        for reason in reasons {
            let verdict = DecisionPolicy.fallback(reason, fallbackProfile: "Personal")
            #expect(verdict.profileName == "Personal")
            #expect(verdict.learn == nil)
            #expect(verdict.decision.badge.contains(reason.label))
        }
    }
}

@Suite struct JevCodecTests {
    @Test func requestEncodesWithoutQueryValues() throws {
        let features = try #require(LinkFeatures(url: URL(string: "https://app.shortcut.com/acme/story/1?code=SECRET")!))
        let request = Jev.makeRequest(
            features: features,
            scheme: "https",
            profiles: [Jev.Profile(name: "Work", description: "Work"), Jev.Profile(name: "Test", description: "")],
            openedFromApp: "Slack"
        )
        let data = try JSONEncoder().encode(request)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("SECRET"))

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["model"] as? String == "jev-latest")
        let state = try #require(object["state"] as? [String: Any])
        #expect(state["url"] as? String == "https://app.shortcut.com/acme/story/1")
        #expect(state["query_keys"] as? [String] == ["code"])
        #expect(state["opened_from_app"] as? String == "Slack")
        let questions = try #require(object["questions"] as? [String: [String: Any]])
        #expect(questions["profile"]?["type"] as? String == "choice")
        let criteria = try #require(questions["profile"]?["criteria"] as? [String: String])
        #expect(criteria["Work"] == "Work")
        #expect(criteria["Test"] == "The Test browser profile.")
        let scopeCriteria = try #require(questions["scope"]?["criteria"] as? [String: String])
        #expect(Set(scopeCriteria.keys) == Set(LinkScope.allCases.map(\.rawValue)))
    }

    @Test func responseDecodesIntoOutcome() throws {
        let json = """
        {
          "model": "jev-1.13.0",
          "answers": {
            "profile": { "type": "choice", "choice": "Work",
                         "probabilities": { "Work": 0.91, "Personal": 0.06, "Test": 0.03 }, "confidence": 0.87 },
            "scope": { "type": "choice", "choice": "first_path_segment",
                       "probabilities": { "first_path_segment": 0.8, "domain": 0.2 }, "confidence": 0.7 }
          },
          "usage": { "input_tokens": 318, "output_tokens": 34 }
        }
        """
        let response = try JSONDecoder().decode(Jev.Response.self, from: Data(json.utf8))
        let outcome = try #require(JevOutcome(response: response))
        #expect(outcome == JevOutcome(profile: "Work", profileConfidence: 0.87, scope: .firstPathSegment, scopeConfidence: 0.7))
    }
}
