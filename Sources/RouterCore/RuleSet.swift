import Foundation

/// The synced rules file. Merge-friendly: rules are identified by `id`, the newer
/// `updatedAt` wins, and deletions are tombstones so they survive a concurrent edit.
///
/// Several versions of Switchyard can share one file (say, a Mac that hasn't updated yet), so
/// reading is forgiving and writing is careful: a version only writes a file it fully understood.
public struct RuleSet: Codable, Equatable, Sendable {
    public static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Bump whenever the file's format changes (new fields, new values), so older versions
    /// know to leave it alone. 2 = rules carry a `browser`.
    public static let currentVersion = 2

    public var version = RuleSet.currentVersion
    public var rules: [Rule]
    /// Rules in the file this version couldn't read (from a newer format). They're never
    /// written back, which is why a file with any of them is read-only.
    public private(set) var unreadableRuleCount = 0

    public init(rules: [Rule] = []) {
        self.rules = rules
    }

    /// Whether writing this file back would lose nothing: it's from this format or older,
    /// and every rule in it was understood.
    public var isSafeToWrite: Bool {
        version <= Self.currentVersion && unreadableRuleCount == 0
    }

    enum CodingKeys: String, CodingKey {
        case version, rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        rules = []
        guard container.contains(.rules) else { return }

        // One rule this version can't read mustn't take the rest of the file with it.
        var list = try container.nestedUnkeyedContainer(forKey: .rules)
        while !list.isAtEnd {
            if let rule = try? list.decode(Rule.self) {
                rules.append(rule)
            } else {
                _ = try list.decode(Skip.self)
                unreadableRuleCount += 1
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(rules, forKey: .rules)
    }

    /// Consumes one array element without reading it.
    private struct Skip: Decodable {
        init(from decoder: Decoder) {}
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
