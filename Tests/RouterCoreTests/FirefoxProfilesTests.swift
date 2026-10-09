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
}
