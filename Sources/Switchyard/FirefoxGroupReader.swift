import Foundation
import RouterCore
import SQLite3

/// Reads the `Profiles` table of Firefox's profile group database (Firefox's profile manager).
/// Read-only; Firefox keeps the database open, so this reads through its WAL when it can and
/// falls back to the main file alone.
enum FirefoxGroupReader {
    /// The database, if `profiles.ini` names one.
    static func databaseFile(profilesINI text: String, browser: BrowserKind) -> URL? {
        FirefoxProfiles.groupDatabaseName(fromINI: text).map {
            browser.userDataDirectory().appendingPathComponent("Profile Groups", isDirectory: true).appendingPathComponent($0)
        }
    }

    static func profiles(in file: URL) -> [FirefoxProfiles.GroupProfile] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        for options in ["?mode=ro", "?immutable=1"] {
            if let rows = query(file.absoluteString + options) { return rows }
        }
        return []
    }

    private static func query(_ uri: String) -> [FirefoxProfiles.GroupProfile]? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT path, name, themeFg, themeBg FROM Profiles ORDER BY id", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var rows: [FirefoxProfiles.GroupProfile] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return nil }
            guard let path = text(0), let name = text(1), !path.isEmpty, !name.isEmpty else { continue }
            rows.append(.init(path: path, name: name, themeForeground: text(2), themeBackground: text(3)))
        }
        return rows
    }
}
