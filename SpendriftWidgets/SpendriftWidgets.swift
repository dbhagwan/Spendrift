import SwiftUI
import WidgetKit

@main
struct SpendriftWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
        SpendPaceWidget()
        BudgetRemainingWidget()
        NetWorthWidget()
        UpcomingBillsWidget()
        AIAlertWidget()
    }
}

/// One provider for all widgets: reads the precomputed snapshot written by the
/// app after each sync/AI run. The app calls `WidgetCenter.reloadAllTimelines()`
/// on meaningful changes; the scheduled refresh below is just a staleness
/// backstop, deliberately infrequent to respect the WidgetKit refresh budget.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: SharedSnapshotStore.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SharedSnapshotStore.load() ?? SharedSnapshotStore.placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedSnapshotStore.load() ?? SharedSnapshotStore.placeholder)
        let refresh = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Shared pieces

extension Decimal {
    func widgetCurrency(_ code: String, cents: Bool = false) -> String {
        formatted(.currency(code: code).precision(.fractionLength(cents ? 2 : 0)))
    }
}

struct WidgetHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .kerning(0.4)
    }
}

struct PaceText: View {
    var delta: Double

    var body: some View {
        let over = delta > 0
        Text("\(over ? "+" : "")\(delta.formatted(.percent.precision(.fractionLength(0)))) \(over ? "over" : "under") pace")
            .foregroundStyle(over ? .red : .green)
    }
}
