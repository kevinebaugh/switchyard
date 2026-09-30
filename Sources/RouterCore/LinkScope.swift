import Foundation

/// How broadly a routing decision generalizes. Jev picks one per link; corrections let
/// the user pick from the concrete options this URL supports.
public enum LinkScope: String, Codable, Sendable, CaseIterable {
    case domain
    case subdomain
    case firstPathSegment = "first_path_segment"
    case queryIdentifier = "query_identifier"
    case none
}

/// A query parameter that names an account (`authuser=you@example.com`).
public struct QueryIdentifier: Sendable, Equatable {
    public let name: String
    public let value: String
}

/// What we know about a URL, reduced to the parts that identify an account.
public struct LinkFeatures: Sendable, Equatable {
    /// Query parameters that name an account or workspace. Only these can become rule keys.
    public static let identifierQueryNames: [String] = ["authuser", "account", "org", "workspace", "team", "tenant"]
    /// Path segments sent to Jev. Deeper segments are more likely to be ids or tokens.
    public static let maxPathSegmentsSent = 3

    public let host: String
    public let registrableDomain: String
    public let pathSegments: [String]
    public let queryNames: [String]
    public let identifierQuery: QueryIdentifier?

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        self.host = RuleKey.normalizeHost(host)
        self.registrableDomain = PublicSuffix.registrableDomain(for: host)
        self.pathSegments = components.path.split(separator: "/").map(String.init)
        let items = components.queryItems ?? []
        self.queryNames = Array(Set(items.map { $0.name.lowercased() })).sorted()
        self.identifierQuery = Self.identifierQueryNames.lazy.compactMap { name in
            items.first { $0.name.lowercased() == name && !($0.value ?? "").isEmpty }
                .map { QueryIdentifier(name: name, value: $0.value!) }
        }.first
    }

    /// The URL as sent to Jev: scheme-less host plus the first few path segments.
    /// No query values, no fragment, nothing deep enough to carry a token.
    public var sanitizedURL: String {
        let segments = pathSegments.prefix(Self.maxPathSegmentsSent)
        return segments.isEmpty ? host : host + "/" + segments.joined(separator: "/")
    }

    /// The rule a scope would create for this URL, or nil when the scope doesn't apply.
    public func ruleKey(for scope: LinkScope) -> RuleKey? {
        switch scope {
        case .domain:
            RuleKey(host: registrableDomain, hostMatch: .domain)
        case .subdomain:
            RuleKey(host: host, hostMatch: .exact)
        case .firstPathSegment:
            pathSegments.first.map { RuleKey(host: host, hostMatch: .exact, pathPrefix: "/" + $0) }
        case .queryIdentifier:
            identifierQuery.map { RuleKey(host: host, hostMatch: .exact, query: [$0.name: $0.value]) }
        case .none:
            nil
        }
    }

    /// Every distinct rule a correction could save for this URL, broadest first.
    public var correctionOptions: [RuleKey] {
        var options: [RuleKey] = [RuleKey(host: registrableDomain, hostMatch: .domain)]
        if host != registrableDomain {
            options.append(RuleKey(host: host, hostMatch: .exact))
        }
        for depth in 1...2 where pathSegments.count >= depth {
            let prefix = "/" + pathSegments.prefix(depth).joined(separator: "/")
            options.append(RuleKey(host: host, hostMatch: .exact, pathPrefix: prefix))
        }
        if let identifierQuery {
            options.append(RuleKey(host: host, hostMatch: .exact, query: [identifierQuery.name: identifierQuery.value]))
        }
        var seen = Set<RuleKey>()
        return options.filter { seen.insert($0).inserted }
    }
}
