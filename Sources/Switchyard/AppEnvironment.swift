import Foundation

/// Where Switchyard keeps its state, and which launch mode it's in.
///
/// - Normal: `UserDefaults.standard`, `~/Library/Application Support/Switchyard`, the real Keychain item.
/// - Rehearsal (`--rehearsal <dir>`): a throwaway settings suite, data directory and Keychain item,
///   wiped at every launch, so onboarding can be run again and again without touching real
///   rules, descriptions, history or the API key. System-wide state (default browser,
///   Automation permission) is still real.
/// - Snapshot (`--snapshot-onboarding <dir>`): renders every onboarding step to PNGs and quits.
enum AppEnvironment {
    private static let arguments = CommandLine.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static let rehearsalDirectory: URL? = value(after: "--rehearsal").map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let snapshotDirectory: URL? = value(after: "--snapshot-onboarding").map { URL(fileURLWithPath: $0, isDirectory: true) }

    static var isRehearsal: Bool { rehearsalDirectory != nil }
    static var isSnapshot: Bool { snapshotDirectory != nil }
    /// Isolated storage: rehearsals and snapshots never touch real state.
    static var isIsolated: Bool { isRehearsal || isSnapshot }

    private static let isolatedSuiteName = "com.kevinebaugh.switchyard.rehearsal"

    nonisolated(unsafe) static let defaults: UserDefaults = isIsolated
        ? UserDefaults(suiteName: isolatedSuiteName)!
        : .standard

    static var dataDirectory: URL {
        if let rehearsalDirectory { return rehearsalDirectory }
        if let snapshotDirectory { return snapshotDirectory.appendingPathComponent(".state", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Switchyard", isDirectory: true)
    }

    static var keychainAccount: String {
        isIsolated ? "typesafe-api-key.rehearsal" : "typesafe-api-key"
    }

    /// Start every isolated launch from a clean slate. Call before anything reads settings.
    static func prepare() {
        guard isIsolated else { return }
        defaults.removePersistentDomain(forName: isolatedSuiteName)
        try? FileManager.default.removeItem(at: dataDirectory)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        Keychain.saveAPIKey("")
    }
}
