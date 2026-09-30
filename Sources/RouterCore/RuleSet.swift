import Foundation

/// The synced rules file. Merge-friendly: rules are identified by `id`, the newer
/// `updatedAt` wins, and deletions are tombstones so they survive a concurrent edit.
public struct RuleSet: Codable, Equatable, Sendable {
    public static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    public var version = 1
    public var rules: [Rule]

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    public var liveRules: [Rule] {
        rules.filter { !$0.deleted }
    }

    public func rule(for key: RuleKey) -> Rule? {
        rules.first { !$0.deleted && $0.key == key }
    }

    @discardableResult
    public mutating func upsert(key: RuleKey, profileName: String, origin: RuleOrigin, now: Date = Date()) -> Rule {
        if let index = rules.firstIndex(where: { !$0.deleted && $0.key == key }) {
            rules[index].profileName = profileName
            rules[index].origin = origin
            rules[index].updatedAt = now
            return rules[index]
        }
        let rule = Rule(key: key, profileName: profileName, origin: origin, updatedAt: now)
        rules.append(rule)
        return rule
    }

    public mutating func update(_ rule: Rule, now: Date = Date()) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var rule = rule
        rule.updatedAt = now
        rules[index] = rule
    }

    public mutating func delete(id: UUID, now: Date = Date()) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].deleted = true
        rules[index].updatedAt = now
    }

    /// Dia renamed a profile on this Mac: follow it in every rule.
    public mutating func renameProfile(from oldName: String, to newName: String, now: Date = Date()) {
        for index in rules.indices
        where !rules[index].deleted
            && rules[index].profileName.compare(oldName, options: .caseInsensitive) == .orderedSame {
            rules[index].profileName = newName
            rules[index].updatedAt = now
        }
    }

    /// Combine two copies of the file (e.g. ours and one another Mac just wrote).
    public static func merge(_ lhs: RuleSet, _ rhs: RuleSet, now: Date = Date()) -> RuleSet {
        var byID: [UUID: Rule] = [:]
        for rule in lhs.rules + rhs.rules {
            if let existing = byID[rule.id], existing.updatedAt >= rule.updatedAt { continue }
            byID[rule.id] = rule
        }

        // Two Macs can independently create a rule for the same key. Keep the newest.
        var newestByKey: [RuleKey: Rule] = [:]
        for rule in byID.values where !rule.deleted {
            if let existing = newestByKey[rule.key], existing.updatedAt >= rule.updatedAt { continue }
            newestByKey[rule.key] = rule
        }
        for (id, rule) in byID where !rule.deleted && newestByKey[rule.key]?.id != id {
            var tombstone = rule
            tombstone.deleted = true
            byID[id] = tombstone
        }

        let cutoff = now.addingTimeInterval(-tombstoneLifetime)
        let merged = byID.values
            .filter { !$0.deleted || $0.updatedAt > cutoff }
            .sorted { ($0.host, $0.pathPrefix ?? "", $0.id.uuidString) < ($1.host, $1.pathPrefix ?? "", $1.id.uuidString) }
        return RuleSet(rules: merged)
    }
}
