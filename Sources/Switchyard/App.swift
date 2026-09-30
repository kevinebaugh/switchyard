import AppKit
import Carbon
import RouterCore
import SwiftUI

@main
struct SwitchyardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = Router.shared

    init() {
        // Before anything reads settings: rehearsals and snapshots start from a clean slate.
        AppEnvironment.prepare()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(router)
                .environmentObject(HistoryStore.shared)
                .environmentObject(RuleStore.shared)
                .environmentObject(RuleUsageStore.shared)
                .environmentObject(ProfilesMonitor.shared)
                .environmentObject(AppSettings.shared)
        } label: {
            if router.attentionCount > 0 {
                Label("\(router.attentionCount)", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(nsImage: MenuBarGlyph.image)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Handle GetURL ourselves (instead of application(_:open:)) to learn which app sent the link.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let snapshotDirectory = AppEnvironment.snapshotDirectory {
            Snapshots.render(to: snapshotDirectory)
            NSApp.terminate(nil)
            return
        }

        Router.shared.start()
        if !AppSettings.shared.onboardingCompleted {
            OnboardingWindow.shared.show()
        } else {
            ensureDefaultBrowser()
        }
    }

    /// Opening Switchyard again (Alfred, Finder, Spotlight) while it's running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppSettings.shared.onboardingCompleted {
            ensureDefaultBrowser()
        }
        return true
    }

    /// Switchyard only works as the default browser, so opening it asks macOS to restore that
    /// if something else took over. macOS shows its own confirmation. Setup handles this step
    /// itself, and rehearsals never touch the real setting.
    private func ensureDefaultBrowser() {
        guard !AppEnvironment.isIsolated, !DefaultBrowser.isDefault else { return }
        Task { try? await DefaultBrowser.makeDefault() }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        Router.shared.handleIncoming(url, source: Self.sourceApp(senderPID: senderPID))
    }

    private static func sourceApp(senderPID: pid_t?) -> SourceApp? {
        let ignored: Set<String?> = [Bundle.main.bundleIdentifier, AppSettings.shared.browser.bundleIdentifier]
        var candidate: NSRunningApplication?
        if let senderPID, senderPID > 0,
           let sender = NSRunningApplication(processIdentifier: senderPID),
           sender.activationPolicy == .regular,
           !ignored.contains(sender.bundleIdentifier) {
            candidate = sender
        } else if let front = NSWorkspace.shared.frontmostApplication, !ignored.contains(front.bundleIdentifier) {
            // Links are usually clicked in whatever app is in front.
            candidate = front
        }
        guard let candidate, let bundleID = candidate.bundleIdentifier else { return nil }
        return SourceApp(bundleID: bundleID, name: candidate.localizedName ?? bundleID)
    }
}
