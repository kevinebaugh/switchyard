import Foundation
import RouterCore

/// The destinations links can open in: every enabled browser's profiles (Safari is one
/// destination). Each browser's profile list (`Local State`, Firefox's `profiles.ini` and profile
/// group database) is watched, and re-read when it changes.
///
/// The rest of the app names a destination by its label: with one browser that's just the
/// profile name, exactly as before Switchyard 2; with several it's "Firefox · Personal". This
/// type converts between labels and destinations.
@MainActor
final class ProfilesMonitor: ObservableObject {
    static let shared = ProfilesMonitor()

    /// Every destination's profile, renamed to its label (and given a unique `directory`), for views.
    @Published private(set) var profiles: [BrowserProfile] = []
    @Published private(set) var destinations: [Destination] = []
    /// Lowercased labels (rebuilt only when destinations change).
    private(set) var availableNames: Set<String> = []
    /// `Destination.id`s, for rule matching.
    private(set) var availableDestinationIDs: Set<String> = []

    private var browsers: [BrowserKind]
    private var sources: [BrowserKind: BrowserProfileSource] = [:]
    /// Label → (destination, the browser's own profile).
    private var byLabel: [String: (destination: Destination, profile: BrowserProfile)] = [:]

    /// Called with (browser, old name, new name) when a browser renames a profile.
    var onRename: ((BrowserKind, String, String) -> Void)?

    private init() {
        browsers = AppSettings.shared.browsers
        rebuildSources()
        refresh()
    }

    var names: [String] { profiles.map(\.name) }
    var isMultiBrowser: Bool { browsers.count > 1 }

    // MARK: Browsers

    /// Follow a different set of browsers (setup, Settings).
    func setBrowsers(_ browsers: [BrowserKind]) {
        guard browsers != self.browsers else { return }
        self.browsers = browsers
        rebuildSources()
        refresh()
    }

    /// Follow one browser (setup's single-browser path).
    func switchTo(_ browser: BrowserKind) {
        setBrowsers([browser])
    }

    private func rebuildSources() {
        for (kind, source) in sources where !browsers.contains(kind) {
            source.stop()
            sources[kind] = nil
        }
        for kind in browsers where sources[kind] == nil {
            let source = BrowserProfileSource(browser: kind)
            source.onChange = { [weak self] in self?.publish() }
            source.onRename = { [weak self] old, new in self?.onRename?(kind, old, new) }
            sources[kind] = source
        }
    }

    @discardableResult
    func refresh() -> [BrowserProfile] {
        for kind in browsers { sources[kind]?.refresh() }
        publish()
        return profiles
    }

    /// Ask a browser for its visible profile order (Dia, once Automation is allowed).
    func refreshVisibleOrder(using adapter: BrowserAdapter) async {
        await sources[adapter.kind]?.refreshVisibleOrder(using: adapter)
        publish()
    }

    private func publish() {
        let multi = isMultiBrowser
        var entries: [(Destination, BrowserProfile, String)] = []
        for kind in browsers {
            for profile in sources[kind]?.profiles ?? [] {
                let destination = Destination(browser: kind, profile: profile.name)
                entries.append((destination, profile, destination.label(multiBrowser: multi)))
            }
        }
        let labelled = entries.map { destination, profile, label in
            BrowserProfile(directory: destination.id, name: label, colorARGB: profile.colorARGB, account: profile.account)
        }
        byLabel = Dictionary(entries.map { ($0.2.lowercased(), ($0.0, $0.1)) }, uniquingKeysWith: { first, _ in first })
        let newDestinations = entries.map(\.0)
        if newDestinations != destinations { destinations = newDestinations }
        if labelled != profiles { profiles = labelled }
        availableNames = Set(labelled.map { $0.name.lowercased() })
        availableDestinationIDs = Set(newDestinations.map(\.id))
    }

    // MARK: Labels and destinations

    /// The destination a label names. Also accepts the original browser's plain profile names
    /// ("Personal" for "Dia · Personal"), which rules and settings from 1.x use.
    func destination(named name: String) -> Destination? {
        entry(named: name)?.destination
    }

    /// The browser and its own profile for a label, for opening a link.
    func target(named name: String) -> (destination: Destination, profile: BrowserProfile)? {
        entry(named: name)
    }

    func label(for destination: Destination) -> String {
        destination.label(multiBrowser: isMultiBrowser)
    }

    /// For views: the labelled profile (colour, account) for a label.
    func profile(named name: String) -> BrowserProfile? {
        guard let destination = destination(named: name) else { return nil }
        return profiles.first { $0.directory == destination.id }
    }

    /// The canonical label for a name (case-insensitive, and accepting the original browser's
    /// plain profile names), or nil if no destination has it.
    func profileName(matching name: String) -> String? {
        destination(named: name).map(label(for:))
    }

    private func entry(named name: String) -> (destination: Destination, profile: BrowserProfile)? {
        if let found = byLabel[name.lowercased()] { return found }
        guard let original = browsers.first else { return nil }
        return byLabel[Destination(browser: original, profile: name).label(multiBrowser: isMultiBrowser).lowercased()]
    }
}

/// One browser's profiles, re-read whenever its profile list changes (checked by mtime, so it's
/// cheap enough to call on every routed link), and watched so changes show up straight away.
@MainActor
private final class BrowserProfileSource {
    let browser: BrowserKind
    private(set) var profiles: [BrowserProfile] = []
    var onChange: (() -> Void)?
    var onRename: ((String, String) -> Void)?

    private var lastModified: Date?
    /// Firefox's profile group database, once profiles.ini has named it.
    private var firefoxDatabase: URL?
    private var listed: [BrowserProfile] = []
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var watchedFolders: [URL] = []
    private var pendingRefresh: Task<Void, Never>?

    init(browser: BrowserKind) {
        self.browser = browser
        if !browser.hasProfiles {
            // Safari: one destination, nothing to read.
            profiles = [BrowserProfile(directory: "", name: browser.displayName)]
        }
    }

    func stop() {
        watchers.forEach { $0.cancel() }
        watchers = []
        watchedFolders = []
    }

    func refresh() {
        guard browser.hasProfiles else { return }
        // Chrome's folder is protected; don't touch it (and trigger the macOS prompt) before
        // setup has asked for access.
        guard Browsers.adapter(for: browser).canReadProfilesSilently else { return }
        defer { watch() }

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
        guard modified != lastModified || profiles.isEmpty else { return }
        lastModified = modified

        guard let data = try? Data(contentsOf: url) else { return }
        var group: [FirefoxProfiles.GroupProfile] = []
        if browser == .firefox {
            firefoxDatabase = FirefoxGroupReader.databaseFile(profilesINI: String(decoding: data, as: UTF8.self), browser: browser)
            group = firefoxDatabase.map(FirefoxGroupReader.profiles(in:)) ?? []
        }
        let fresh = browser.profiles(fromProfileList: data, firefoxGroup: group)
        guard !fresh.isEmpty else { return }

        for rename in ChromiumLocalState.renames(from: listed, to: fresh) {
            onRename?(rename.from, rename.to)
        }
        listed = fresh
        sort()
    }

    // MARK: Visible order (Dia)

    private var visibleOrderKey: String {
        browser == .dia ? SettingsKey.diaProfileOrder.rawValue : SettingsKey.profileOrder(browser.rawValue)
    }

    private var visibleOrder: [String] {
        get { AppEnvironment.defaults.stringArray(forKey: visibleOrderKey) ?? [] }
        set { AppEnvironment.defaults.set(newValue, forKey: visibleOrderKey) }
    }

    func refreshVisibleOrder(using adapter: BrowserAdapter) async {
        guard let order = await adapter.visibleProfileOrder(), !order.isEmpty, order != visibleOrder else { return }
        visibleOrder = order
        sort()
    }

    private func sort() {
        let sorted = ChromiumLocalState.sorted(listed, visibleOrder: visibleOrder)
        guard sorted != profiles else { return }
        profiles = sorted
        onChange?()
    }

    // MARK: Watching for new and renamed profiles

    /// Folder watchers on the profile list, so a profile added or renamed in the browser shows up
    /// as soon as the browser saves it (Dia and Chrome replace `Local State` rather than editing
    /// it, so the folder is watched, not the file).
    private func watch() {
        var folders = [browser.profileListFile().deletingLastPathComponent()]
        if let firefoxDatabase { folders.append(firefoxDatabase.deletingLastPathComponent()) }
        guard folders != watchedFolders else { return }
        stop()
        watchedFolders = folders
        for folder in folders {
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers.append(source)
        }
    }

    /// Browsers write their data folder in bursts; settle for a moment, then re-read (which is a
    /// no-op unless the profile list itself changed).
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
