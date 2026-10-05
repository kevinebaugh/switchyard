import Foundation
import Testing
@testable import RouterCore

@Suite struct JevReachabilityTests {
    let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func backoffDoublesToAFiveMinuteCap() {
        #expect((0..<9).map(JevReachability.baseDelay) == [5, 10, 20, 40, 80, 160, 300, 300, 300])
    }

    @Test func jitterStaysWithinTwentyPercent() {
        #expect(JevReachability.delay(attempt: 0, random: { 0 }) == 4)
        #expect(JevReachability.delay(attempt: 0, random: { 0.5 }) == 5)
        #expect(abs(JevReachability.delay(attempt: 6, random: { 0.999_999 }) - 360) < 0.001)
    }

    @Test func oneFailureSkipsJevAndSchedulesChecks() {
        var reach = JevReachability()
        #expect(reach.skipReason == nil)

        let becameUnreachable = reach.recordFailure(now: start, random: { 0.5 })
        #expect(becameUnreachable)
        #expect(reach.skipReason == .unreachable)
        #expect(reach.nextCheck == start + 5)

        let becameUnreachableAgain = reach.recordFailure(now: start + 5, random: { 0.5 })   // a failed check
        #expect(!becameUnreachableAgain)
        #expect(reach.nextCheck == start + 15)
        reach.recordFailure(now: start + 15, random: { 0.5 })
        #expect(reach.nextCheck == start + 35)

        let recovered = reach.recordSuccess()   // time to catch up
        #expect(recovered)
        #expect(reach.skipReason == nil)
        #expect(reach.nextCheck == nil)
        let recoveredAgain = reach.recordSuccess()
        #expect(!recoveredAgain)
    }

    @Test func aNetworkChangeChecksAtOnceAndRestartsTheBackoff() {
        var reach = JevReachability()
        for i in 0..<5 { reach.recordFailure(now: start + Double(i), random: { 0.5 }) }
        #expect(reach.failedChecks == 4)

        reach.networkChanged(hasNetwork: true, now: start + 100)
        #expect(reach.nextCheck == start + 100)
        #expect(reach.failedChecks == 0)
        reach.recordFailure(now: start + 100, random: { 0.5 })
        #expect(reach.nextCheck == start + 110)   // second step of a fresh backoff
    }

    @Test func noNetworkMeansOfflineAndItsReturnTriggersACheck() {
        var reach = JevReachability()
        reach.networkChanged(hasNetwork: false, now: start)
        #expect(reach.skipReason == .offline)
        #expect(reach.nextCheck == nil)
        #expect(!reach.shouldCheckForLink(now: start))

        reach.networkChanged(hasNetwork: true, now: start + 60)
        #expect(reach.skipReason == .unreachable)
        #expect(reach.nextCheck == start + 60)
        let recovered = reach.recordSuccess()
        #expect(recovered)
    }

    @Test func linksCheckAtMostEveryFiveSecondsWithoutResettingTheBackoff() {
        var reach = JevReachability()
        #expect(!reach.shouldCheckForLink(now: start))   // reachable: nothing to check
        reach.recordFailure(now: start, random: { 0.5 })
        reach.recordFailure(now: start, random: { 0.5 })
        #expect(reach.shouldCheckForLink(now: start))
        reach.checkStarted(now: start)
        #expect(!reach.shouldCheckForLink(now: start + 4))
        #expect(reach.shouldCheckForLink(now: start + 5))
        #expect(reach.failedChecks == 1)
    }
}

@Suite struct OfflineFallbackTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func record(_ url: String, _ decision: Decision, ago: TimeInterval = 60, profile: String = "Personal",
                catchUp: RoutingRecord.CatchUp? = nil, learned: UUID? = nil) -> RoutingRecord {
        var record = RoutingRecord(url: URL(string: url)!, date: now - ago, profileName: profile, decision: decision,
                                   latencyMilliseconds: 0.2, learnedRuleID: learned)
        record.catchUp = catchUp
        return record
    }

    @Test func certificateErrorsLookLikeACaptivePortal() {
        #expect(FallbackReason(urlErrorCode: .notConnectedToInternet) == .offline)
        #expect(FallbackReason(urlErrorCode: .serverCertificateUntrusted) == .unreachable)
        #expect(FallbackReason(urlErrorCode: .cannotFindHost) == .unreachable)
        #expect(FallbackReason(urlErrorCode: .timedOut) == .timeout)
        #expect(FallbackReason(urlErrorCode: .badServerResponse) == .http(URLError.Code.badServerResponse.rawValue))
        #expect([FallbackReason.timeout, .offline, .unreachable].map(\.isNetworkFailure) == [true, true, true])
        #expect([FallbackReason.rateLimited, .noAPIKey, .http(500)].map(\.isNetworkFailure) == [false, false, false])
    }

    @Test func catchUpPicksRecentNetworkFallbacksOncePerHostAndPath() {
        let records = [
            record("https://app.example.com/a?x=1", .fallback(.unreachable), ago: 10),
            record("https://app.example.com/a?x=2", .fallback(.unreachable), ago: 20),   // same host + path
            record("https://app.example.com/b", .fallback(.offline), ago: 30),
            record("https://slow.example.com/", .fallback(.timeout), ago: 40),
            record("https://limited.example.com/", .fallback(.rateLimited), ago: 50),    // not a network failure
            record("https://done.example.com/", .fallback(.offline),
                   catchUp: .init(profileName: "Work", confidence: 0.9, isConfident: true, scope: nil)),
            record("https://old.example.com/", .fallback(.offline), ago: 25 * 60 * 60),
        ]
        let items = OfflineCatchUp.items(from: records, now: now)
        #expect(items.map(\.representative.url.host) == ["app.example.com", "app.example.com", "slow.example.com"])
        #expect(items[0].recordIDs == [records[0].id, records[1].id])
        #expect(items[0].representative.id == records[0].id)
    }

    @Test func catchUpIsCappedAtTwentyFive() {
        let records = (0..<40).map { record("https://site\($0).example/", .fallback(.offline), ago: Double($0)) }
        #expect(OfflineCatchUp.items(from: records, now: now).count == 25)
    }

    @Test func explanationsBeforeAndAfterCatchingUp() {
        func line(_ r: RoutingRecord, _ rules: [Rule] = []) -> RoutingExplanation.Line {
            RoutingExplanation.explain(r, rule: { id in rules.first { $0.id == id } })
        }
        #expect(line(record("https://a.example/", .fallback(.offline)))
            == .init(text: "Opened offline · Jev will check it later", needsAttention: false))
        #expect(line(record("https://a.example/", .fallback(.unreachable))).text
            == "Couldn't reach Jev · will check it later")

        let learned = Rule(key: RuleKey(host: "a.example", hostMatch: .domain), profileName: "Work", origin: .learned)
        #expect(line(record("https://a.example/", .fallback(.offline),
                            catchUp: .init(profileName: "Work", confidence: 0.91, isConfident: true, scope: .domain),
                            learned: learned.id), [learned])
            == .init(text: "Opened offline · Jev says Work (0.91)", needsAttention: true))
        #expect(line(record("https://a.example/", .fallback(.unreachable),
                            catchUp: .init(profileName: "personal", confidence: 0.93, isConfident: true, scope: nil)))
            == .init(text: "Couldn't reach Jev · Jev agrees (0.93)", needsAttention: false))
        #expect(line(record("https://a.example/", .fallback(.timeout),
                            catchUp: .init(profileName: "Work", confidence: 0.55, isConfident: false, scope: nil)))
            == .init(text: "Jev timed out · Jev unsure (0.55)", needsAttention: true))

        let yours = Rule(key: RuleKey(host: "a.example", hostMatch: .domain), profileName: "Personal", origin: .corrected)
        #expect(line(record("https://a.example/", .fallback(.offline), learned: yours.id), [yours])
            == .init(text: "Opened offline · you saved all of a.example", needsAttention: false))
    }
}
