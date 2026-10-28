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
        didSet { defaults.set(isSupporter, forKey: SettingsKey.isSupporter.rawValue) }
    }
    /// Show the card in Recent. Set when a reminder comes due; cleared by any button on it.
    @Published private(set) var isShowingCard: Bool {
        didSet { defaults.set(isShowingCard, forKey: SettingsKey.supportCardShowing.rawValue) }
    }
    private(set) var state: SupportNudge.State {
        didSet { if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: SettingsKey.supportNudge.rawValue) } }
    }

    var routedLinks: Int { state.routedLinks }
    var isEnabled: Bool { Self.checkoutURL != nil }

    private let defaults = AppEnvironment.defaults

    private init() {
        isSupporter = defaults.bool(forKey: SettingsKey.isSupporter.rawValue)
        isShowingCard = defaults.bool(forKey: SettingsKey.supportCardShowing.rawValue)
        state = defaults.data(forKey: SettingsKey.supportNudge.rawValue).flatMap { try? JSONDecoder().decode(SupportNudge.State.self, from: $0) }
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

    /// From `switchyard://supported?session=…` (the thank-you page, or a link Kevin sends someone who
    /// paid but still sees reminders), or from another Mac's `supporter.json`.
    /// The session ID is kept only as a local record of the payment.
    func markSupported(checkoutSession: String? = nil) {
        if let checkoutSession { defaults.set(checkoutSession, forKey: SettingsKey.supportCheckoutSession.rawValue) }
        isSupporter = true
        isShowingCard = false
        if checkoutSession != nil { syncWithOtherMacs() }
    }

    // MARK: Other Macs

    /// `supporter.json` beside rules.json in the sync folder: the checkout session that proved a
    /// payment, so your other Macs stop reminding too. Each Mac re-checks the session's shape
    /// (a little friction, not a lock). Macs marked supporter before sessions existed have none to
    /// share; their other Macs can use "Paid but still seeing this?".
    private struct SharedSupport: Codable {
        var session: String
        var since: Date
    }

    static let supportFileName = "supporter.json"

    /// Share this Mac's payment, or pick up one from another Mac. Off the main thread: the sync
    /// folder may be a cloud folder that's slow to answer.
    func syncWithOtherMacs() {
        guard isEnabled, !AppEnvironment.isSnapshot else { return }
        let file = AppSettings.shared.rulesLocation.directory.appendingPathComponent(Self.supportFileName)
        let saved = defaults.string(forKey: SettingsKey.supportCheckoutSession.rawValue)
        let allowTest = AppEnvironment.isRehearsal
        let alreadySupporter = isSupporter
        Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let shared = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(SharedSupport.self, from: $0) }
            switch SupportSync.action(savedSession: saved, sharedSession: shared?.session,
                                      isSupporter: alreadySupporter, allowTest: allowTest) {
            case let .share(session):
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(SharedSupport(session: session, since: Date())) {
                    try? data.write(to: file, options: .atomic)
                }
            case let .adopt(session):
                await MainActor.run { SupportReminder.shared.markSupported(checkoutSession: session) }
            case .nothing:
                break
            }
        }
    }

    /// A pre-filled GitHub issue for someone who paid but still sees reminders (say, they paid
    /// on another device). Asks only for the date and amount, which are enough to find the
    /// payment in Stripe; never an email address.
    static let paidButStillSeeingURL = URL(string: "https://github.com/kevinebaugh/switchyard/issues/new?template=supporter.yml")!

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
