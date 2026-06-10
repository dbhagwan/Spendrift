import Foundation

/// Reads/writes the precomputed `WidgetSnapshot` to the App Group container.
/// The app writes after every sync/AI recomputation; the widget extension only
/// reads. Compiled into both targets.
enum SharedSnapshotStore {
    static let appGroupID = "group.com.spendrift.shared"
    private static let snapshotFilename = "widget-snapshot.json"

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Placeholder snapshot for previews and first-run widgets.
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: .now,
            currencyCode: "USD",
            safeToSpendToday: 38,
            safeToSpendWeek: 245,
            safeToSpendConfidence: 0.82,
            budgetTotal: 3600,
            budgetSpent: 2150,
            budgetRemaining: 1450,
            spendPaceDelta: 0.08,
            netWorth: 84_320,
            netWorthChange30Days: 1240,
            upcomingBills: [
                .init(merchant: "Rent", amount: 1850, dueDate: .now.addingTimeInterval(86_400 * 3)),
                .init(merchant: "Netflix", amount: 15.49, dueDate: .now.addingTimeInterval(86_400 * 5)),
            ],
            topAlert: .init(
                title: "Dining pace +27%",
                detail: "Dining is running above your 3-month average.",
                severity: .warning
            )
        )
    }
}
