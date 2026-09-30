import Foundation

public struct BrowserProfile: Hashable, Sendable, Identifiable {
    public let directory: String
    public let name: String
    /// The profile's color in Dia, as 0xAARRGGBB.
    public let colorARGB: UInt32?
    /// The Google account the profile is signed in to, if any.
    public let account: ProfileAccount?

    public var id: String { directory }

    public init(directory: String, name: String, colorARGB: UInt32? = nil, account: ProfileAccount? = nil) {
        self.directory = directory
        self.name = name
        self.colorARGB = colorARGB
        self.account = account
    }
}

/// Reads a Chromium browser's `Local State` (Dia, Chrome, Brave…), the source of truth for
/// which profiles exist.
/// Adapted from jdsimcoe/dia-router's DiaProfileState (MIT); see THIRD_PARTY_NOTICES.md.
public enum ChromiumLocalState {
    public static func fileURL(for browser: BrowserKind) -> URL {
        browser.userDataDirectory().appendingPathComponent("Local State")
    }

    private struct LocalState: Decodable {
        struct ProfileState: Decodable {
            struct Info: Decodable {
                let name: String
                let colorSeed: Int64?
                let highlightColor: Int64?
                let avatarFillColor: Int64?
                let userName: String?
                let hostedDomain: String?

                enum CodingKeys: String, CodingKey {
                    case name
                    case colorSeed = "profile_color_seed"
                    case highlightColor = "profile_highlight_color"
                    case avatarFillColor = "default_avatar_fill_color"
                    case userName = "user_name"
                    case hostedDomain = "hosted_domain"
                }

                /// Dia keeps the profile color in the seed; Chrome in the highlight or avatar color.
                /// Opaque black is Chromium's "unset".
                var color: UInt32? {
                    [colorSeed, highlightColor, avatarFillColor]
                        .compactMap { $0.map { UInt32(truncatingIfNeeded: $0) } }
                        .first { $0 != 0xFF00_0000 && $0 != 0 }
                }
            }

            let infoCache: [String: Info]
            let profilesOrder: [String]?

            enum CodingKeys: String, CodingKey {
                case infoCache = "info_cache"
                case profilesOrder = "profiles_order"
            }
        }

        let profile: ProfileState
    }

    public static func profiles(from data: Data) -> [BrowserProfile] {
        guard let state = try? JSONDecoder().decode(LocalState.self, from: data) else { return [] }
        let order = state.profile.profilesOrder ?? []

        return state.profile.infoCache
            .map { directory, info in
                BrowserProfile(
                    directory: directory,
                    name: info.name,
                    colorARGB: info.color,
                    account: info.userName.flatMap { $0.isEmpty ? nil : ProfileAccount(email: $0, workspaceDomain: info.hostedDomain) }
                )
            }
            .sorted { lhs, rhs in
                let lhsIndex = order.firstIndex(of: lhs.directory) ?? Int.max
                let rhsIndex = order.firstIndex(of: rhs.directory) ?? Int.max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.directory.localizedStandardCompare(rhs.directory) == .orderedAscending
            }
    }

    /// Order profiles as Dia shows them (its scripting interface reports that order; `Local State`
    /// doesn't store it). Profiles missing from `visibleOrder` keep their relative order at the end.
    public static func sorted(_ profiles: [BrowserProfile], visibleOrder: [String]) -> [BrowserProfile] {
        let rank = Dictionary(visibleOrder.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return profiles.enumerated()
            .sorted { lhs, rhs in
                let l = rank[lhs.element.name.lowercased()] ?? Int.max
                let r = rank[rhs.element.name.lowercased()] ?? Int.max
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Profiles whose directory is unchanged but whose name differs: Dia renames.
    public static func renames(from old: [BrowserProfile], to new: [BrowserProfile]) -> [(from: String, to: String)] {
        new.compactMap { profile in
            guard let previous = old.first(where: { $0.directory == profile.directory }),
                  previous.name != profile.name else { return nil }
            return (previous.name, profile.name)
        }
    }
}
