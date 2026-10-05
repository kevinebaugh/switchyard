import AppKit
import Network
import os
import RouterCore

private let log = Logger(subsystem: "com.kevinebaugh.switchyard", category: "connectivity")

/// Keeps `JevReachability` up to date: watches the network, runs the background checks on its
/// backoff schedule, and calls `onRecovered` when Jev can be reached again (time to catch up).
@MainActor
final class Connectivity {
    private(set) var state = JevReachability()
    var onRecovered: (() -> Void)?
    var onUnreachable: (() -> Void)?

    private let jev: JevClient
    private let monitor = NWPathMonitor()
    private var scheduledCheck: Task<Void, Never>?
    private var isChecking = false

    init(jev: JevClient) {
        self.jev = jev
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let hasNetwork = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(hasNetwork: hasNetwork) }
        }
        monitor.start(queue: DispatchQueue(label: "com.kevinebaugh.switchyard.path"))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.networkChanged(hasNetwork: self.state.hasNetwork)
            }
        }
    }

    /// Why to skip Jev for this link, if it should be skipped. A skipped link also nudges a
    /// background check (at most every 5 s), so a returning connection is noticed while you click.
    func skipReason() -> FallbackReason? {
        guard let reason = state.skipReason else { return nil }
        if state.shouldCheckForLink(now: Date()) { Task { await check() } }
        return reason
    }

    /// A real request to Jev got an answer.
    func requestSucceeded() {
        recovered(state.recordSuccess())
    }

    /// A real request (or the keep-warm) couldn't get through.
    func requestFailed() {
        let became = state.recordFailure(now: Date())
        if became {
            log.info("Jev unreachable; checking in the background")
            onUnreachable?()
        }
        schedule()
    }

    /// The keep-warm doubles as a check while Jev is reachable.
    func keepWarmFinished(reachedJev: Bool) {
        if reachedJev { requestSucceeded() } else if state.hasNetwork { requestFailed() }
    }

    private func networkChanged(hasNetwork: Bool) {
        let hadNetwork = state.hasNetwork
        state.networkChanged(hasNetwork: hasNetwork, now: Date())
        if hadNetwork, !hasNetwork {
            log.info("No network")
            onUnreachable?()
        }
        schedule()
    }

    private func recovered(_ wasUnreachable: Bool) {
        scheduledCheck?.cancel()
        scheduledCheck = nil
        if wasUnreachable {
            log.info("Jev reachable again")
            onRecovered?()
        }
    }

    /// (Re)arm the timer for the next background check.
    private func schedule() {
        scheduledCheck?.cancel()
        scheduledCheck = nil
        guard state.hasNetwork, let next = state.nextCheck else { return }
        let delay = max(0, next.timeIntervalSinceNow)
        scheduledCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    private func check() async {
        guard !isChecking, state.hasNetwork, !state.isReachable else { return }
        isChecking = true
        state.checkStarted(now: Date())
        let reached = await jev.prewarm()
        isChecking = false
        if reached {
            requestSucceeded()
        } else {
            state.recordFailure(now: Date())
            schedule()
        }
    }
}
