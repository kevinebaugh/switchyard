import Foundation
import RouterCore

/// The selected browser's profiles, re-read whenever its profile list (`Local State`, or
/// Firefox's `profiles.ini`) changes (checked by mtime, so it's cheap enough to call on every
/// routed link).
@MainActor
final class ProfilesMonitor: ObservableObject {
    static let shared = ProfilesMonitor()

    @Published private(set) var profiles: [BrowserProfile] = []
    /// Lowercased names, for rule matching (rebuilt only when profiles change).
    private(set) var availableNames: Set<String> = []

    private var browser: BrowserKind
    private var lastModified: Date?
    /// Firefox's profile group database, once profiles.ini has named it.
    private var firefoxDatabase: URL?
    private var localStateProfiles: [BrowserProfile] = []

    /// Called with (old name, new name) when the browser renames a profile.
    var onRename: ((String, String) -> Void)?

    private init() {
        browser = AppSettings.shared.browser
        refresh()
    }

    var names: [String] { profiles.map(\.name) }

    /// The browser's own profile order, when it can report one (Dia's scripting interface
    /// can; Local State doesn't store it). Remembered per browser.
    private var visibleOrderKey: String {
        browser == .dia ? "diaProfileOrder" : "profileOrder.\(browser.rawValue)"
    }

    private var visibleOrder: [String] {
        get { AppEnvironment.defaults.stringArray(forKey: visibleOrderKey) ?? [] }
        set { AppEnvironment.defaults.set(newValue, forKey: visibleOrderKey) }
    }

    /// Follow a different browser (setup's browser step).
    func switchTo(_ browser: BrowserKind) {
        guard browser != self.browser else { return }
        self.browser = browser
        lastModified = nil
        firefoxDatabase = nil
        localStateProfiles = []
        profiles = []
        availableNames = []
        refresh()
    }

    @discardableResult
    func refresh() -> [BrowserProfile] {
        // Chrome's folder is protected; don't touch it (and trigger the macOS prompt) before
        // setup has asked for access.
        guard Browsers.adapter(for: browser).canReadProfilesSilently else { return profiles }

        let url = browser.profileListFile()
        // Firefox's profile manager keeps names in its group database (and its WAL), so a rename
        // there changes those files, not profiles.ini.
        var watched = [url]
        if browser == .firefox, let database = firefoxDatabase {
            watched += [database, URL(fileURLWithPath: database.path + "-wal")]
        }
        let modified = watched
            .compactMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
            .max()
        guard modified != lastModified || profiles.isEmpty else { return profiles }
        lastModified = modified

        guard let data = try? Data(contentsOf: url) else { return profiles }
        var group: [FirefoxProfiles.GroupProfile] = []
        if browser == .firefox {
            firefoxDatabase = FirefoxGroupReader.databaseFile(profilesINI: String(decoding: data, as: UTF8.self), browser: browser)
            group = firefoxDatabase.map(FirefoxGroupReader.profiles(in:)) ?? []
        }
        let fresh = browser.profiles(fromProfileList: data, firefoxGroup: group)
        guard !fresh.isEmpty else { return profiles }

        for rename in ChromiumLocalState.renames(from: localStateProfiles, to: fresh) {
            onRename?(rename.from, rename.to)
        }
        localStateProfiles = fresh
        publish()
        return profiles
    }

    /// Ask the browser for its visible order (Dia only, and only once Automation is allowed).
    func refreshVisibleOrder(using adapter: BrowserAdapter) async {
        guard adapter.kind == browser,
              let order = await adapter.visibleProfileOrder(), !order.isEmpty, order != visibleOrder else { return }
        visibleOrder = order
        publish()
    }

    private func publish() {
        let sorted = ChromiumLocalState.sorted(localStateProfiles, visibleOrder: visibleOrder)
        guard sorted != profiles else { return }
        profiles = sorted
        availableNames = Set(sorted.map { $0.name.lowercased() })
    }

    func profile(named name: String) -> BrowserProfile? {
        profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func profileName(matching name: String) -> String? {
        profile(named: name)?.name
    }
}
