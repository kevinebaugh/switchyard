import Foundation

/// A short, plain answer to "why did this link open there?" for the Recent list.
public enum RoutingExplanation {
    public struct Line: Equatable, Sendable {
        public let text: String
        /// Worth a second look: Jev was unsure, or a fallback was used. Shown in orange.
        public let needsAttention: Bool
        /// Counts toward the menu-bar badge. Usually the same as `needsAttention`; a catch-up
        /// that's merely unsure doesn't count (after a flight there can be many, and none has an
        /// obvious fix), only one that says the link belonged in another profile.
        public let badges: Bool

        public init(text: String, needsAttention: Bool, badges: Bool? = nil) {
            self.text = text
            self.needsAttention = needsAttention
            self.badges = badges ?? needsAttention
        }
    }

    /// - Parameter rule: looks up a rule by id in the current rule set (it may have changed or
    ///   been deleted since the link was routed).
    public static func explain(_ record: RoutingRecord, rule: (UUID) -> Rule?) -> Line {
        let saved = record.learnedRuleID.flatMap(rule).map(\.key.label)

        if let correctedTo = record.correctedTo {
            return Line(text: saved.map { "You moved it to \(correctedTo) · saved \($0)" } ?? "You re-opened it in \(correctedTo)",
                        needsAttention: false)
        }

        switch record.decision {
        case let .rule(id, label):
            guard let current = rule(id) else {
                return Line(text: "Rule: \(label) (since removed)", needsAttention: false)
            }
            let whose = current.origin == .learned ? "Learned rule" : "Your rule"
            return Line(text: "\(whose): \(current.key.label)", needsAttention: false)

        case let .jev(confidence, _):
            if let saved, record.learnedRuleID.flatMap(rule)?.origin == .learned {
                return Line(text: "\(jev(confidence)) · learned \(saved)", needsAttention: false)
            }
            if let saved {
                return Line(text: "\(jev(confidence)) · you saved \(saved)", needsAttention: false)
            }
            return Line(text: "\(jev(confidence)) · nothing saved (too specific)", needsAttention: false)

        case let .lowConfidence(confidence):
            if let saved {
                return Line(text: "Jev unsure (\(format(confidence))) · you saved \(saved)", needsAttention: false)
            }
            return Line(text: "Jev unsure (\(format(confidence))) · nothing saved", needsAttention: true)

        case let .fallback(reason) where reason.isNetworkFailure:
            return network(reason, record: record, saved: saved, savedOrigin: record.learnedRuleID.flatMap(rule)?.origin)

        case let .fallback(reason):
            if let saved {
                return Line(text: "Fallback: \(reason.label) · you saved \(saved)", needsAttention: false)
            }
            return Line(text: "Fallback: \(reason.label)", needsAttention: true)

        case .explicit:
            return Line(text: "Opened in a named profile", needsAttention: false)
        }
    }

    /// A link that opened in the fallback profile because Jev couldn't be reached, before and
    /// after catching up. Not flagged while waiting (there's nothing to do yet), nor once Jev
    /// agrees; flagged when Jev says it belonged elsewhere or isn't sure.
    private static func network(_ reason: FallbackReason, record: RoutingRecord, saved: String?, savedOrigin: RuleOrigin?) -> Line {
        let what = switch reason {
        case .offline: "Opened offline"
        case .unreachable: "Couldn't reach Jev"
        default: "Jev timed out"
        }
        if let saved, savedOrigin != .learned {
            return Line(text: "\(what) · you saved \(saved)", needsAttention: false)
        }
        guard let catchUp = record.catchUp else {
            let later = reason == .offline ? "Jev will check it later" : "will check it later"
            return Line(text: "\(what) · \(later)", needsAttention: false)
        }
        let learned = saved.map { " · learned \($0)" } ?? ""
        let confidence = format(catchUp.confidence)
        guard catchUp.isConfident else {
            return Line(text: "\(what) · Jev unsure (\(confidence))", needsAttention: true, badges: false)
        }
        if catchUp.profileName.caseInsensitiveCompare(record.profileName) == .orderedSame {
            return Line(text: "\(what) · Jev agrees (\(confidence))\(learned)", needsAttention: false)
        }
        // The row's "Move to …" button sits next to this, so it stays short; moving saves the rule.
        return Line(text: "\(what) · Jev says \(catchUp.profileName) (\(confidence))", needsAttention: true)
    }

    private static func jev(_ confidence: Double) -> String {
        "Jev \(confidence.confidenceLabel)"
    }

    private static func format(_ confidence: Double) -> String {
        confidence.confidenceLabel
    }
}
