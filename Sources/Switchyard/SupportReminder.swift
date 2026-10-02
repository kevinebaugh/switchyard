import AppKit
import RouterCore

/// The occasional "support Switchyard" reminder: a card at the top of Recent plus a quiet
/// notification, every 50 links and at most weekly (see `SupportNudge`). Paying once, or
/// saying you already have, stops it for good. It's on trust: Switchyard is MIT, so there's
/// no license key to check. It never touches routing.
@MainActor
final class SupportReminder: ObservableObject {
    static let shared = SupportReminder()

    /// The pay-what-you-want Stripe Payment Link (Managed Payments, $10 suggested, $5 minimum).
    /// After payment it redirects to docs/thanks (on GitHub Pages) with `?session_id=`, which
    /// opens `switchyard://supported?session=…` to mark this Mac as a supporter. Nil turns reminders off.
    static let checkoutURL: URL? = URL(string: "https://buy.stripe.com/6oU8wR2sC1eJcLT4tW0ZW00")
    /// Payments made through Stripe Climate put 1% toward carbon removal.
    static let climateNote = "1% goes to removing carbon from the atmosphere."

    @Published private(set) var isSupporter: Bool {
        didSet { defaults.set(isSupporter, forKey: "isSupporter") }
    }
    /// Show the card in Recent. Set when a reminder comes due; cleared by any button on it.
    @Published private(set) var isShowingCard: Bool {
        didSet { defaults.set(isShowingCard, forKey: "supportCardShowing") }
    }
    private(set) var state: SupportNudge.State {
        didSet { if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "supportNudge") } }
    }

    var routedLinks: Int { state.routedLinks }
    var isEnabled: Bool { Self.checkoutURL != nil }

    private let defaults = AppEnvironment.defaults

    private init() {
        isSupporter = defaults.bool(forKey: "isSupporter")
        isShowingCard = defaults.bool(forKey: "supportCardShowing")
        state = defaults.data(forKey: "supportNudge").flatMap { try? JSONDecoder().decode(SupportNudge.State.self, from: $0) }
            ?? SupportNudge.State()
    }

    /// Called after every routed link, once the link is open.
    func linkRouted() {
        guard isEnabled, !AppEnvironment.isIsolated else { return }
        guard SupportNudge.recordLink(&state, isSupporter: isSupporter) else { return }
        SupportNudge.markShown(&state)
        isShowingCard = true
        Notifier.shared.notifySupport(routedLinks: routedLinks)
    }

    func openCheckout() {
        isShowingCard = false
        if let url = Self.checkoutURL { NSWorkspace.shared.open(url) }
    }

    func notNow() {
        isShowingCard = false
    }

    /// From `switchyard://supported?session=…` (the thank-you page) or "I've already supported".
    /// The session ID is kept only as a local record of the payment.
    func markSupported(checkoutSession: String? = nil) {
        if let checkoutSession { defaults.set(checkoutSession, forKey: "supportCheckoutSession") }
        isSupporter = true
        isShowingCard = false
    }

    /// Snapshots only: a made-up count, so the card renders as it would after a while.
    func showForSnapshot(routedLinks: Int) {
        guard AppEnvironment.isSnapshot else { return }
        state.routedLinks = routedLinks
        isShowingCard = true
    }

    /// "Switchyard has routed 1,250 links for you."
    var routedSummary: String {
        "Switchyard has routed \(routedLinks.formatted()) links for you."
    }
}
