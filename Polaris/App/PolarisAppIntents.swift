import AppIntents
import Foundation

/// Siri / Shortcuts / Spotlight surface. Answers come from the widget
/// snapshot the pipeline writes after every recompute, so the intent is
/// instant and fully offline — no model call, no network.
struct SafeToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Safe to Spend Today"
    static let description = IntentDescription(
        "Asks Polaris how much you can safely spend today."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedSnapshotStore.load() else {
            return .result(dialog: "Polaris hasn't computed a number yet — open the app to sync your accounts.")
        }
        let today = snapshot.safeToSpendToday.currency(snapshot.currencyCode, showCents: false)
        let week = snapshot.safeToSpendWeek.currency(snapshot.currencyCode, showCents: false)
        return .result(dialog: "You can safely spend \(today) today, and \(week) over the rest of the week.")
    }
}

struct UpcomingBillsIntent: AppIntent {
    static let title: LocalizedStringResource = "Upcoming Bills"
    static let description = IntentDescription(
        "Asks Polaris which recurring charges are coming up."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedSnapshotStore.load(), !snapshot.upcomingBills.isEmpty else {
            return .result(dialog: "No upcoming bills detected right now.")
        }
        let bills = snapshot.upcomingBills.prefix(3)
            .map { "\($0.merchant) \($0.amount.currency(snapshot.currencyCode, showCents: false)) on \($0.dueDate.shortDay)" }
            .joined(separator: ", ")
        return .result(dialog: "Coming up: \(bills).")
    }
}

struct PolarisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SafeToSpendIntent(),
            phrases: [
                "How much can I spend in \(.applicationName)",
                "Ask \(.applicationName) what's safe to spend today",
            ],
            shortTitle: "Safe to Spend",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: UpcomingBillsIntent(),
            phrases: [
                "What bills are coming up in \(.applicationName)",
            ],
            shortTitle: "Upcoming Bills",
            systemImageName: "calendar.badge.clock"
        )
    }
}
