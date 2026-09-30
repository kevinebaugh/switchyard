import Foundation
import RouterCore

/// Dia's profiles, re-read whenever `Local State` changes (checked by mtime, so it's
/// cheap enough to call on every routed link).
@MainActor
final class DiaProfilesMonitor: ObservableObject {
    static let shared = DiaProfilesMonitor()

    @Published private(set) var profiles: [DiaProfile] = []
    private var lastModified: Date?
    private var localStateProfiles: [DiaProfile] = []

    /// Dia's own profile order, from its scripting interface (Local State doesn't store it).
    private var visibleOrder: [String] = AppEnvironment.defaults.stringArray(forKey: "diaProfileOrder") ?? [] {
        didSet { AppEnvironment.defaults.set(visibleOrder, forKey: "diaProfileOrder") }
    }

    /// Called with (old name, new name) when Dia renames a profile.
    var onRename: ((String, String) -> Void)?

    private init() {
        refresh()
    }

    var names: [String] { profiles.map(\.name) }

    /// Lowercased names, for rule matching (rebuilt only when profiles change).
    private(set) var availableNames: Set<String> = []

    @discardableResult
    func refresh() -> [DiaProfile] {
        let url = DiaLocalState.fileURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard modified != lastModified || profiles.isEmpty else { return profiles }
        lastModified = modified

        guard let data = try? Data(contentsOf: url) else { return profiles }
        let fresh = DiaLocalState.profiles(from: data)
        guard !fresh.isEmpty else { return profiles }

        for rename in DiaLocalState.renames(from: localStateProfiles, to: fresh) {
            onRename?(rename.from, rename.to)
        }
        localStateProfiles = fresh
        publish()
        return profiles
    }

    /// Ask Dia for its visible order (only if Automation is already allowed).
    func refreshVisibleOrder(using launcher: DiaLauncher) async {
        guard let order = await launcher.visibleProfileOrder(), !order.isEmpty, order != visibleOrder else { return }
        visibleOrder = order
        publish()
    }

    private func publish() {
        let sorted = DiaLocalState.sorted(localStateProfiles, visibleOrder: visibleOrder)
        guard sorted != profiles else { return }
        profiles = sorted
        availableNames = Set(sorted.map { $0.name.lowercased() })
    }

    func profile(named name: String) -> DiaProfile? {
        profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func profileName(matching name: String) -> String? {
        profile(named: name)?.name
    }
}
