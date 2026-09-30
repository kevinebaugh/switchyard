import Foundation
import RouterCore
import UserNotifications

/// Notifications only for loud events: fallbacks, (optionally) low confidence, setup problems.
/// Routing notifications carry one action per other profile, which performs the suggested correction.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private static let fallbackInterval: TimeInterval = 5 * 60
    private static let setupInterval: TimeInterval = 60 * 60
    nonisolated private static let actionPrefix = "profile:"

    private var center: UNUserNotificationCenter { .current() }
    private var lastRoutingNotification = Date.distantPast
    private var lastSetupNotifications: [String: Date] = [:]
    private var registeredProfiles: [String] = []

    func setUp(profiles: [String]) {
        center.delegate = self
        registerCategories(for: profiles)
    }

    /// Asked during onboarding (or at launch once onboarding is done), not on first launch.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// One category per profile the link opened in: confirm it first, then the other profiles.
    /// Every action saves the suggested rule; the others also re-open the link.
    func registerCategories(for profiles: [String]) {
        guard profiles != registeredProfiles else { return }
        registeredProfiles = profiles
        let categories = profiles.map { opened in
            let confirm = UNNotificationAction(identifier: Self.actionPrefix + opened, title: "\(opened) was right")
            let moves = profiles.filter { $0 != opened }.map {
                UNNotificationAction(identifier: Self.actionPrefix + $0, title: "Should be \($0)")
            }
            return UNNotificationCategory(identifier: "routing.\(opened)", actions: [confirm] + moves, intentIdentifiers: [])
        }
        center.setNotificationCategories(Set(categories))
    }

    func notify(about record: RoutingRecord) {
        let settings = AppSettings.shared
        guard settings.notificationsEnabled else { return }

        let host = record.url.displayHost
        let title: String
        var body = "\(host) → \(record.profileName)"
        switch record.decision {
        case let .fallback(reason) where reason.isSetupProblem:
            notifySetupProblem(reason == .noAPIKey
                ? "No TypeSafe API key: new links open in \(record.profileName). Add one in Switchyard → Settings."
                : "Jev rejected the API key: new links open in \(record.profileName). Check Settings.")
            return
        case let .fallback(reason):
            title = reason == .timeout ? "Jev was too slow" : "Fallback: \(reason.label)"
        case let .lowConfidence(confidence) where settings.notifyLowConfidence:
            title = "Jev wasn't sure"
            body += " · \(confidence.confidenceLabel)"
        default:
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastRoutingNotification) >= Self.fallbackInterval else { return }
        lastRoutingNotification = now

        registerCategories(for: ProfilesMonitor.shared.names)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = "routing.\(record.profileName)"
        content.userInfo = ["recordID": record.id.uuidString]
        center.add(UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil))
    }

    func notifySetupProblem(_ message: String) {
        guard AppSettings.shared.notificationsEnabled else { return }
        let now = Date()
        if let last = lastSetupNotifications[message], now.timeIntervalSince(last) < Self.setupInterval { return }
        lastSetupNotifications[message] = now

        let content = UNMutableNotificationContent()
        content.title = "Switchyard needs attention"
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action.hasPrefix(Self.actionPrefix),
              let idString = response.notification.request.content.userInfo["recordID"] as? String,
              let recordID = UUID(uuidString: idString) else { return }
        let profile = String(action.dropFirst(Self.actionPrefix.count))
        await Router.shared.correct(recordID: recordID, to: profile)
    }
}
