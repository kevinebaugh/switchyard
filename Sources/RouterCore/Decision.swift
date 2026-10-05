import Foundation

public enum FallbackReason: Codable, Hashable, Sendable {
    case noAPIKey
    case timeout
    /// No network at all.
    case offline
    /// A network, but it can't reach Jev (a captive portal, a dead hotspot, a recent failure).
    case unreachable
    case unauthorized
    case rateLimited
    case overloaded
    case http(Int)
    case invalidResponse
    case unknownProfile(String)

    /// Why the fallback was used, in a few words ("Jev timed out"). The one wording used
    /// by the Recent list, notifications, the status line and the log.
    public var label: String {
        switch self {
        case .noAPIKey: "no API key"
        case .timeout: "Jev timed out"
        case .offline: "offline"
        case .unreachable: "couldn't reach Jev"
        case .unauthorized: "API key rejected"
        case .rateLimited: "Jev rate-limited"
        case .overloaded: "Jev busy"
        case let .http(code): "Jev error \(code)"
        case .invalidResponse: "unreadable answer"
        case let .unknownProfile(name): "Jev picked unknown profile \(name)"
        }
    }

    /// Jev couldn't be reached at all: worth retrying once the network recovers, and caught up on.
    public var isNetworkFailure: Bool {
        switch self {
        case .timeout, .offline, .unreachable: true
        default: false
        }
    }

    /// How a failed request to Jev is reported. Certificate errors mean something between the Mac
    /// and Jev intercepted HTTPS, which is what a captive portal does.
    public init(urlErrorCode code: URLError.Code) {
        switch code {
        case .timedOut, .cancelled:
            self = .timeout
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            self = .offline
        case .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
             .clientCertificateRejected, .clientCertificateRequired, .redirectToNonExistentLocation:
            self = .unreachable
        default:
            self = .http(code.rawValue)
        }
    }

    /// Problems the user has to fix, as opposed to transient failures.
    public var isSetupProblem: Bool {
        switch self {
        case .noAPIKey, .unauthorized: true
        default: false
        }
    }
}

/// Why a link opened where it did. Stored on every routing record.
public enum Decision: Codable, Hashable, Sendable {
    case rule(id: UUID, label: String)
    case jev(confidence: Double, scope: LinkScope?)
    case lowConfidence(confidence: Double)
    case fallback(FallbackReason)
    /// `switchyard://open?profile=` or "open again in" from the menu.
    case explicit

    /// A compact form for the status line and the log; the Recent list uses RoutingExplanation.
    public var badge: String {
        switch self {
        case .rule: "rule"
        case let .jev(confidence, _): "Jev \(confidence.confidenceLabel)"
        case let .lowConfidence(confidence): "⚠︎ Jev \(confidence.confidenceLabel)"
        case let .fallback(reason): "↩︎ fallback · \(reason.label)"
        case .explicit: "manual"
        }
    }

    public var needsAttention: Bool {
        switch self {
        case .lowConfidence, .fallback: true
        default: false
        }
    }
}

extension Double {
    /// A Jev confidence as shown everywhere: "0.84".
    public var confidenceLabel: String {
        String(format: "%.2f", self)
    }
}

public struct JevOutcome: Sendable, Equatable {
    public let profile: String
    public let profileConfidence: Double
    public let scope: LinkScope?
    public let scopeConfidence: Double

    public init(profile: String, profileConfidence: Double, scope: LinkScope?, scopeConfidence: Double) {
        self.profile = profile
        self.profileConfidence = profileConfidence
        self.scope = scope
        self.scopeConfidence = scopeConfidence
    }

    public init?(response: Jev.Response) {
        guard let profileAnswer = response.answers[Jev.profileQuestionID] else { return nil }
        let scopeAnswer = response.answers[Jev.scopeQuestionID]
        self.init(
            profile: profileAnswer.choice,
            profileConfidence: profileAnswer.confidence,
            scope: scopeAnswer.flatMap { LinkScope(rawValue: $0.choice) },
            scopeConfidence: scopeAnswer?.confidence ?? 0
        )
    }
}

public struct Verdict: Sendable, Equatable {
    public let profileName: String
    public let decision: Decision
    /// The rule to save, if the decision is confident enough to generalize.
    public let learn: RuleKey?

    public init(profileName: String, decision: Decision, learn: RuleKey?) {
        self.profileName = profileName
        self.decision = decision
        self.learn = learn
    }
}

public enum DecisionPolicy {
    public static let defaultProfileThreshold = 0.7
    public static let scopeThreshold = 0.5

    public static func verdict(
        for outcome: JevOutcome,
        features: LinkFeatures,
        knownProfiles: [String],
        fallbackProfile: String,
        profileThreshold: Double = defaultProfileThreshold
    ) -> Verdict {
        guard let profileName = knownProfiles.first(where: {
            $0.compare(outcome.profile, options: [.caseInsensitive]) == .orderedSame
        }) else {
            return Verdict(profileName: fallbackProfile, decision: .fallback(.unknownProfile(outcome.profile)), learn: nil)
        }

        guard outcome.profileConfidence >= profileThreshold else {
            return Verdict(profileName: profileName, decision: .lowConfidence(confidence: outcome.profileConfidence), learn: nil)
        }

        let learn: RuleKey? = if let scope = outcome.scope, outcome.scopeConfidence >= scopeThreshold {
            features.ruleKey(for: scope)
        } else {
            nil
        }
        return Verdict(
            profileName: profileName,
            decision: .jev(confidence: outcome.profileConfidence, scope: outcome.scope),
            learn: learn
        )
    }

    public static func fallback(_ reason: FallbackReason, fallbackProfile: String) -> Verdict {
        Verdict(profileName: fallbackProfile, decision: .fallback(reason), learn: nil)
    }
}
