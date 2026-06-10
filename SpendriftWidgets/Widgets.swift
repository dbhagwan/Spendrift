import SwiftUI
import WidgetKit

// MARK: - Safe to Spend (hero widget, all families + lock screen)

struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SafeToSpend", provider: SnapshotProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Safe to Spend")
        .description("What you can spend today without breaking your plan.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct SafeToSpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Safe today: \(snapshot.safeToSpendToday.widgetCurrency(snapshot.currencyCode))")
                .privacySensitive()
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(snapshot.safeToSpendToday.widgetCurrency(snapshot.currencyCode))
                    .font(.headline.bold())
                    .minimumScaleFactor(0.5)
                Text("today").font(.caption2)
            }
            .privacySensitive()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("SAFE TO SPEND").font(.caption2.weight(.semibold))
                Text(snapshot.safeToSpendToday.widgetCurrency(snapshot.currencyCode))
                    .font(.title3.bold())
                PaceText(delta: snapshot.spendPaceDelta).font(.caption2)
            }
            .privacySensitive()
        case .systemMedium, .systemLarge:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Safe to Spend Today", systemImage: "sparkles")
                Text(snapshot.safeToSpendToday.widgetCurrency(snapshot.currencyCode))
                    .font(.system(size: 38, weight: .bold))
                    .privacySensitive()
                HStack(spacing: 14) {
                    stat("Week", snapshot.safeToSpendWeek.widgetCurrency(snapshot.currencyCode))
                    stat("Budget left", snapshot.budgetRemaining.widgetCurrency(snapshot.currencyCode))
                    Spacer()
                }
                if family == .systemLarge {
                    Divider()
                    if let alert = snapshot.topAlert {
                        Label(alert.title, systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.medium))
                    }
                    ForEach(snapshot.upcomingBills.prefix(3)) { bill in
                        HStack {
                            Text(bill.merchant).font(.footnote)
                            Spacer()
                            Text(bill.amount.widgetCurrency(snapshot.currencyCode, cents: true))
                                .font(.footnote.monospacedDigit())
                        }
                        .privacySensitive()
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default: // systemSmall
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Safe Today", systemImage: "sparkles")
                Spacer()
                Text(snapshot.safeToSpendToday.widgetCurrency(snapshot.currencyCode))
                    .font(.system(size: 30, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                PaceText(delta: snapshot.spendPaceDelta).font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).privacySensitive()
        }
    }
}

// MARK: - Spend Pace

struct SpendPaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendPace", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Spend Pace", systemImage: "speedometer")
                Spacer()
                PaceText(delta: entry.snapshot.spendPaceDelta)
                    .font(.title3.bold())
                Text("\(entry.snapshot.budgetSpent.widgetCurrency(entry.snapshot.currencyCode)) of \(entry.snapshot.budgetTotal.widgetCurrency(entry.snapshot.currencyCode))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spend Pace")
        .description("How your spending compares to the ideal pace.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Budget Remaining (ring)

struct BudgetRemainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgetRemaining", provider: SnapshotProvider()) { entry in
            BudgetRingView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget Remaining")
        .description("Monthly budget progress at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct BudgetRingView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var progress: Double {
        guard snapshot.budgetTotal > 0 else { return 0 }
        return (snapshot.budgetSpent as NSDecimalNumber).doubleValue
            / (snapshot.budgetTotal as NSDecimalNumber).doubleValue
    }

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: min(1, progress)) {
                Text("Budget")
            } currentValueLabel: {
                Text(snapshot.budgetRemaining.widgetCurrency(snapshot.currencyCode))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .privacySensitive()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Budget", systemImage: "chart.pie")
                Spacer()
                Gauge(value: min(1, progress)) {
                    EmptyView()
                } currentValueLabel: {
                    Text(snapshot.budgetRemaining.widgetCurrency(snapshot.currencyCode))
                        .font(.caption.bold())
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(progress > 1 ? .red : .mint)
                .privacySensitive()
                Text("remaining").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Net Worth

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorth", provider: SnapshotProvider()) { entry in
            let snapshot = entry.snapshot
            let up = snapshot.netWorthChange30Days >= 0
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Net Worth", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Text(snapshot.netWorth.widgetCurrency(snapshot.currencyCode))
                    .font(.title2.bold())
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Label(
                    snapshot.netWorthChange30Days.widgetCurrency(snapshot.currencyCode) + " · 30d",
                    systemImage: up ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(up ? .green : .red)
                .privacySensitive()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Net Worth")
        .description("Current net worth and 30-day change.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Upcoming Bills

struct UpcomingBillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingBills", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(title: "Upcoming Bills", systemImage: "calendar.badge.clock")
                if entry.snapshot.upcomingBills.isEmpty {
                    Spacer()
                    Text("Nothing due soon").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(entry.snapshot.upcomingBills.prefix(4)) { bill in
                        HStack {
                            Text(bill.merchant).font(.footnote).lineLimit(1)
                            Spacer()
                            Text(bill.dueDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(bill.amount.widgetCurrency(entry.snapshot.currencyCode, cents: true))
                                .font(.footnote.monospacedDigit().weight(.medium))
                                .privacySensitive()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Your next recurring charges.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - AI Alert

struct AIAlertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIAlert", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(title: "Spendrift AI", systemImage: "sparkles")
                Spacer()
                if let alert = entry.snapshot.topAlert {
                    Text(alert.title).font(.subheadline.bold()).lineLimit(2)
                    Text(alert.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text("You're on pace").font(.subheadline.bold())
                    Text("No spending alerts right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI Alert")
        .description("The single most important thing Spendrift noticed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Safe to Spend", as: .systemMedium) {
    SafeToSpendWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: SharedSnapshotStore.placeholder)
}
