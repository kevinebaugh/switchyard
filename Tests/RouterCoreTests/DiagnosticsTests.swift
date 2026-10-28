import Foundation
import Testing
@testable import RouterCore

@Suite struct DiagnosticsTests {
    @Test func reportsStateWithoutAnythingPersonal() {
        let rule = UUID()
        var corrected = RoutingRecord(url: URL(string: "https://secret.example.com/private/path?token=abc")!,
                                      profileName: "Acme Work", decision: .rule(id: rule, label: "secret.example.com/private"),
                                      latencyMilliseconds: 0.4)
        corrected.correctedTo = "Personal"
        let records = [
            corrected,
            RoutingRecord(url: URL(string: "https://other.example/x")!, profileName: "Personal",
                          decision: .jev(confidence: 0.91, scope: .domain), latencyMilliseconds: 180),
        ]
        let report = DiagnosticsReport(
            appVersion: "0.9.11 (50)", macOS: "Version 27.2", architecture: "arm64", browser: "Dia",
            installedBrowsers: ["Dia", "Chrome"], browserPermission: "granted", notifications: "allowed",
            hasKey: true, keyRejected: false, jev: "reachable", rulesFolder: "Dropbox", rules: 12,
            rulesReadOnly: nil, profiles: 4, isRehearsal: false,
            recentDecisions: DiagnosticsReport.decisions(from: records))
        let text = report.markdown

        #expect(text.contains("- Switchyard: 0.9.11 (50)"))
        #expect(text.contains("- Rules: 12 in Dropbox"))
        #expect(text.contains("- rule · corrected · 0.4 ms"))
        #expect(text.contains("- Jev 0.91 · 180 ms"))
        for secret in ["secret.example.com", "private", "token", "Acme", "other.example"] {
            #expect(!text.contains(secret), "leaked \(secret)")
        }
    }
}
