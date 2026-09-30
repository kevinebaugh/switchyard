import AppKit
import ServiceManagement

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return false
        }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static var currentHandlerName: String? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?
            .deletingPathExtension().lastPathComponent
    }

    /// macOS asks the user to confirm the change.
    static func makeDefault() async throws {
        for scheme in ["http", "https"] {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Rehearsals and snapshots never change the real login item.
    static func set(enabled: Bool) throws {
        guard !AppEnvironment.isIsolated else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
