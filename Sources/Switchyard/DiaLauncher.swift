import AppKit
import Carbon

enum DiaLaunchError: LocalizedError {
    case diaNotInstalled
    case noWindow
    case profileNotFound(String)
    case automationDenied
    case script(String)

    var errorDescription: String? {
        switch self {
        case .diaNotInstalled: "Dia is not installed."
        case .noWindow: "Dia didn't open a window in time."
        case let .profileNotFound(name): "Dia has no profile named “\(name)”."
        case .automationDenied: "Allow Switchyard to control Dia in System Settings → Privacy & Security → Automation."
        case let .script(message): message
        }
    }
}

enum AutomationPermission: Equatable {
    case granted
    case notDetermined
    case denied
    case diaNotRunning
    case unknown
}

/// Opens a URL in a specific Dia profile through Dia's AppleScript dictionary:
/// `make new tab at end of tabs of <profile>` then `focus` it. No Accessibility
/// permission or keyboard-shortcut alignment needed, only a one-time Automation grant.
final class DiaLauncher: @unchecked Sendable {
    static let bundleIdentifier = "company.thebrowser.dia"

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
    private let queue = DispatchQueue(label: "DiaLauncher.applescript", qos: .userInteractive)
    private var compiledScript: NSAppleScript?

    var diaApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
    }

    var isDiaRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    /// Start Dia early (e.g. while Jev is thinking) so the open doesn't wait on a cold launch.
    func warmUp() {
        guard !isDiaRunning, let diaApplicationURL else { return }
        NSWorkspace.shared.openApplication(at: diaApplicationURL, configuration: Self.configuration(activates: false))
    }

    /// Launch Dia if needed and wait (up to ~5s) until it's running.
    func ensureRunning() async {
        guard !isDiaRunning else { return }
        warmUp()
        for _ in 0..<20 where !isDiaRunning {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func configuration(activates: Bool) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return configuration
    }

    /// Whether macOS lets Switchyard send Apple Events to Dia. With `ask`, shows the
    /// one-time consent prompt if needed (blocks until answered, so it runs off the main thread).
    func automationPermission(ask: Bool) async -> AutomationPermission {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
                let status = AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask
                )
                let result: AutomationPermission = switch status {
                case noErr: .granted
                case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
                case OSStatus(errAEEventNotPermitted): .denied
                case OSStatus(procNotFound): .diaNotRunning
                default: .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Profile names in the order Dia shows them. Only asks when Automation is already
    /// allowed, so it never triggers the consent prompt by surprise.
    func visibleProfileOrder() async -> [String]? {
        guard isDiaRunning, await automationPermission(ask: false) == .granted else { return nil }
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

    func open(_ url: URL, inProfile profileName: String) async throws {
        guard let diaApplicationURL else { throw DiaLaunchError.diaNotInstalled }

        // A cold or window-less Dia needs a moment; retry for up to ~6s.
        for attempt in 0..<20 {
            do {
                try await run(profileName: profileName, url: url)
                return
            } catch DiaLaunchError.noWindow {
                if attempt == 0 {
                    // Launching (or reopening) Dia makes it create a window.
                    _ = try? await NSWorkspace.shared.openApplication(at: diaApplicationURL, configuration: Self.configuration(activates: true))
                }
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        throw DiaLaunchError.noWindow
    }

    /// Last resort when a profile can't be targeted: hand the URL to Dia as-is.
    func openInCurrentProfile(_ url: URL) async throws {
        guard let diaApplicationURL else { throw DiaLaunchError.diaNotInstalled }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: diaApplicationURL, configuration: Self.configuration(activates: true))
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
            throw DiaLaunchError.script("Could not create the Dia AppleScript.")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            throw DiaLaunchError.script("Could not compile the Dia AppleScript: \(errorInfo ?? [:])")
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
        case 9001, -600, -609: throw DiaLaunchError.noWindow // no window / app not running / connection lost
        case 9002: throw DiaLaunchError.profileNotFound(profileName)
        case -1743: throw DiaLaunchError.automationDenied
        default: throw DiaLaunchError.script("\(message) (\(number))")
        }
    }
}
