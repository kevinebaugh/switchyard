import Foundation

/// Rebuilds rules that Recent's history points to but the rule set no longer has (lost, for
/// example, when a sync folder was moved away under Switchyard). Only rules the history pins
/// down exactly come back, under their original IDs so the Recent rows find them again:
///
/// - a row decided by a rule stores that rule's label; the URL's possible rules (every scope,
///   plus "links from <app>") are searched for the one with exactly that label
/// - a row where Jev learned a rule stores the scope, which gives the rule directly
///
/// Each rebuilt rule is dated by the row it came from, so a newer edit elsewhere still wins.
public enum RuleRecovery {
    public static func rebuild(from records: [RoutingRecord], existing: Set<UUID>, browser: BrowserKind) -> [Rule] {
        var rebuilt: [UUID: Rule] = [:]
        // Evidence of how each missing rule was made, for its origin.
        var learnedByJev = Set<UUID>()
        var madeByCorrection = Set<UUID>()
        for record in records {
            guard let id = record.learnedRuleID else { continue }
            if case .jev = record.decision, record.correctedTo == nil { learnedByJev.insert(id) }
            if record.correctedTo != nil { madeByCorrection.insert(id) }
        }

        // Oldest first, so the newest row about a rule decides it.
        for record in records.sorted(by: { $0.date < $1.date }) {
            guard let features = LinkFeatures(url: record.url) else { continue }

            if case let .rule(id, label) = record.decision, !existing.contains(id),
               let key = candidates(for: record, features: features).first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                rebuilt[id] = Rule(id: id, key: key, profileName: record.profileName,
                                   origin: origin(for: id, key: key, learned: learnedByJev, corrected: madeByCorrection),
                                   browser: browser, updatedAt: record.date)
            }

            if case let .jev(_, scope) = record.decision, record.correctedTo == nil,
               let id = record.learnedRuleID, !existing.contains(id), rebuilt[id] == nil,
               let scope, let key = features.ruleKey(for: scope) {
                rebuilt[id] = Rule(id: id, key: key, profileName: record.profileName, origin: .learned,
                                   browser: browser, updatedAt: record.date)
            }
        }
        return rebuilt.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    private static func candidates(for record: RoutingRecord, features: LinkFeatures) -> [RuleKey] {
        var keys = features.correctionOptions
        keys += LinkScope.allCases.compactMap { features.ruleKey(for: $0) }
        if let source = record.source { keys.append(.app(source)) }
        return keys
    }

    private static func origin(for id: UUID, key: RuleKey, learned: Set<UUID>, corrected: Set<UUID>) -> RuleOrigin {
        if corrected.contains(id) { return .corrected }
        if learned.contains(id) { return .learned }
        // App rules are only ever made by you (a suggestion you accepted, or a correction).
        return key.sourceApp != nil ? .manual : .learned
    }
}
