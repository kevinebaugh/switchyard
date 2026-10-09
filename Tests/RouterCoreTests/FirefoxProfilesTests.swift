import Foundation
import Testing
@testable import RouterCore

@Suite struct FirefoxProfilesTests {
    let root = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Firefox", isDirectory: true)

    let ini = """
        [Install4F96D1932A9F858E]
        Default=Profiles/abcd1234.default-release
        Locked=1

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/efgh5678.Work

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abcd1234.default-release
        Default=1

        ; a profile kept somewhere else
        [Profile2]
        Name=Side = Project
        IsRelative=0
        Path=/Volumes/External/firefox/side

        [Profile3]
        Path=Profiles/nameless

        [General]
        StartWithLastProfile=1
        Version=2
        """

    @Test func readsProfilesInFileOrderWithFullPaths() {
        let profiles = FirefoxProfiles.profiles(fromINI: ini, root: root)
        #expect(profiles.map(\.name) == ["default-release", "Work", "Side = Project"])
        #expect(profiles.map(\.directory) == [
            "/Users/someone/Library/Application Support/Firefox/Profiles/abcd1234.default-release",
            "/Users/someone/Library/Application Support/Firefox/Profiles/efgh5678.Work",
            "/Volumes/External/firefox/side",
        ])
    }

    @Test func toleratesWindowsLineEndingsAndJunk() {
        let crlf = "[Profile0]\r\nName=Personal\r\nIsRelative=1\r\nPath=Profiles/p.Personal\r\n"
        #expect(FirefoxProfiles.profiles(fromINI: crlf, root: root).map(\.name) == ["Personal"])
        #expect(FirefoxProfiles.profiles(fromINI: "not an ini file", root: root).isEmpty)
        #expect(FirefoxProfiles.profiles(fromINI: "", root: root).isEmpty)
    }

    @Test func firefoxIsWiredThroughTheBrowserModel() throws {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(BrowserKind.firefox.profileListFile(home: home).path
            == "/Users/someone/Library/Application Support/Firefox/profiles.ini")
        #expect(BrowserKind.chrome.profileListFile(home: home).lastPathComponent == "Local State")

        let profile = try #require(BrowserKind.firefox.profiles(fromProfileList: Data(ini.utf8), home: home).last)
        #expect(BrowserKind.firefox.profileFolder(profile, home: home).path == "/Volumes/External/firefox/side")
        #expect(BrowserKind.firefox.launchArguments(opening: URL(string: "https://example.com/a?b=c")!, in: profile)
            == ["-profile", "/Volumes/External/firefox/side", "-new-tab", "https://example.com/a?b=c"])

        let chromeProfile = BrowserProfile(directory: "Profile 2", name: "Work")
        #expect(BrowserKind.chrome.profileFolder(chromeProfile, home: home).path
            == "/Users/someone/Library/Application Support/Google/Chrome/Profile 2")
        #expect(BrowserKind.chrome.launchArguments(opening: URL(string: "https://example.com")!, in: chromeProfile)
            == ["--profile-directory=Profile 2", "https://example.com"])
    }

    @Test func renamesAreDetectedByFolder() {
        let before = FirefoxProfiles.profiles(fromINI: ini, root: root)
        let after = FirefoxProfiles.profiles(fromINI: ini.replacingOccurrences(of: "Name=Work", with: "Name=Job"), root: root)
        #expect(ChromiumLocalState.renames(from: before, to: after).map { "\($0.from)→\($0.to)" } == ["Work→Job"])
    }

    // The layout Firefox's profile manager writes: profiles.ini names a group database by
    // StoreID, keeps the unused "default" profile, and doesn't list newer profiles at all.
    let managerINI = """
        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/aaaa1111.default-release
        StoreID=652a8792
        ShowSelector=1

        [Install2656FF1E876E9973]
        Default=Profiles/aaaa1111.default-release
        Locked=1

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/bbbb2222.default
        Default=1
        """

    @Test func profileManagerGroupIsWhatFirefoxShows() {
        #expect(FirefoxProfiles.groupDatabaseName(fromINI: managerINI) == "652a8792.sqlite")
        #expect(FirefoxProfiles.groupDatabaseName(fromINI: ini) == nil)

        let group = [
            FirefoxProfiles.GroupProfile(path: "Profiles/aaaa1111.default-release", name: "Original profile",
                                         themeForeground: "rgb(21,20,26)", themeBackground: "rgb(240,240,244)"),
            FirefoxProfiles.GroupProfile(path: "Profiles/cccc3333.Profile 1", name: "Work",
                                         themeForeground: "rgb(62,41,118)", themeBackground: "rgb(245,236,255)"),
        ]
        let profiles = FirefoxProfiles.profiles(fromINI: managerINI, root: root, group: group)
        #expect(profiles.map(\.name) == ["Original profile", "Work"])
        #expect(profiles[1].directory == "/Users/someone/Library/Application Support/Firefox/Profiles/cccc3333.Profile 1")
        #expect(profiles[0].colorARGB == nil)            // default theme: greys, so Switchyard's palette
        #expect(profiles[1].colorARGB == 0xFF3E_2976)     // the Work theme's purple
    }

    @Test func classicSetupHidesTheUnusedDefaultProfile() {
        #expect(FirefoxProfiles.profiles(fromINI: managerINI, root: root).map(\.name) == ["default-release"])
        let onlyDefault = "[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/x.default\n"
        #expect(FirefoxProfiles.profiles(fromINI: onlyDefault, root: root).map(\.name) == ["default"])
    }

    @Test func themeColours() {
        #expect(FirefoxProfiles.rgb("rgba(62, 41, 118, 1)")! == (62, 41, 118))
        #expect(FirefoxProfiles.rgb("not a colour") == nil)
        #expect(FirefoxProfiles.themeColor(foreground: "rgb(255,255,255)", background: "rgb(0,120,212)") == 0xFF00_78D4)
        #expect(FirefoxProfiles.themeColor(foreground: nil, background: nil) == nil)
    }
}
