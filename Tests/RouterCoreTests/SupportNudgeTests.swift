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
}
