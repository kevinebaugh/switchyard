import AppKit
import Carbon
import RouterCore

enum BrowserLaunchError: LocalizedError {
    case notInstalled(BrowserKind)
    case noWindow(BrowserKind)
    case profileNotFound(String, BrowserKind)
    case automationDenied
    case script(String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(browser): "\(browser.displayName) is not installed."
        case let .noWindow(browser): "\(browser.displayName) didn't open a window in time."
        case let .profileNotFound(name, browser): "\(browser.displayName) has no profile named “\(name)”."
        case .automationDenied: "Allow Switchyard to control Dia in System Settings → Privacy & Security → Automation."
        case let .script(message): message
        }
    }
}

/// What macOS lets Switchyard do with the browser: Automation for Dia, reading the profile
/// list ("data from other apps") for Chrome and friends.
enum BrowserPermission: Equatable {
    case granted
    case notDetermined
    case denied
    case browserNotRunning
    case unknown
}

/// Everything browser-specific: finding it, what permission it needs, and opening a link in
/// one of its profiles. Rules, Jev, sync and setup don't care which browser this is.
protocol BrowserAdapter: AnyObject, Sendable {
    var kind: BrowserKind { get }
    /// Whether the profile list can be read without showing a macOS prompt.
    var canReadProfilesSilently: Bool { get }
    /// Compile or cache whatever the first open needs.
    func prepare()
    func permission(ask: Bool) async -> BrowserPermission
    /// Profile names in the order the browser shows them, when it can say (Dia can).
    func visibleProfileOrder() async -> [String]?
    func open(_ url: URL, in profile: BrowserProfile) async throws
}

extension BrowserAdapter {
    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleIdentifier)
    }

    var isInstalled: Bool { applicationURL != nil }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier).isEmpty
    }

    /// Start the browser early (e.g. while Jev is thinking) so the open doesn't wait on a cold launch.
    func warmUp() {
        guard !isRunning, let applicationURL else { return }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: .activating(false))
    }

    /// Launch the browser if needed and wait (up to ~5s) until it's running.
    func ensureRunning() async {
        guard !isRunning else { return }
        warmUp()
        for _ in 0..<20 where !isRunning {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Last resort when a profile can't be targeted: hand the URL to the browser as-is.
    func openInCurrentProfile(_ url: URL) async throws {
        guard let applicationURL else { throw BrowserLaunchError.notInstalled(kind) }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: .activating(true))
    }
}

extension NSWorkspace.OpenConfiguration {
    static func activating(_ activates: Bool) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return configuration
    }
}

enum Browsers {
    private static let dia = DiaAdapter()
    private static let launching = Dictionary(uniqueKeysWithValues: BrowserKind.allCases
        .filter(\.opensWithArguments)
        .map { ($0, LaunchArgumentsAdapter(kind: $0)) })

    static func adapter(for kind: BrowserKind) -> BrowserAdapter {
        kind == .dia ? dia : launching[kind]!
    }

    /// Supported browsers installed on this Mac, verified ones first.
    static var installed: [BrowserKind] {
        BrowserKind.allCases.filter { adapter(for: $0).isInstalled }
    }
}

/// Dia: opens a tab in a profile through Dia's AppleScript dictionary
/// (`make new tab at end of tabs of <profile>`, then `focus`). Dia ignores Chromium's
/// `--profile-directory`, so this needs a one-time Automation grant, but no Accessibility
/// permission or keyboard-shortcut alignment.
final class DiaAdapter: BrowserAdapter, @unchecked Sendable {
    let kind = BrowserKind.dia
    let canReadProfilesSilently = true

    private static let source = """
        on openurl(profileName, theURL)
            tell application id "company.thebrowser.dia"
                if (count of windows) is 0 then error "Dia has no windows" number 9001
                try
                    set targetProfile to first profile of front window whose name is profileName
                on error
                    error "No Dia profile named " & profileName number 9002
                end try
                set newTab to make new tab at end of tabs of targetProfile with properties {URL:theURL}
                focus newTab
                activate
            end tell
        end openurl

        on profilenames()
            tell application id "company.thebrowser.dia"
                if (count of windows) is 0 then error "Dia has no windows" number 9001
                return name of profiles of front window
            end tell
        end profilenames
        """

    /// NSAppleScript isn't thread-safe; it's only touched on this queue.
    private let queue = DispatchQueue(label: "DiaAdapter.applescript", qos: .userInteractive)
    private var compiledScript: NSAppleScript?

    /// Whether macOS lets Switchyard send Apple Events to Dia. With `ask`, shows the
    /// one-time consent prompt if needed (blocks until answered, so it runs off the main thread).
    func permission(ask: Bool) async -> BrowserPermission {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: BrowserKind.dia.bundleIdentifier)
                let status = AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask
                )
                let result: BrowserPermission = switch status {
                case noErr: .granted
                case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
                case OSStatus(errAEEventNotPermitted): .denied
                case OSStatus(procNotFound): .browserNotRunning
                default: .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Profile names in the order Dia shows them. Only asks when Automation is already
    /// allowed, so it never triggers the consent prompt by surprise.
    func visibleProfileOrder() async -> [String]? {
        guard isRunning, await permission(ask: false) == .granted else { return nil }
        return try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            queue.async {
                do {
                    let result = try self.invoke(handler: "profilenames", arguments: [])
                    let names = (0..<result.numberOfItems).compactMap { result.atIndex($0 + 1)?.stringValue }
                    continuation.resume(returning: names)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Compile the script ahead of the first link.
    func prepare() {
        queue.async { _ = try? self.script() }
    }

    func open(_ url: URL, in profile: BrowserProfile) async throws {
        guard let applicationURL else { throw BrowserLaunchError.notInstalled(kind) }
        let profileName = profile.name

        // A cold or window-less Dia needs a moment; retry for up to ~6s.
        for attempt in 0..<20 {
            do {
                try await run(profileName: profileName, url: url)
                return
            } catch BrowserLaunchError.noWindow {
                if attempt == 0 {
                    // Launching (or reopening) Dia makes it create a window.
                    _ = try? await NSWorkspace.shared.openApplication(at: applicationURL, configuration: .activating(true))
                }
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        throw BrowserLaunchError.noWindow(kind)
    }

    private func run(profileName: String, url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.invoke(handler: "openurl", arguments: [profileName, url.absoluteString])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func script() throws -> NSAppleScript {
        if let compiledScript { return compiledScript }
        guard let script = NSAppleScript(source: Self.source) else {
            throw BrowserLaunchError.script("Could not create the Dia AppleScript.")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            throw BrowserLaunchError.script("Could not compile the Dia AppleScript: \(errorInfo ?? [:])")
        }
        compiledScript = script
        return script
    }

    @discardableResult
    private func invoke(handler: String, arguments: [String]) throws -> NSAppleEventDescriptor {
        let script = try script()

        // Call the handler with typed arguments: no string interpolation into source.
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            parameters.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }

        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))

        var errorInfo: NSDictionary?
        let result = script.executeAppleEvent(event, error: &errorInfo)
        guard let errorInfo else { return result }
        let profileName = arguments.first ?? ""

        let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        switch number {
        case 9001, -600, -609: throw BrowserLaunchError.noWindow(kind) // no window / app not running / connection lost
        case 9002: throw BrowserLaunchError.profileNotFound(profileName, kind)
        case -1743: throw BrowserLaunchError.automationDenied
        default: throw BrowserLaunchError.script("\(message) (\(number))")
        }
    }
}

/// Chrome, Brave, Edge, Vivaldi and Firefox: a new launch with the profile in its arguments
/// (`--profile-directory=<dir>`, or Firefox's `-profile <path> -new-tab`), which the browser
/// hands to its already-running instance. No Automation needed. The profile list lives in the
/// browser's data folder, which macOS protects ("data from other apps"), so reading it is this
/// adapter's permission.
final class LaunchArgumentsAdapter: BrowserAdapter, @unchecked Sendable {
    let kind: BrowserKind

    init(kind: BrowserKind) {
        self.kind = kind
    }

    private var askedKey: String { "askedDataAccess.\(kind.rawValue)" }

    var canReadProfilesSilently: Bool {
        AppEnvironment.defaults.bool(forKey: askedKey)
    }

    func prepare() {}

    func visibleProfileOrder() async -> [String]? { nil }

    /// Reading the profile list is the permission. It's only attempted after setup asked once,
    /// so a status check never shows the macOS prompt by surprise.
    func permission(ask: Bool) async -> BrowserPermission {
        let defaults = AppEnvironment.defaults
        guard ask || defaults.bool(forKey: askedKey) else { return .notDetermined }
        if ask { defaults.set(true, forKey: askedKey) }

        let file = kind.profileListFile()
        return await Task.detached(priority: .userInitiated) {
            do {
                _ = try Data(contentsOf: file)
                return .granted
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                return .denied
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // Never launched, so no profiles yet; reading isn't what's blocked.
                return .granted
            } catch {
                return (error as NSError).code == Int(EPERM) ? .denied : .unknown
            }
        }.value
    }

    func open(_ url: URL, in profile: BrowserProfile) async throws {
        guard let applicationURL else { throw BrowserLaunchError.notInstalled(kind) }
        let configuration = NSWorkspace.OpenConfiguration.activating(true)
        configuration.createsNewApplicationInstance = true   // `open -n`: the new process hands off and exits
        configuration.arguments = kind.launchArguments(opening: url, in: profile)
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }
}
