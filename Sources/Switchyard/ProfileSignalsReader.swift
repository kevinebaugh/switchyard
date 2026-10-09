import Foundation
import RouterCore
import SQLite3

/// Reads, on this Mac only, what each browser profile is signed in to and where it browses, so
/// setup can draft profile descriptions. Nothing here leaves the Mac; only the descriptions
/// the user keeps are sent to Jev.
enum ProfileSignalsReader {
    static let historyDays = 90

    static func signals(for profiles: [BrowserProfile], in browser: BrowserKind) -> [ProfileSignals] {
        profiles.map { profile in
            let folder = browser.profileFolder(profile)
            let rows = browser == .firefox ? firefoxHistoryRows(in: folder) : historyRows(in: folder)
            return ProfileSignals(
                name: profile.name,
                accounts: accounts(for: profile, in: folder),
                siteVisits: ProfileDescriber.siteVisits(from: rows)
            )
        }
    }

    // MARK: Accounts

    private struct Preferences: Decodable {
        struct Account: Decodable {
            let email: String?
            let hd: String?
        }

        let accountInfo: [Account]?

        enum CodingKeys: String, CodingKey {
            case accountInfo = "account_info"
        }
    }

    private static func accounts(for profile: BrowserProfile, in folder: URL) -> [ProfileAccount] {
        var accounts: [ProfileAccount] = profile.account.map { [$0] } ?? []
        let url = folder.appendingPathComponent("Preferences")
        if let data = try? Data(contentsOf: url),
           let preferences = try? JSONDecoder().decode(Preferences.self, from: data) {
            for account in preferences.accountInfo ?? [] {
                guard let email = account.email, !email.isEmpty else { continue }
                accounts.append(ProfileAccount(email: email, workspaceDomain: account.hd))
            }
        }
        var seen = Set<String>()
        return accounts.filter { seen.insert($0.email.lowercased()).inserted }
    }

    // MARK: History

    private static func historyRows(in folder: URL) -> [(url: String, visits: Int)] {
        // Chromium timestamps are microseconds since 1601-01-01.
        let cutoff = (Date().timeIntervalSince1970 - Double(historyDays) * 86_400 + 11_644_473_600) * 1_000_000
        return query(folder: folder,
                     sql: "SELECT url, visit_count FROM urls WHERE hidden = 0 AND last_visit_time > ?1",
                     parameter: Int64(cutoff))
    }

    /// Firefox keeps history in `places.sqlite`, with timestamps in microseconds since 1970.
    private static func firefoxHistoryRows(in folder: URL) -> [(url: String, visits: Int)] {
        let cutoff = (Date().timeIntervalSince1970 - Double(historyDays) * 86_400) * 1_000_000
        return query(folder: folder, file: "places.sqlite",
                     sql: "SELECT url, visit_count FROM moz_places WHERE hidden = 0 AND last_visit_date > ?1",
                     parameter: Int64(cutoff))
    }

    private static func query(folder: URL, file name: String = "History", sql: String, parameter: Int64) -> [(url: String, visits: Int)] {
        let file = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }

        // immutable=1: read Dia's live database without taking locks or touching its journal.
        var database: OpaquePointer?
        guard sqlite3_open_v2(file.absoluteString + "?immutable=1", &database,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, parameter)

        var rows: [(String, Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            rows.append((String(cString: text), Int(sqlite3_column_int64(statement, 1))))
        }
        return rows
    }
}
