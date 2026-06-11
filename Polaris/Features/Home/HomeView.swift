import SwiftData
import SwiftUI

/// The AI command center: safe-to-spend hero, pace, alerts, budget health,
/// receipt matches, upcoming bills, net worth and cash flow at a glance.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: \NetWorthSnapshot.date, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]
    @Query private var accounts: [Account]
    @Query(sort: \Receipt.capturedAt, order: .reverse) private var receipts: [Receipt]
    @Query private var transactions: [Transaction]

    @State private var showExplanation = false
    @Namespace private var zoomNamespace

    private var pipeline: AIPipeline { appEnvironment.pipeline }
    private var isLoading: Bool {
        if case .syncing = appEnvironment.syncState { return pipeline.lastRunAt == nil }
        return false
    }

    var body: some View {
        ScrollView {
            if isLoading {
                loadingSkeleton
            } else if accounts.isEmpty {
                EmptyStateView(
                    systemImage: "building.columns",
                    title: "No accounts yet",
                    message: "Connect a bank account and Polaris starts learning your spending immediately."
                )
            } else {
                content
            }
        }
        .background(AppBackground())
        .toolbar {
            // iPad reaches Settings via the sidebar; iPhone gets it here.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .refreshable { await appEnvironment.sync(context: modelContext) }
        .sensoryFeedback(.impact(weight: .light), trigger: showExplanation)
        .sheet(isPresented: $showExplanation) {
            if let decision = pipeline.safeToSpend {
                SafeToSpendExplanationView(decision: decision)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var content: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 360 : 600), spacing: Theme.sectionSpacing)],
            spacing: Theme.sectionSpacing
        ) {
            if let decision = pipeline.safeToSpend {
                SafeToSpendCard(decision: decision) { showExplanation = true }
            }
            if let forecast = pipeline.forecast, let risk = pipeline.risk {
                SpendPaceCard(forecast: forecast, risk: risk)
            }
            if !dailySpend.isEmpty {
                DailySpendCard(days: dailySpend)
            }
            if !pipeline.recommendations.isEmpty {
                RecommendationsCard(recommendations: pipeline.recommendations)
            }
            if let forecast = pipeline.forecast, !forecast.upcomingRecurringCharges.isEmpty {
                UpcomingBillsCard(charges: Array(forecast.upcomingRecurringCharges.prefix(4)))
            }
            recentReceiptsCard
            netWorthCard
            if let forecast = pipeline.forecast {
                CashFlowCard(forecast: forecast)
            }
            if !pipeline.insights.isEmpty {
                InsightsCard(insights: Array(pipeline.insights.prefix(3)))
            }
        }
        // Cards drift in and fade as they scroll — part of the alive feel.
        .scrollTransition(.interactive) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.85)
                .scaleEffect(phase.isIdentity ? 1 : 0.98)
        }
        .padding()
    }

    private var loadingSkeleton: some View {
        VStack(spacing: Theme.sectionSpacing) {
            SkeletonBlock(height: 160)
            SkeletonBlock(height: 90)
            SkeletonBlock(height: 120)
            SkeletonBlock(height: 90)
        }
        .padding()
    }

    /// Every calendar day of the last two weeks (zero-filled so quiet days
    /// still draw), spend only.
    private var dailySpend: [DailySpendChart.Day] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -13, to: Date.now.startOfDay) ?? .now
        var totals: [Date: Decimal] = [:]
        for offset in 0...13 {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                totals[day] = 0
            }
        }
        for transaction in transactions where transaction.countsAsSpend && transaction.date >= start {
            totals[transaction.date.startOfDay, default: 0] += transaction.amount
        }
        return totals.map { DailySpendChart.Day(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Tapping opens the full Net Worth view — front and center, not buried
    /// in Settings. Zooms out of the card (iOS 18+ zoom transition).
    private var netWorthCard: some View {
        NavigationLink {
            NetWorthView()
                .navigationTransition(.zoom(sourceID: "netWorth", in: zoomNamespace))
        } label: {
            Card(title: "Net Worth", systemImage: "chart.line.uptrend.xyaxis") {
                let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
                HStack(alignment: .firstTextBaseline) {
                    AmountText(amount: netWorth, font: .title2, showCents: false)
                    Spacer()
                    if let change = netWorthChange30Days {
                        Label(change.currencyCompact(), systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                HStack {
                    Text("\(accounts.filter { !$0.isHidden }.count) accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "netWorth", in: zoomNamespace)
    }

    private var netWorthChange30Days: Decimal? {
        guard let latest = netWorthSnapshots.first else { return nil }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        guard let old = netWorthSnapshots.first(where: { $0.date <= thirtyDaysAgo }) else { return nil }
        return latest.netWorth - old.netWorth
    }

    private var recentReceiptsCard: some View {
        Card(title: "Receipts", systemImage: "doc.text.viewfinder") {
            let recent = Array(receipts.prefix(3))
            if recent.isEmpty {
                Text("Scan a receipt and Polaris matches it to the card charge automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { receipt in
                    HStack {
                        Image(systemName: receipt.matchStatus == .unmatched ? "questionmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(receipt.matchStatus == .unmatched ? Theme.warning : Theme.positive)
                        VStack(alignment: .leading) {
                            Text(receipt.merchant ?? "Unknown merchant").font(.subheadline.weight(.medium))
                            Text(receipt.matchStatus.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let total = receipt.total {
                            AmountText(amount: total, font: .subheadline)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
