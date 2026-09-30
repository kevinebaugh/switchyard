import Foundation
import RouterCore

/// When each rule last decided a link, on this Mac only (so routing never touches the synced
/// rules file). Used to sort the Rules tab.
@MainActor
final class RuleUsageStore: ObservableObject {
    static let shared = RuleUsageStore()

    @Published private(set) var usage: [UUID: RuleUsage] = [:]

    private let fileURL = AppEnvironment.dataDirectory.appendingPathComponent("rule-usage.json")
    private let saver = DebouncedSave(delay: .seconds(2))

    private init() {
        usage = LocalJSONFile.read([UUID: RuleUsage].self, from: fileURL) ?? [:]
    }

    func recordUse(of ruleID: UUID, at date: Date = Date()) {
        var entry = usage[ruleID] ?? RuleUsage(lastUsed: date, count: 0)
        entry.lastUsed = date
        entry.count += 1
        usage[ruleID] = entry
        saver.schedule { [weak self] in
            guard let self else { return }
            LocalJSONFile.write(self.usage, to: self.fileURL)
        }
    }
}
