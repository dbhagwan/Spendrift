import SwiftData
import SwiftUI

struct BudgetView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [Budget]

    @State private var showEditor = false

    private var budget: Budget? { budgets.first }
    private var risk: BudgetRiskAssessment? { appEnvironment.pipeline.risk }
    private var forecast: SpendForecast? { appEnvironment.pipeline.forecast }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                if let budget {
                    overviewCard(budget)
                    if let risk, !risk.categoryRisks.isEmpty {
                        categoriesCard(risk)
                    }
                    safeToSpendLinkCard
                } else {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "No budget yet",
                        message: "Set a monthly budget — or let Spendrift recommend one from your spending history.",
                        actionTitle: "Set up budget",
                        action: { showEditor = true }
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Budget")
        .toolbar {
            if budget != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            BudgetEditorView(existing: budget)
        }
    }

    private func overviewCard(_ budget: Budget) -> some View {
        Card(title: "This Period", systemImage: "chart.pie") {
            let spent = forecast?.spentToDate ?? 0
            let remaining = max(0, budget.monthlyTotal - spent)
            let progress = budget.monthlyTotal > 0 ? (spent / budget.monthlyTotal).doubleValue : 0

            HStack(spacing: 16) {
                ProgressRing(progress: progress, lineWidth: 9, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    AmountText(amount: remaining, font: .title2, showCents: false)
                    Text("left of \(budget.monthlyTotal.currency(showCents: false))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let forecast {
                        let projected = forecast.projectedTotalSpend
                        Text("Projected: \(projected.currency(showCents: false))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(projected > budget.monthlyTotal ? Theme.negative : Theme.positive)
                    }
                }
                Spacer()
            }
        }
    }

    private func categoriesCard(_ risk: BudgetRiskAssessment) -> some View {
        Card(title: "Categories", systemImage: "square.grid.2x2") {
            ForEach(risk.categoryRisks) { categoryRisk in
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: categoryRisk.category.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(categoryRisk.category.displayName).font(.subheadline)
                        Spacer()
                        Text("\(categoryRisk.spent.currencyCompact()) / \(categoryRisk.budgeted.currencyCompact())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        let utilization = categoryRisk.budgeted > 0
                            ? min(1.5, (categoryRisk.spent / categoryRisk.budgeted).doubleValue)
                            : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(color(for: categoryRisk.risk))
                                .frame(width: proxy.size.width * min(1, utilization))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var safeToSpendLinkCard: some View {
        Card {
            Label {
                Text("Changing your budget recomputes safe-to-spend instantly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            }
        }
    }

    private func color(for risk: BudgetRiskAssessment.RiskLevel) -> Color {
        switch risk {
        case .onTrack: Theme.accent
        case .watch: Theme.warning
        case .likelyOverspend: Theme.negative
        }
    }
}

struct BudgetEditorView: View {
    var existing: Budget?

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var total: Double = 3500
    @State private var categoryLimits: [SpendingCategory: Double] = [:]

    private var recommendedTotal: Double? {
        appEnvironment.pipeline.profile.map { ($0.averageMonthlySpend.doubleValue / 100).rounded() * 100 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly total") {
                    HStack {
                        Slider(value: $total, in: 500...15000, step: 100)
                        Text(Decimal(total).currency(showCents: false))
                            .font(.headline)
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    if let recommendedTotal {
                        Button {
                            total = recommendedTotal
                        } label: {
                            Label("Use AI recommendation: \(Decimal(recommendedTotal).currency(showCents: false))", systemImage: "sparkles")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Category budgets (optional)") {
                    ForEach(SpendingCategory.allCases.filter { !$0.isExcludedFromSpend }) { category in
                        HStack {
                            Label(category.displayName, systemImage: category.systemImage)
                                .font(.subheadline)
                            Spacer()
                            TextField(
                                "—",
                                value: Binding(
                                    get: { categoryLimits[category] },
                                    set: { categoryLimits[category] = $0 }
                                ),
                                format: .number.precision(.fractionLength(0))
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard let existing else {
            if let recommendedTotal { total = recommendedTotal }
            return
        }
        total = existing.monthlyTotal.doubleValue
        for category in existing.categories {
            categoryLimits[category.category] = category.monthlyLimit.doubleValue
        }
    }

    private func save() {
        let budget = existing ?? Budget(monthlyTotal: Decimal(total))
        if existing == nil { modelContext.insert(budget) }
        budget.monthlyTotal = Decimal(total)
        budget.updatedAt = .now

        for (category, limit) in categoryLimits {
            if let existingCategory = budget.categories.first(where: { $0.category == category }) {
                existingCategory.monthlyLimit = Decimal(limit)
                existingCategory.isAIRecommended = false
            } else if limit > 0 {
                budget.categories.append(BudgetCategory(category: category, monthlyLimit: Decimal(limit)))
            }
        }
        budget.categories.removeAll { categoryLimits[$0.category] == 0 }

        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
        dismiss()
    }
}

#Preview {
    NavigationStack { BudgetView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
