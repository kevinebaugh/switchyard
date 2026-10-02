import Foundation

/// When to remind someone that Switchyard can be supported with a one-time payment:
/// every `linkInterval` routed links, but never more often than `minimumGap`, never in the
/// first `minimumGap` after first use, and never again once they've supported it.
public enum SupportNudge {
    public static let linkInterval = 50
    public static let minimumGap: TimeInterval = 7 * 24 * 60 * 60

    public struct State: Codable, Equatable, Sendable {
        public var routedLinks = 0
        /// `routedLinks` when the last reminder was shown.
        public var lastShownAtCount = 0
        public var lastShownDate: Date?
        public var firstUseDate: Date?

        public init(routedLinks: Int = 0, lastShownAtCount: Int = 0, lastShownDate: Date? = nil, firstUseDate: Date? = nil) {
            self.routedLinks = routedLinks
            self.lastShownAtCount = lastShownAtCount
            self.lastShownDate = lastShownDate
            self.firstUseDate = firstUseDate
        }
    }

    public static func isDue(_ state: State, isSupporter: Bool, now: Date = Date()) -> Bool {
        guard !isSupporter, state.routedLinks - state.lastShownAtCount >= linkInterval else { return false }
        guard let since = state.lastShownDate ?? state.firstUseDate else { return false }
        return now.timeIntervalSince(since) >= minimumGap
    }

    /// Count one routed link (stamping first use), and say whether a reminder is now due.
    public static func recordLink(_ state: inout State, isSupporter: Bool, now: Date = Date()) -> Bool {
        if state.firstUseDate == nil { state.firstUseDate = now }
        state.routedLinks += 1
        return isDue(state, isSupporter: isSupporter, now: now)
    }

    public static func markShown(_ state: inout State, now: Date = Date()) {
        state.lastShownAtCount = state.routedLinks
        state.lastShownDate = now
    }
}
