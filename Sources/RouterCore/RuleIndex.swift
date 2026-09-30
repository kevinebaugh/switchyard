import Foundation

/// In-memory index for rule lookup. Built once per rules change; matching walks the
/// URL host's labels (`a.b.slack.com` → `b.slack.com` → `slack.com` → `com`) and
/// picks the most specific matching rule. No I/O, no ordering dependence.
///
/// Precedence:
/// 1. the most specific URL rule, if you made or corrected it;
/// 2. an app rule for the app the link came from ("links from Slack");
/// 3. the most specific URL rule Jev learned.
public struct RuleIndex: Sendable {
    private let rulesByHost: [String: [Rule]]
    private let appRules: [String: Rule]

    public init(rules: [Rule]) {
        var rulesByHost: [String: [Rule]] = [:]
        var appRules: [String: Rule] = [:]
        for rule in rules where !rule.deleted {
            if rule.key.isAppRule, let sourceApp = rule.sourceApp {
                let id = sourceApp.bundleID.lowercased()
                if let existing = appRules[id], existing.updatedAt >= rule.updatedAt { continue }
                appRules[id] = rule
            } else if !rule.host.isEmpty {
                rulesByHost[rule.host, default: []].append(rule)
            }
        }
        self.rulesByHost = rulesByHost
        self.appRules = appRules
    }

    public func appRule(for bundleID: String) -> Rule? {
        appRules[bundleID.lowercased()]
    }

    /// - Parameters:
    ///   - sourceAppBundleID: the app the link was clicked in, if known.
    ///   - availableProfiles: lowercased names of profiles that exist on this Mac.
    ///     Rules targeting any other profile are skipped. `nil` skips nothing.
    public func match(
        _ url: URL,
        from sourceAppBundleID: String? = nil,
        availableProfiles: Set<String>? = nil
    ) -> Rule? {
        let urlRule = matchURL(url, from: sourceAppBundleID, availableProfiles: availableProfiles)
        if let urlRule, urlRule.origin != .learned { return urlRule }

        if let sourceAppBundleID, let appRule = appRule(for: sourceAppBundleID),
           availableProfiles.map({ $0.contains(appRule.profileName.lowercased()) }) ?? true {
            return appRule
        }
        return urlRule
    }

    private func matchURL(_ url: URL, from sourceAppBundleID: String?, availableProfiles: Set<String>?) -> Rule? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawHost = components.host, !rawHost.isEmpty else {
            return nil
        }

        let host = RuleKey.normalizeHost(rawHost)
        let path = components.path.lowercased()
        let queryItems = components.queryItems ?? []

        var best: Rule?
        var bestSpecificity: Specificity?

        var labels = host.split(separator: ".")
        while !labels.isEmpty {
            let candidateHost = labels.joined(separator: ".")
            for rule in rulesByHost[candidateHost] ?? [] {
                if rule.hostMatch == .exact, candidateHost != host { continue }
                if let availableProfiles, !availableProfiles.contains(rule.profileName.lowercased()) { continue }
                if let ruleApp = rule.sourceApp,
                   ruleApp.bundleID.lowercased() != sourceAppBundleID?.lowercased() { continue }
                guard Self.pathMatches(path, prefix: rule.pathPrefix),
                      Self.queryMatches(queryItems, required: rule.query) else { continue }

                let specificity = Specificity(rule.key)
                if bestSpecificity.map({ specificity > $0 }) ?? true {
                    best = rule
                    bestSpecificity = specificity
                }
            }
            labels.removeFirst()
        }
        return best
    }

    static func pathMatches(_ path: String, prefix: String?) -> Bool {
        guard let prefix else { return true }
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    static func queryMatches(_ items: [URLQueryItem], required: [String: String]?) -> Bool {
        guard let required else { return true }
        return required.allSatisfy { name, value in
            items.contains { $0.name.lowercased() == name && ($0.value ?? "").lowercased() == value }
        }
    }
}

/// Ranking for "most specific wins": source app, then query params, then path depth,
/// then exact-over-domain, then host label count.
struct Specificity: Comparable {
    let sourceApp: Int
    let queryCount: Int
    let pathDepth: Int
    let exactHost: Int
    let hostLabels: Int

    init(_ key: RuleKey) {
        sourceApp = key.sourceApp == nil ? 0 : 1
        queryCount = key.query?.count ?? 0
        pathDepth = key.pathDepth
        exactHost = key.hostMatch == .exact ? 1 : 0
        hostLabels = key.host.split(separator: ".").count
    }

    static func < (lhs: Specificity, rhs: Specificity) -> Bool {
        (lhs.sourceApp, lhs.queryCount, lhs.pathDepth, lhs.exactHost, lhs.hostLabels)
            < (rhs.sourceApp, rhs.queryCount, rhs.pathDepth, rhs.exactHost, rhs.hostLabels)
    }
}
