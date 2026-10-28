import Foundation
import Testing
@testable import RouterCore

@Suite struct SupportNudgeTests {
    let day: TimeInterval = 86_400
    let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func neverInTheFirstWeek() {
        var state = SupportNudge.State()
        var due = false
        for i in 0..<500 { due = SupportNudge.recordLink(&state, isSupporter: false, now: start + Double(i) * 60) }
        #expect(!due)   // 500 links, all within the first day
        #expect(SupportNudge.isDue(state, isSupporter: false, now: start + 8 * day))
    }

    @Test func everyFiftyLinksAtMostWeekly() {
        var state = SupportNudge.State(routedLinks: 49, firstUseDate: start)
        #expect(SupportNudge.recordLink(&state, isSupporter: false, now: start + 10 * day))   // 50th link, after a week: due
        SupportNudge.markShown(&state, now: start + 10 * day)

        for _ in 0..<49 { _ = SupportNudge.recordLink(&state, isSupporter: false, now: start + 20 * day) }
        #expect(!SupportNudge.isDue(state, isSupporter: false, now: start + 20 * day))     // only 49 since
        #expect(SupportNudge.recordLink(&state, isSupporter: false, now: start + 20 * day))  // 50 since, 10 days later

        SupportNudge.markShown(&state, now: start + 20 * day)
        for _ in 0..<200 { _ = SupportNudge.recordLink(&state, isSupporter: false, now: start + 22 * day) }
        #expect(!SupportNudge.isDue(state, isSupporter: false, now: start + 22 * day))     // plenty of links, but 2 days
        #expect(SupportNudge.isDue(state, isSupporter: false, now: start + 27 * day))
    }

    @Test func supportersAreNeverReminded() {
        let state = SupportNudge.State(routedLinks: 10_000, firstUseDate: start)
        #expect(!SupportNudge.isDue(state, isSupporter: true, now: start + 365 * day))
        #expect(SupportNudge.isDue(state, isSupporter: false, now: start + 365 * day))
    }

    @Test func checkoutSessionIDs() {
        #expect(SupportNudge.isCheckoutSessionID("cs_live_a1" + String(repeating: "B2c3", count: 14)))
        #expect(!SupportNudge.isCheckoutSessionID(""))
        #expect(!SupportNudge.isCheckoutSessionID("cs_live_short"))
        #expect(!SupportNudge.isCheckoutSessionID("cs_test_a1" + String(repeating: "B2c3", count: 14)))
        #expect(!SupportNudge.isCheckoutSessionID("cs_live_" + String(repeating: "x", count: 40) + "&evil=1"))
        #expect(!SupportNudge.isCheckoutSessionID("{CHECKOUT_SESSION_ID}"))
        // Sandbox sessions only when asked for (rehearsals).
        #expect(SupportNudge.isCheckoutSessionID("cs_test_a1" + String(repeating: "B2c3", count: 14), allowTest: true))
        #expect(!SupportNudge.isCheckoutSessionID("cs_test_short", allowTest: true))
    }

    let live = "cs_live_a1" + String(repeating: "B2c3", count: 14)
    let otherLive = "cs_live_z9" + String(repeating: "Y8x7", count: 14)
    let test = "cs_test_a1" + String(repeating: "B2c3", count: 14)

    @Test func aPayingMacSharesItsSessionWhenTheFolderHasNone() {
        #expect(SupportSync.action(savedSession: live, sharedSession: nil, isSupporter: true, allowTest: false) == .share(session: live))
        // A broken or hand-edited file doesn't block sharing a real session.
        #expect(SupportSync.action(savedSession: live, sharedSession: "nonsense", isSupporter: true, allowTest: false) == .share(session: live))
    }

    @Test func anotherMacAdoptsTheSharedSession() {
        #expect(SupportSync.action(savedSession: nil, sharedSession: live, isSupporter: false, allowTest: false) == .adopt(session: live))
        // Already a supporter: nothing to change, and the folder keeps the first Mac's session.
        #expect(SupportSync.action(savedSession: otherLive, sharedSession: live, isSupporter: true, allowTest: false) == .nothing)
    }

    @Test func implausibleSessionsDoNothing() {
        #expect(SupportSync.action(savedSession: nil, sharedSession: nil, isSupporter: false, allowTest: false) == .nothing)
        #expect(SupportSync.action(savedSession: nil, sharedSession: "cs_live_short", isSupporter: false, allowTest: false) == .nothing)
        #expect(SupportSync.action(savedSession: "made-up", sharedSession: nil, isSupporter: true, allowTest: false) == .nothing)
    }

    @Test func sandboxSessionsOnlyCountInRehearsals() {
        #expect(SupportSync.action(savedSession: nil, sharedSession: test, isSupporter: false, allowTest: false) == .nothing)
        #expect(SupportSync.action(savedSession: nil, sharedSession: test, isSupporter: false, allowTest: true) == .adopt(session: test))
        #expect(SupportSync.action(savedSession: test, sharedSession: nil, isSupporter: true, allowTest: false) == .nothing)
    }
}
