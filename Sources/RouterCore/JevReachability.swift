import Foundation

/// Whether to ask Jev right now, and when to check again after it couldn't be reached.
///
/// - No network: skip Jev (`.offline`) until macOS reports one again.
/// - A network that can't reach Jev (a captive portal, a dead hotspot): after one failure, skip
///   Jev (`.unreachable`) and check in the background with exponential backoff: 5 s, 10 s, 20 s…
///   up to every 5 minutes, each wait jittered by ±20%. A network change or wake checks at once
///   and starts the backoff over; a link checks at once at most every 5 s, without resetting it.
/// - The first successful check (or request) makes Jev reachable again.
///
/// Links never wait on any of this: while Jev is skipped they open in the fallback profile.
public struct JevReachability: Sendable, Equatable {
    public static let backoff: [TimeInterval] = [5, 10, 20, 40, 80, 160]
    public static let maximumDelay: TimeInterval = 5 * 60
    public static let jitter = 0.2
    public static let linkCheckMinimumGap: TimeInterval = 5

    public private(set) var hasNetwork = true
    public private(set) var isReachable = true
    /// Background checks that have failed since Jev became unreachable.
    public private(set) var failedChecks = 0
    /// When the next background check is due, while Jev is unreachable.
    public private(set) var nextCheck: Date?
    public private(set) var lastCheck: Date?

    public init() {}

    /// Why Jev should be skipped right now, or nil to ask it.
    public var skipReason: FallbackReason? {
        if !hasNetwork { return .offline }
        if !isReachable { return .unreachable }
        return nil
    }

    /// The wait before background check number `attempt` (0-based), before jitter.
    public static func baseDelay(attempt: Int) -> TimeInterval {
        attempt < backoff.count ? backoff[attempt] : maximumDelay
    }

    /// `baseDelay` jittered by ±20%. `random` returns a value in 0..<1.
    public static func delay(attempt: Int, random: () -> Double) -> TimeInterval {
        let base = baseDelay(attempt: attempt)
        return base * (1 - jitter + 2 * jitter * random())
    }

    /// A request or check couldn't get through. Returns true if Jev just became unreachable.
    @discardableResult
    public mutating func recordFailure(now: Date, random: () -> Double = { Double.random(in: 0..<1) }) -> Bool {
        let wasReachable = isReachable
        if wasReachable {
            isReachable = false
            failedChecks = 0
        } else {
            failedChecks += 1
        }
        nextCheck = now + Self.delay(attempt: failedChecks, random: random)
        return wasReachable
    }

    /// Jev answered. Returns true if it had been unreachable (time to catch up).
    @discardableResult
    public mutating func recordSuccess() -> Bool {
        let wasUnreachable = !isReachable
        isReachable = true
        failedChecks = 0
        nextCheck = nil
        return wasUnreachable
    }

    /// macOS reported a network change (or the Mac woke). If Jev is unreachable and there's a
    /// network, check right away and start the backoff over.
    /// Losing the network counts as Jev being unreachable too, so getting it back triggers a
    /// check, and the check's success triggers catch-up.
    public mutating func networkChanged(hasNetwork: Bool, now: Date) {
        self.hasNetwork = hasNetwork
        failedChecks = 0
        if !hasNetwork {
            isReachable = false
            nextCheck = nil
        } else if !isReachable {
            nextCheck = now
        }
    }

    /// A background check is starting.
    public mutating func checkStarted(now: Date) {
        lastCheck = now
    }

    /// A link arrived while Jev is skipped: check now, unless one ran in the last 5 s.
    public func shouldCheckForLink(now: Date) -> Bool {
        guard hasNetwork, !isReachable else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.linkCheckMinimumGap
    }
}
