import SwiftUI

/// Hero card: the one number the product exists to answer.
struct SafeToSpendCard: View {
    var decision: SafeToSpendDecision
    var onExplain: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SAFE TO SPEND TODAY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.6)
                    Spacer()
                    ConfidenceBadge(confidence: decision.confidence)
                }
                AmountText(amount: decision.todayAllowance, font: .system(size: 46, weight: .bold), showCents: false)
                HStack(spacing: 16) {
                    metric("This week", decision.weekAllowance)
                    metric("Rest of month", decision.monthRemainingAllowance)
                    Spacer()
                }
                Button(action: onExplain) {
                    Label("Why this number?", systemImage: "sparkles")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
            }
        }
    }

    private func metric(_ label: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            AmountText(amount: amount, font: .subheadline, showCents: false)
        }
    }
}

/// Explanation drawer: every input to the decision, no black box.
struct SafeToSpendExplanationView: View {
    var decision: SafeToSpendDecision
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Deterministic base") {
                    row("Remaining discretionary budget", decision.remainingDiscretionaryBudget)
                    row("Upcoming recurring (discretionary)", -decision.upcomingRecurringDiscretionary)
                    row("Forecasted essential spend (unreserved)", -decision.forecastedRequiredEssentialSpend)
                    LabeledContent("Days left in period", value: "\(decision.remainingDaysInPeriod)")
                }
                Section("Behavioral adjustment") {
                    LabeledContent("Multiplier", value: decision.behavioralAdjustment.formatted(.number.precision(.fractionLength(2))) + "×")
                    ForEach(decision.adjustmentReasons, id: \.self) { reason in
                        Label(reason, systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !decision.excludedCategories.isEmpty {
                    Section("Excluded categories") {
                        Text(decision.excludedCategories.map(\.displayName).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent("Confidence", value: decision.confidence.percentString)
                    LabeledContent("Computed", value: decision.generatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .navigationTitle("How this is computed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ amount: Decimal) -> some View {
        LabeledContent(label) {
            AmountText(amount: amount, font: .subheadline, colorBySign: true)
        }
    }
}

struct SpendPaceCard: View {
    var forecast: SpendForecast
    var risk: BudgetRiskAssessment

    private var paceDelta: Double {
        let total = max(1, forecast.periodStart.daysUntil(forecast.periodEnd))
        let elapsed = max(1, forecast.periodStart.daysUntil(.now))
        let idealFraction = Double(elapsed) / Double(total)
        let ideal = forecast.projectedTotalSpend.doubleValue * idealFraction
        guard ideal > 0 else { return 0 }
        return forecast.spentToDate.doubleValue / ideal - 1
    }

    var body: some View {
        Card(title: "Spend Pace", systemImage: "speedometer") {
            HStack(alignment: .firstTextBaseline) {
                Text(paceDelta.signedPercentString)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(paceDelta > 0.05 ? Theme.negative : paceDelta < -0.05 ? Theme.positive : .primary)
                Text(paceDelta > 0 ? "over pace" : "under pace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(risk.overallRisk.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(riskColor)
            }
            HStack {
                Text("Spent \(forecast.spentToDate.currencyCompact())")
                Text("·").foregroundStyle(.tertiary)
                Text("Projected \(forecast.projectedTotalSpend.currencyCompact())")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var riskColor: Color {
        switch risk.overallRisk {
        case .onTrack: Theme.positive
        case .watch: Theme.warning
        case .likelyOverspend: Theme.negative
        }
    }
}

struct RecommendationsCard: View {
    var recommendations: [Recommendation]

    var body: some View {
        Card(title: "AI Recommendations", systemImage: "sparkles") {
            ForEach(recommendations.prefix(3)) { recommendation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Theme.severityColor(recommendation.severity))
                            .frame(width: 7, height: 7)
                        Text(recommendation.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        ConfidenceBadge(confidence: recommendation.confidence)
                    }
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !recommendation.evidence.isEmpty {
                        DisclosureGroup {
                            ForEach(recommendation.evidence, id: \.self) { item in
                                Text("• " + item)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } label: {
                            Text("Evidence").font(.caption.weight(.medium))
                        }
                        .tint(.secondary)
                    }
                }
                if recommendation.id != recommendations.prefix(3).last?.id {
                    Divider()
                }
            }
        }
    }
}

struct InsightsCard: View {
    var insights: [SpendingInsight]

    var body: some View {
        Card(title: "Insights", systemImage: "lightbulb") {
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.severityColor(insight.severity))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title).font(.subheadline.weight(.medium))
                        Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct UpcomingBillsCard: View {
    var charges: [SpendForecast.UpcomingCharge]

    var body: some View {
        Card(title: "Upcoming Bills", systemImage: "calendar.badge.clock") {
            ForEach(charges) { charge in
                HStack {
                    Image(systemName: charge.category.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading) {
                        Text(charge.merchant).font(.subheadline.weight(.medium))
                        Text(charge.expectedDate.shortDay).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    AmountText(amount: charge.amount, font: .subheadline)
                }
            }
        }
    }
}

struct CashFlowCard: View {
    var forecast: SpendForecast

    var body: some View {
        Card(title: "Cash Flow", systemImage: "arrow.left.arrow.right") {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent this period").font(.caption).foregroundStyle(.secondary)
                    AmountText(amount: forecast.spentToDate, font: .title3, showCents: false)
                }
                if let paycheck = forecast.expectedNextPaycheckAmount, let date = forecast.expectedNextPaycheckDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next paycheck · \(date.shortDay)").font(.caption).foregroundStyle(.secondary)
                        AmountText(amount: paycheck, font: .title3, showCents: false)
                    }
                }
                Spacer()
            }
        }
    }
}
