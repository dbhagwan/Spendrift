import Charts
import SwiftUI

/// The "Spending DNA" surface — renders the structured SpendingProfile
/// visually: fixed/variable, essential/discretionary, momentum, merchants,
/// timing behavior, and detected overspend triggers.
struct SpendingProfileView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var profile: SpendingProfile? { appEnvironment.pipeline.profile }

    var body: some View {
        ScrollView {
            if let profile {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 340 : 600), spacing: Theme.sectionSpacing)],
                    spacing: Theme.sectionSpacing
                ) {
                    headlineCard(profile)
                    fixedVariableCard(profile)
                    momentumCard(profile)
                    merchantsCard(profile)
                    timingCard(profile)
                    if !profile.overspendTriggers.isEmpty {
                        triggersCard(profile)
                    }
                }
                .padding()
            } else {
                EmptyStateView(
                    systemImage: "chart.xyaxis.line",
                    title: "Profile is still learning",
                    message: "Spendrift builds your spending profile after the first sync."
                )
                .padding(.top, 80)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Spending Profile")
    }

    private func headlineCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Monthly Average", systemImage: "gauge.with.needle") {
            AmountText(amount: profile.averageMonthlySpend, font: .system(size: 36, weight: .bold), showCents: false)
            HStack(spacing: 20) {
                stat("Volatility", profile.spendVolatility.percentString)
                stat("Savings rate", profile.savingsRate.percentString)
                stat("Subscriptions", profile.subscriptionMonthlyLoad.currencyCompact() + "/mo")
            }
            Text("Built from \(profile.monthsOfHistory) months of history")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func fixedVariableCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Fixed vs. Variable", systemImage: "square.stack.3d.up") {
            Chart {
                BarMark(x: .value("Amount", profile.fixedMonthlySpend.doubleValue), y: .value("Type", "Fixed"))
                    .foregroundStyle(Theme.accent)
                BarMark(x: .value("Amount", profile.variableMonthlySpend.doubleValue), y: .value("Type", "Variable"))
                    .foregroundStyle(Theme.accent.opacity(0.45))
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Decimal(amount).currencyCompact())
                        }
                    }
                }
            }
            .frame(height: 110)

            HStack {
                legend("Essential", profile.essentialShare, Theme.accent)
                legend("Discretionary", profile.discretionaryShare, Theme.warning)
                Spacer()
            }
        }
    }

    private func momentumCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Category Momentum", systemImage: "arrow.up.right") {
            if profile.categoryMomentum.isEmpty {
                Text("No notable category movement this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(profile.categoryMomentum.prefix(6)) { momentum in
                    BarMark(
                        x: .value("Change", (momentum.ratioToTrailingAverage - 1) * 100),
                        y: .value("Category", momentum.category.displayName)
                    )
                    .foregroundStyle(momentum.ratioToTrailingAverage > 1 ? Theme.negative : Theme.positive)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let pct = value.as(Double.self) {
                                Text("\(Int(pct))%")
                            }
                        }
                    }
                }
                .frame(height: 160)
                Text("This month's pace vs. your trailing 3-month average")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func merchantsCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Top Merchants", systemImage: "storefront") {
            ForEach(profile.topMerchants.prefix(6)) { merchant in
                HStack {
                    Text(merchant.merchant)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(merchant.transactionsPerMonth.formatted(.number.precision(.fractionLength(1))))×/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(amount: merchant.monthlyAverage, font: .subheadline, showCents: false)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private func timingCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Timing Behavior", systemImage: "clock") {
            HStack(spacing: 20) {
                stat("Weekend share", profile.weekendSpendShare.percentString)
                stat("2nd-half of month", profile.secondHalfOfMonthSpendShare.percentString)
                stat("Dining / week", profile.diningTransactionsPerWeek.formatted(.number.precision(.fractionLength(1))) + "×")
            }
        }
    }

    private func triggersCard(_ profile: SpendingProfile) -> some View {
        Card(title: "Overspend Triggers", systemImage: "exclamationmark.triangle") {
            ForEach(profile.overspendTriggers, id: \.self) { trigger in
                Label(trigger, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func legend(_ label: String, _ share: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(share.percentString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { SpendingProfileView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
