import Foundation

/// Which links to ask Jev about once it can be reached again: those that fell back because it
/// couldn't be, from the last day, one request per host and path, at most 25.
public enum OfflineCatchUp {
    public static let maximumAge: TimeInterval = 24 * 60 * 60
    public static let maximumRequests = 25

    public struct Item: Equatable, Sendable {
        /// The newest record for this host and path; its URL and source app are what's asked about.
        public let representative: RoutingRecord
        /// Every record the answer applies to (the representative included).
        public let recordIDs: [UUID]
    }

    /// - Parameter records: newest first, as in history.
    public static func items(from records: [RoutingRecord], now: Date) -> [Item] {
        var order: [String] = []
        var groups: [String: (representative: RoutingRecord, ids: [UUID])] = [:]
        for record in records where record.isAwaitingCatchUp && now.timeIntervalSince(record.date) <= maximumAge {
            let key = (record.url.host?.lowercased() ?? "") + record.url.path
            if groups[key] == nil {
                guard order.count < maximumRequests else { continue }
                order.append(key)
                groups[key] = (record, [])
            }
            groups[key]?.ids.append(record.id)
        }
        return order.compactMap { key in groups[key].map { Item(representative: $0.representative, recordIDs: $0.ids) } }
    }
}
