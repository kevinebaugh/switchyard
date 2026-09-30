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

    public func liveRules(for browser: BrowserKind) -> [Rule] {
        rules.filter { !$0.deleted && $0.effectiveBrowser == browser }
    }

    public func rule(for key: RuleKey, browser: BrowserKind = .dia) -> Rule? {
        rules.first { !$0.deleted && $0.key == key && $0.effectiveBrowser == browser }
    }

    @discardableResult
    public mutating func upsert(
        key: RuleKey,
        profileName: String,
        origin: RuleOrigin,
        browser: BrowserKind = .dia,
        now: Date = Date()
    ) -> Rule {
        if let index = rules.firstIndex(where: { !$0.deleted && $0.key == key && $0.effectiveBrowser == browser }) {
            rules[index].profileName = profileName
            rules[index].origin = origin
            rules[index].updatedAt = now
            return rules[index]
        }
        let rule = Rule(key: key, profileName: profileName, origin: origin, browser: browser, updatedAt: now)
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
    public mutating func renameProfile(from oldName: String, to newName: String, browser: BrowserKind = .dia, now: Date = Date()) {
        for index in rules.indices
        where !rules[index].deleted && rules[index].effectiveBrowser == browser
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
        struct Identity: Hashable { let key: RuleKey; let browser: BrowserKind }
        var newest: [Identity: Rule] = [:]
        for rule in byID.values where !rule.deleted {
            let identity = Identity(key: rule.key, browser: rule.effectiveBrowser)
            if let existing = newest[identity], existing.updatedAt >= rule.updatedAt { continue }
            newest[identity] = rule
        }
        for (id, rule) in byID
        where !rule.deleted && newest[Identity(key: rule.key, browser: rule.effectiveBrowser)]?.id != id {
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
