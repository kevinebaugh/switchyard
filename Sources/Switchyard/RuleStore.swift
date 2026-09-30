import Foundation
import os
import RouterCore

private let log = Logger(subsystem: "dev.kev.Switchyard", category: "rules")

/// Rules live in a JSON file in the sync folder (iCloud Drive / Dropbox / local).
/// Every write re-reads the file and merges first, so edits from another Mac aren't lost.
@MainActor
final class RuleStore: ObservableObject {
    static let shared = RuleStore(location: AppSettings.shared.rulesLocation)

    @Published private(set) var ruleSet = RuleSet()
    @Published private(set) var lastError: String?
    private(set) var index = RuleIndex(rules: [])
    private var rulesByID: [UUID: Rule] = [:]
    private(set) var location: RulesLocation

    private var presenter: RulesFilePresenter?
    private var lastModified: Date?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(location: RulesLocation) {
        self.location = location
        attach()
    }

    var fileURL: URL { location.rulesFile }

    // MARK: Reading

    /// Cheap check (one stat) used on every routed link, in case the file presenter missed a sync.
    func reloadIfChangedOnDisk() {
        if modificationDate() != lastModified { reload() }
    }

    func reload() {
        let disk = readDisk()
        let merged = RuleSet.merge(ruleSet, disk)
        apply(merged)
        if merged != disk { write(merged) }
    }

    // MARK: Mutations

    @discardableResult
    func upsert(key: RuleKey, profileName: String, origin: RuleOrigin) -> Rule {
        mutate { $0.upsert(key: key, profileName: profileName, origin: origin, browser: browser) }
    }

    func update(_ rule: Rule) {
        mutate { $0.update(rule) }
    }

    func delete(id: UUID) {
        mutate { $0.delete(id: id) }
    }

    func renameProfile(from oldName: String, to newName: String) {
        mutate { $0.renameProfile(from: oldName, to: newName, browser: browser) }
    }

    /// The selected browser's rules (rules for other browsers stay in the file, untouched).
    var browserRules: [Rule] {
        ruleSet.liveRules(for: browser)
    }

    /// The selected browser changed: match its rules from now on.
    func browserChanged() {
        apply(ruleSet)
    }

    private var browser: BrowserKind { AppSettings.shared.browser }

    func rule(id: UUID) -> Rule? {
        rulesByID[id]
    }

    /// Move to another sync folder, carrying the current rules along (merged with whatever is there).
    func move(to newLocation: RulesLocation) {
        guard newLocation != location else { return }
        let current = RuleSet.merge(ruleSet, readDisk())
        detach()
        location = newLocation
        ruleSet = current
        attach()
    }

    private func mutate<T>(_ body: (inout RuleSet) -> T) -> T {
        var set = RuleSet.merge(ruleSet, readDisk())
        let result = body(&set)
        apply(set)
        write(set)
        return result
    }

    // MARK: File plumbing

    private func attach() {
        try? FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)

        let presenter = RulesFilePresenter(url: fileURL) { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
        reload()
        if !FileManager.default.fileExists(atPath: fileURL.path) { write(ruleSet) }
    }

    private func detach() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }

    private func apply(_ set: RuleSet) {
        if set != ruleSet { ruleSet = set }
        index = RuleIndex(rules: set.liveRules, browser: browser)
        rulesByID = Dictionary(set.rules.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func readDisk() -> RuleSet {
        var result = RuleSet()
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: fileURL, options: [], error: &coordinationError
        ) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            do {
                result = try Self.decoder.decode(RuleSet.self, from: data)
                lastError = nil
            } catch {
                lastError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                log.error("Couldn't decode rules: \(error.localizedDescription, privacy: .public)")
            }
        }
        lastModified = modificationDate()
        return result
    }

    private func write(_ set: RuleSet) {
        guard let data = try? Self.encoder.encode(set) else { return }
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: fileURL, options: .forReplacing, error: &coordinationError
        ) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                lastError = "Couldn't save rules: \(error.localizedDescription)"
            }
        }
        if let coordinationError { lastError = coordinationError.localizedDescription }
        lastModified = modificationDate()
    }
}

private final class RulesFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
    }

    func presentedItemDidChange() {
        onChange()
    }
}

/// Recent routings. Local to this Mac: full URLs never go to the sync folder.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 25

    @Published private(set) var records: [RoutingRecord] = []

    private let fileURL = AppEnvironment.dataDirectory.appendingPathComponent("history.json")
    private let saver = DebouncedSave(delay: .seconds(1))

    private init() {
        records = LocalJSONFile.read([RoutingRecord].self, from: fileURL) ?? []
    }

    func add(_ record: RoutingRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    func update(id: UUID, _ body: (inout RoutingRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        body(&records[index])
        save()
    }

    func record(id: UUID) -> RoutingRecord? {
        records.first { $0.id == id }
    }

    private func save() {
        saver.schedule { [weak self] in
            guard let self else { return }
            LocalJSONFile.write(self.records, to: self.fileURL)
        }
    }
}
