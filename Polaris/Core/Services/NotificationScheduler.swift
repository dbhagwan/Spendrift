import Foundation
import UserNotifications

/// Local notifications only — the weekly money digest and receipt
/// return-window reminders. Content is computed on device from structured
/// pipeline output; nothing leaves the phone.
enum NotificationScheduler {
    static let digestIdentifier = "polaris.weekly-digest"
    static let digestEnabledKey = "weeklyDigestEnabled"

    /// (Re)schedules the repeating Sunday-evening digest with the freshest
    /// insight, or clears it when the user has the toggle off. Called after
    /// every pipeline recompute so the content never goes stale.
    static func updateWeeklyDigest(
        insights: [SpendingInsight],
        safeToSpendWeek: Decimal?,
        currencyCode: String
    ) async {
        let center = UNUserNotificationCenter.current()
        guard UserDefaults.standard.bool(forKey: digestEnabledKey) else {
            center.removePendingNotificationRequests(withIdentifiers: [digestIdentifier])
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your week in money"
        if let top = insights.first {
            content.body = top.title
        } else if let week = safeToSpendWeek {
            content.body = "You have \(week.currency(currencyCode, showCents: false)) safe to spend this week."
        } else {
            content.body = "Open Polaris for this week's spending story."
        }
        content.sound = .default

        var fireOn = DateComponents()
        fireOn.weekday = 1 // Sunday
        fireOn.hour = 18
        center.removePendingNotificationRequests(withIdentifiers: [digestIdentifier])
        try? await center.add(UNNotificationRequest(
            identifier: digestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: fireOn, repeats: true)
        ))
    }

    /// One reminder two days before a receipt's return window closes.
    static func scheduleReturnReminder(receiptID: UUID, merchant: String?, returnBy: Date) async {
        guard let fireDate = Calendar.current.date(byAdding: .day, value: -2, to: returnBy),
              fireDate > .now else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Return window closing"
        content.body = "\(merchant ?? "A recent purchase") can be returned until \(returnBy.formatted(date: .abbreviated, time: .omitted))."
        content.sound = .default
        try? await center.add(UNNotificationRequest(
            identifier: "polaris.return.\(receiptID.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate),
                repeats: false
            )
        ))
    }
}
