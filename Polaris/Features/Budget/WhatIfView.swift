import SwiftUI

/// The "what if" coach: drag a spending lever, watch the math move live.
/// Every number is deterministic — derived from the spending profile and the
/// current forecast — so the answer is explainable, not vibes.
struct WhatIfView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Fraction (0...0.5) the user is trying cutting, per category.
    @State private var cuts: [SpendingCategory: Double] = [:]

    private var levers: [SpendingProfile.CategorySpend] {
        guard let profile = appEnvironment.pipeline.profile else { return [] }
        return Array(
            profile.topCategories
                .filter { !$0.category.isTypicallyFixed && $0.category != .groceries && $0.monthlyAverage > 0 }
                .prefix(4)
        )
    }

    private var monthlySavings: Decimal {
        levers.reduce(Decimal(0)) { total, lever in
            total + lever.monthlyAverage * Decimal(cuts[lever.category] ?? 0)
        }
    }

    private var dailyBoost: Decimal {
        let days = appEnvironment.pipeline.forecast.map { max(1, Date.now.daysUntil($0.periodEnd)) } ?? 30
        return monthlySavings / Decimal(days)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                Card(title: "If You Cut…", systemImage: "slider.horizontal.3") {
                    if levers.isEmpty {
                        Text("Polaris needs a bit more history before it can model cuts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(levers) { lever in
                            leverRow(lever)
                        }
                    }
                }
                resultCard
                Card {
                    Label {
                        Text("Levers are your top discretionary categories; numbers come straight from your spending profile and the live forecast.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("What If")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: monthlySavings)
    }

    private func leverRow(_ lever: SpendingProfile.CategorySpend) -> some View {
        let cut = cuts[lever.category] ?? 0
        return VStack(spacing: 4) {
            HStack {
                Label(lever.category.displayName, systemImage: lever.category.systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(cut == 0 ? "—" : "−\(cut.percentString)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(cut == 0 ? .secondary : Theme.positive)
            }
            Slider(
                value: Binding(
                    get: { cuts[lever.category] ?? 0 },
                    set: { cuts[lever.category] = $0 }
                ),
                in: 0...0.5,
                step: 0.05
            )
            .tint(lever.category.chartColor)
            HStack {
                Text("\(lever.monthlyAverage.currency(showCents: false))/mo today")
                Spacer()
                if cut > 0 {
                    Text("saves \((lever.monthlyAverage * Decimal(cut)).currency(showCents: false))/mo")
                        .foregroundStyle(Theme.positive)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var resultCard: some View {
        Card(title: "You'd Free Up", systemImage: "arrow.up.heart") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AmountText(
                    amount: dailyBoost,
                    font: .system(size: 40, weight: .bold),
                    style: AnyShapeStyle(Theme.heroGradient)
                )
                Text("/day safe to spend")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per month").font(.caption2).foregroundStyle(.secondary)
                    AmountText(amount: monthlySavings, font: .subheadline, showCents: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per year").font(.caption2).foregroundStyle(.secondary)
                    AmountText(amount: monthlySavings * 12, font: .subheadline, showCents: false)
                }
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack { WhatIfView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
