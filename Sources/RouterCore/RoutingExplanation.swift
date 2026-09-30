import Foundation

/// A short, plain answer to "why did this link open there?" for the Recent list.
public enum RoutingExplanation {
    public struct Line: Equatable, Sendable {
        public let text: String
        /// Worth a second look: Jev was unsure, or a fallback was used.
        public let needsAttention: Bool
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

        case let .fallback(reason):
            if let saved {
                return Line(text: "Fallback: \(reason.label) · you saved \(saved)", needsAttention: false)
            }
            return Line(text: "Fallback: \(reason.label)", needsAttention: true)

        case .explicit:
            return Line(text: "Opened in a named profile", needsAttention: false)
        }
    }

    private static func jev(_ confidence: Double) -> String {
        "Jev \(confidence.confidenceLabel)"
    }

    private static func format(_ confidence: Double) -> String {
        confidence.confidenceLabel
    }
}
