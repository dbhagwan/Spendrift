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

    @State private var showExplanation = false

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
                    message: "Connect a bank account and Spendrift starts learning your spending immediately."
                )
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Spendrift")
        .toolbar {
            // iPad reaches Settings via the sidebar; iPhone gets it here.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .refreshable { await appEnvironment.sync(context: modelContext) }
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

    private var netWorthCard: some View {
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
            Text("\(accounts.filter { !$0.isHidden }.count) accounts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                Text("Scan a receipt and Spendrift matches it to the card charge automatically.")
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
