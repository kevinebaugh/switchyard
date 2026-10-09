import Foundation

/// Reads Firefox's `profiles.ini`: one `[ProfileN]` section per profile, with `Name`, `Path` and
/// `IsRelative` (Path relative to the folder holding profiles.ini). Profiles keep the file's
/// order (Profile0, Profile1, …); their `directory` is the full path, which is what `-profile`
/// takes, so names never reach the command line.
public enum FirefoxProfiles {
    public static func profiles(fromINI text: String, root: URL) -> [BrowserProfile] {
        sections(text)
            .compactMap { header, values -> (index: Int, profile: BrowserProfile)? in
                guard header.hasPrefix("Profile"), let index = Int(header.dropFirst("Profile".count)),
                      let name = values["Name"], !name.isEmpty,
                      let path = values["Path"], !path.isEmpty else { return nil }
                let isRelative = values["IsRelative"].map { $0 != "0" } ?? !path.hasPrefix("/")
                let folder = isRelative
                    ? root.appendingPathComponent(path, isDirectory: true).standardizedFileURL.path
                    : URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
                return (index, BrowserProfile(directory: folder, name: name))
            }
            .sorted { $0.index < $1.index }
            .map(\.profile)
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
