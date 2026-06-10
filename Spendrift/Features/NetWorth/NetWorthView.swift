import Charts
import SwiftData
import SwiftUI

struct NetWorthView: View {
    enum Range: String, CaseIterable {
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case yearToDate = "YTD"
        case oneYear = "1Y"
        case all = "All"

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: .now)
            case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now)
            case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
            case .yearToDate: return calendar.date(from: calendar.dateComponents([.year], from: .now))
            case .oneYear: return calendar.date(byAdding: .year, value: -1, to: .now)
            case .all: return nil
            }
        }
    }

    @Query(sort: \NetWorthSnapshot.date) private var snapshots: [NetWorthSnapshot]
    @Query private var accounts: [Account]

    @State private var range: Range = .threeMonths
    @State private var selectedDate: Date?

    private var visibleSnapshots: [NetWorthSnapshot] {
        guard let start = range.startDate else { return snapshots }
        return snapshots.filter { $0.date >= start }
    }

    private var currentNetWorth: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
    }

    private var selectedSnapshot: NetWorthSnapshot? {
        guard let selectedDate else { return nil }
        return visibleSnapshots.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                chartCard
                breakdownCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Net Worth")
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSnapshot.map { $0.date.shortDay } ?? "Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(
                        amount: selectedSnapshot?.netWorth ?? currentNetWorth,
                        font: .system(size: 34, weight: .bold),
                        showCents: false
                    )
                }

                if visibleSnapshots.count > 1 {
                    Chart(visibleSnapshots) { snapshot in
                        LineMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net worth", snapshot.netWorth.doubleValue)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)

                        AreaMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net worth", snapshot.netWorth.doubleValue)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent.opacity(0.08))

                        if let selectedSnapshot, selectedSnapshot.id == snapshot.id {
                            RuleMark(x: .value("Selected", snapshot.date))
                                .foregroundStyle(.secondary.opacity(0.4))
                            PointMark(
                                x: .value("Date", snapshot.date),
                                y: .value("Net worth", snapshot.netWorth.doubleValue)
                            )
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(Decimal(amount).currencyCompact())
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 220)
                } else {
                    EmptyStateView(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "Building history",
                        message: "Net worth is snapshotted on every sync — the chart fills in over time."
                    )
                }

                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var breakdownCard: some View {
        Card(title: "Breakdown", systemImage: "building.columns") {
            let assets = accounts.filter { !$0.kind.isLiability && !$0.isHidden }
            let liabilities = accounts.filter { $0.kind.isLiability && !$0.isHidden }

            sectionRow("Assets", assets.reduce(Decimal(0)) { $0 + $1.currentBalance }, Theme.positive)
            ForEach(assets) { account in accountRow(account, negative: false) }
            Divider()
            sectionRow("Liabilities", -liabilities.reduce(Decimal(0)) { $0 + $1.currentBalance }, Theme.negative)
            ForEach(liabilities) { account in accountRow(account, negative: true) }
        }
    }

    private func sectionRow(_ label: String, _ amount: Decimal, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.semibold))
            Spacer()
            AmountText(amount: amount, font: .subheadline)
        }
        .foregroundStyle(color)
    }

    private func accountRow(_ account: Account, negative: Bool) -> some View {
        HStack {
            Text("\(account.name) ••\(account.mask)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            AmountText(amount: negative ? -account.currentBalance : account.currentBalance, font: .subheadline)
        }
    }
}

#Preview {
    NavigationStack { NetWorthView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
