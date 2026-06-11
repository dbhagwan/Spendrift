import Charts
import SwiftData
import SwiftUI

struct NetWorthView: View {
    /// Tab roots don't repeat the tab's name; pushed presentations keep it.
    var showsTitle = true

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
    @State private var showSpinView = false

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

    /// What the hero card is showing: the trend line or the allocation ring.
    enum DisplayMode: String, CaseIterable {
        case trend, allocation
    }

    @State private var displayMode: DisplayMode = .trend

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                chartCard
                breakdownCard
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle(showsTitle ? "Net Worth" : "")
        .navigationBarTitleDisplayMode(showsTitle ? .automatic : .inline)
        .fullScreenCover(isPresented: $showSpinView) {
            DonutSpinView(title: "Allocation", slices: allocationSlices)
        }
    }

    // MARK: - Allocation (where the money sits)

    private var allocationAccounts: [Account] {
        accounts.filter { !$0.isHidden && !$0.kind.isLiability && $0.netWorthContribution > 0 }
    }

    private var allocationSlices: [DonutSlice] {
        allocationAccounts.map { account in
            DonutSlice(
                id: account.id.uuidString,
                label: account.name,
                amount: account.netWorthContribution,
                color: account.kind.chartColor,
                systemImage: account.kind.chartSystemImage
            )
        }
    }

    /// Robinhood-style allocation: the ring shows each account's share of
    /// your assets, the rows underneath spell it out. Swapped into the hero
    /// card via the top-right toggle.
    @ViewBuilder
    private var allocationContent: some View {
        let total = allocationAccounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
        if allocationAccounts.isEmpty {
            Text("Connect accounts to see where your money sits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            DonutChart(
                slices: allocationSlices,
                centerCaption: "across accounts",
                showsPercentLabels: true
            )
            .frame(height: 220)
            ForEach(allocationAccounts) { account in
                HStack(spacing: 8) {
                    Circle()
                        .fill(account.kind.chartColor)
                        .frame(width: 8, height: 8)
                    Text("\(account.name) ••\(account.mask)")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if total > 0 {
                        Text((account.netWorthContribution / total).doubleValue.percentString)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    AmountText(amount: account.netWorthContribution, font: .subheadline, showCents: false)
                        .frame(width: 84, alignment: .trailing)
                }
            }
            HStack {
                Spacer()
                Button {
                    showSpinView = true
                } label: {
                    Label("Spin in 3D", systemImage: "rotate.3d")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.glass)
                Spacer()
            }
        }
    }

    /// Top-right toggle between the trend line and the allocation ring.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeButton(.trend, icon: "chart.xyaxis.line", label: "Trend")
            modeButton(.allocation, icon: "chart.pie", label: "Allocation")
        }
        .padding(2)
        .glassEffect(.regular, in: Capsule())
        .sensoryFeedback(.selection, trigger: displayMode)
    }

    private func modeButton(_ mode: DisplayMode, icon: String, label: String) -> some View {
        Button {
            withAnimation(.snappy) { displayMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(displayMode == mode ? Theme.accent : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    displayMode == mode ? AnyShapeStyle(Theme.accent.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        if displayMode == .trend {
                            Text(selectedSnapshot.map { $0.date.shortDay } ?? "Current")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            AmountText(
                                amount: selectedSnapshot?.netWorth ?? currentNetWorth,
                                font: .system(size: 34, weight: .bold),
                                showCents: false
                            )
                        } else {
                            Text("Allocation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(allocationAccounts.count) accounts")
                                .font(.headline)
                        }
                    }
                    Spacer()
                    modeToggle
                }

                if displayMode == .allocation {
                    allocationContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if visibleSnapshots.count > 1 {
                    Chart(visibleSnapshots) { snapshot in
                        AreaMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net worth", snapshot.netWorth.doubleValue)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.chartAreaGradient)

                        LineMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net worth", snapshot.netWorth.doubleValue)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(Theme.heroGradient)

                        if let selectedSnapshot, selectedSnapshot.id == snapshot.id {
                            RuleMark(x: .value("Selected", snapshot.date))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .foregroundStyle(.secondary.opacity(0.5))
                            PointMark(
                                x: .value("Date", snapshot.date),
                                y: .value("Net worth", snapshot.netWorth.doubleValue)
                            )
                            .symbolSize(120)
                            .foregroundStyle(Theme.accent)
                            .annotation(
                                position: .top,
                                spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                HStack(spacing: 6) {
                                    Text(snapshot.date.shortDay)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    AmountText(amount: snapshot.netWorth, font: .caption.bold(), showCents: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: Capsule())
                            }
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
                    .sensoryFeedback(.selection, trigger: selectedSnapshot?.id)
                    .frame(height: 220)
                } else {
                    EmptyStateView(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "Building history",
                        message: "Net worth is snapshotted on every sync — the chart fills in over time."
                    )
                }

                if displayMode == .trend {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
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
