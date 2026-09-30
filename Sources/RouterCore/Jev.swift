import Foundation

/// Wire types for TypeSafe's System One endpoint (`POST https://api.typesafe.ai/v1/systemone`).
/// See https://docs.typesafe.ai/api.md.
public enum Jev {
    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    public static let model = "jev-latest"

    public static let profileQuestionID = "profile"
    public static let scopeQuestionID = "scope"

    public struct Request: Encodable, Sendable {
        public let model: String
        public let state: State
        public let questions: [String: ChoiceQuestion]
    }

    public struct State: Encodable, Sendable, Equatable {
        public let url: String
        public let host: String
        public let pathSegments: [String]
        public let queryKeys: [String]
        public let openedFromApp: String?

        enum CodingKeys: String, CodingKey {
            case url
            case host
            case pathSegments = "path_segments"
            case queryKeys = "query_keys"
            case openedFromApp = "opened_from_app"
        }
    }

    public struct ChoiceQuestion: Encodable, Sendable {
        public let type = "choice"
        public let instructions: String
        public let criteria: [String: String]

        enum CodingKeys: String, CodingKey {
            case type, instructions, criteria
        }
    }

    public struct Response: Decodable, Sendable {
        public let answers: [String: ChoiceAnswer]
    }

    public struct ChoiceAnswer: Decodable, Sendable {
        public let choice: String
        public let confidence: Double
    }

    public struct Profile: Sendable, Equatable {
        public let name: String
        public let description: String

        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }

    static let scopeCriteria: [String: String] = [
        LinkScope.domain.rawValue:
            "The whole site and all its subdomains belong to one person's account, e.g. a company's internal tool or a personal bank.",
        LinkScope.subdomain.rawValue:
            "The subdomain names the organization or workspace, e.g. acme.slack.com or acme.atlassian.net.",
        LinkScope.firstPathSegment.rawValue:
            "The first path segment names an organization, workspace, team or user, e.g. github.com/Acme, app.shortcut.com/acme, linear.app/acme.",
        LinkScope.queryIdentifier.rawValue:
            "A query parameter names the account, e.g. authuser= or org=.",
        LinkScope.none.rawValue:
            "It can't be generalized; each link differs, e.g. link shorteners, redirectors, shared document links, search results.",
    ]

    public static func makeRequest(
        features: LinkFeatures,
        scheme: String,
        profiles: [Profile],
        openedFromApp: String?
    ) -> Request {
        var criteria: [String: String] = [:]
        for profile in profiles {
            criteria[profile.name] = profile.description.isEmpty ? "The \(profile.name) browser profile." : profile.description
        }

        return Request(
            model: model,
            state: State(
                url: "\(scheme)://\(features.sanitizedURL)",
                host: features.host,
                pathSegments: Array(features.pathSegments.prefix(LinkFeatures.maxPathSegmentsSent)),
                queryKeys: features.queryNames,
                openedFromApp: openedFromApp
            ),
            questions: [
                profileQuestionID: ChoiceQuestion(
                    instructions: "Which browser profile should open this link? Each profile is signed in to different accounts.",
                    criteria: criteria
                ),
                scopeQuestionID: ChoiceQuestion(
                    instructions: "Which part of this URL decides whose account or workspace it belongs to?",
                    criteria: scopeCriteria
                ),
            ]
        )
    }
}
