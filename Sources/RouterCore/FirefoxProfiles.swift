import Foundation

/// Reads Firefox's profiles. Two setups exist:
///
/// - **Firefox's profile manager** (Firefox's profile menu with names, icons and theme colours):
///   a `[ProfileN]` in `profiles.ini` carries a `StoreID`, naming a database at
///   `Profile Groups/<StoreID>.sqlite` whose `Profiles` table lists every profile in the group
///   (`path` relative to the Firefox folder, `name`, `themeFg`/`themeBg` as `rgb(r,g,b)`). Newer
///   profiles exist only there. Switchyard shows exactly that group, as Firefox's menu does.
/// - **Classic profiles:** each `[ProfileN]` has `Name`, `Path` and `IsRelative`. Firefox also
///   keeps an unused `default` profile for older versions next to `default-release`; it's hidden.
///
/// A profile's `directory` is its full path, which is what `-profile` takes, so names never reach
/// the command line.
public enum FirefoxProfiles {
    /// A row of the profile group's `Profiles` table.
    public struct GroupProfile: Equatable, Sendable {
        public let path: String
        public let name: String
        public let themeForeground: String?
        public let themeBackground: String?

        public init(path: String, name: String, themeForeground: String? = nil, themeBackground: String? = nil) {
            self.path = path
            self.name = name
            self.themeForeground = themeForeground
            self.themeBackground = themeBackground
        }
    }

    /// The profile group database's file name, if Firefox's profile manager is in use.
    public static func groupDatabaseName(fromINI text: String) -> String? {
        sections(text)
            .lazy
            .compactMap { $0.values["StoreID"] }
            .first { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }
            .map { "\($0).sqlite" }
    }

    public static func profiles(fromINI text: String, root: URL, group: [GroupProfile] = []) -> [BrowserProfile] {
        guard group.isEmpty else {
            return group.map { row in
                BrowserProfile(directory: fullPath(row.path, isRelative: !row.path.hasPrefix("/"), root: root),
                               name: row.name,
                               colorARGB: themeColor(foreground: row.themeForeground, background: row.themeBackground))
            }
        }

        let classic = sections(text)
            .compactMap { header, values -> (index: Int, profile: BrowserProfile)? in
                guard header.hasPrefix("Profile"), let index = Int(header.dropFirst("Profile".count)),
                      let name = values["Name"], !name.isEmpty,
                      let path = values["Path"], !path.isEmpty else { return nil }
                let isRelative = values["IsRelative"].map { $0 != "0" } ?? !path.hasPrefix("/")
                return (index, BrowserProfile(directory: fullPath(path, isRelative: isRelative, root: root), name: name))
            }
            .sorted { $0.index < $1.index }
            .map(\.profile)

        // Firefox creates "default" (for older Firefox versions) beside "default-release" and
        // never opens it; its own menus don't list it either.
        let hasRelease = classic.contains { $0.name == "default-release" }
        return classic.filter { !(hasRelease && $0.name == "default") }
    }

    /// A profile's colour from its Firefox theme. The foreground is the distinctive one (the
    /// background is a near-white tint); greys (the default theme) get Switchyard's palette.
    static func themeColor(foreground: String?, background: String?) -> UInt32? {
        for value in [foreground, background] {
            guard let (r, g, b) = value.flatMap(rgb) else { continue }
            let spread = max(r, g, b) - min(r, g, b)
            if spread >= 24 { return 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
        }
        return nil
    }

    /// `rgb(62,41,118)` or `rgba(62, 41, 118, 1)`.
    static func rgb(_ text: String) -> (Int, Int, Int)? {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        let parts = text[text.index(after: open)..<close].split(separator: ",")
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3, let r = parts[0], let g = parts[1], let b = parts[2],
              [r, g, b].allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (r, g, b)
    }

    private static func fullPath(_ path: String, isRelative: Bool, root: URL) -> String {
        (isRelative ? root.appendingPathComponent(path, isDirectory: true) : URL(fileURLWithPath: path, isDirectory: true))
            .standardizedFileURL.path
    }

    /// `[Header]` sections and their `key=value` lines, in file order. Comments (`;`, `#`) and
    /// blank lines are skipped.
    static func sections(_ text: String) -> [(header: String, values: [String: String])] {
        var result: [(String, [String: String])] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                result.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !result.isEmpty {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                result[result.count - 1].1[key] = value
            }
        }
        return result
    }
}
