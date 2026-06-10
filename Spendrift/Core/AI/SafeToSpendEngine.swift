import Foundation

/// The signature feature: hybrid deterministic + behavioral safe-to-spend.
///
/// Deterministic layer:
///   (remaining discretionary budget
///    − upcoming recurring discretionary obligations
///    − forecasted required essential spend not yet covered by category budgets)
///   ÷ remaining days in the budget period
///
/// Behavioral adjustment layer (bounded, always explained):
///   • down-weight when discretionary acceleration is detected
///   • up-weight when meaningfully under pace
///   • down-weight in the user's historical overspend window (e.g. last week
///     of the month for back-loaded spenders)
enum SafeToSpendEngine {
    struct Configuration: Sendable {
        /// Clamp on the AI adjustment so the number stays trustworthy.
        var minAdjustment: Double = 0.7
        var maxAdjustment: Double = 1.2
        /// Momentum ratio above which a category is "accelerating".
        var accelerationThreshold: Double = 1.2
        /// Pace utilization below which the user is "under pace".
        var underPaceThreshold: Double = 0.85

        static let `default` = Configuration()
    }

    static func decide(
        budget: Budget,
        forecast: SpendForecast,
        profile: SpendingProfile,
        transactions: [Transaction],
        excludedCategories: [SpendingCategory] = [],
        configuration: Configuration = .default,
        asOf now: Date = .now
    ) -> SafeToSpendDecision {
        let period = DateInterval(start: forecast.periodStart, end: forecast.periodEnd)
        let remainingDays = max(1, now.daysUntil(period.end))
        let totalDays = max(1, period.start.daysUntil(period.end))
        let elapsedFraction = 1 - Double(remainingDays) / Double(totalDays)

        // --- Deterministic layer ---
        let discretionaryCategories = SpendingCategory.allCases.filter {
            $0.isDiscretionaryByDefault && !excludedCategories.contains($0)
        }
        let discretionaryBudget = discretionaryBudgetTotal(budget: budget, categories: discretionaryCategories)

        let periodTxns = transactions.filter { period.contains($0.date) && $0.date <= now }
        let discretionarySpent = periodTxns
            .filter { $0.countsAsSpend && discretionaryCategories.contains($0.category) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let remainingDiscretionary = max(0, discretionaryBudget - discretionarySpent)

        let upcomingDiscretionary = forecast.upcomingRecurringCharges
            .filter { $0.isDiscretionary && !excludedCategories.contains($0.category) }
            .reduce(Decimal(0)) { $0 + $1.amount }

        // Essential spend the budget hasn't explicitly reserved for.
        let essentialBudgeted = budget.categories
            .filter { !$0.category.isDiscretionaryByDefault }
            .reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        let essentialRemaining = max(0, forecast.projectedEssentialSpend - forecast.spentToDate * Decimal(profile.essentialShare))
        let unreservedEssential = max(0, essentialRemaining - essentialBudgeted)

        let baseRemaining = max(0, remainingDiscretionary - upcomingDiscretionary - unreservedEssential)
        let baseDaily = baseRemaining / Decimal(remainingDays)

        // --- Behavioral adjustment layer ---
        var adjustment = 1.0
        var reasons: [String] = []

        let accelerating = profile.categoryMomentum.filter {
            $0.ratioToTrailingAverage > configuration.accelerationThreshold
                && discretionaryCategories.contains($0.category)
        }
        if let worst = accelerating.first {
            let pct = Int((worst.ratioToTrailingAverage - 1) * 100)
            adjustment -= 0.10
            reasons.append("\(worst.category.displayName) pace +\(pct)% vs. 3-month average → allowance reduced 10%")
        }

        let idealSpendSoFar = budget.monthlyTotal * Decimal(elapsedFraction)
        if idealSpendSoFar > 0 {
            let paceUtilization = (forecast.spentToDate / idealSpendSoFar).doubleValue
            if paceUtilization < configuration.underPaceThreshold {
                adjustment += 0.10
                reasons.append("Spending \(Int((1 - paceUtilization) * 100))% under pace → allowance increased 10%")
            }
        }

        let inFinalWeek = remainingDays <= 7
        if inFinalWeek && profile.secondHalfOfMonthSpendShare > 0.58 {
            adjustment -= 0.10
            reasons.append("You historically overspend late in the month → allowance reduced 10%")
        }

        adjustment = min(configuration.maxAdjustment, max(configuration.minAdjustment, adjustment))
        if reasons.isEmpty { reasons.append("No behavioral adjustment — spending pattern is steady") }

        let today = max(0, baseDaily * Decimal(adjustment))
        let week = max(0, today * Decimal(min(7, remainingDays)))
        let monthRemaining = max(0, baseRemaining * Decimal(adjustment))

        let confidence = min(0.95, forecast.confidence * (budget.categories.isEmpty ? 0.85 : 1.0))

        return SafeToSpendDecision(
            generatedAt: now,
            todayAllowance: today,
            weekAllowance: week,
            monthRemainingAllowance: monthRemaining,
            confidence: confidence,
            remainingDiscretionaryBudget: remainingDiscretionary,
            upcomingRecurringDiscretionary: upcomingDiscretionary,
            forecastedRequiredEssentialSpend: unreservedEssential,
            remainingDaysInPeriod: remainingDays,
            behavioralAdjustment: adjustment,
            adjustmentReasons: reasons,
            excludedCategories: excludedCategories
        )
    }

    /// Discretionary slice of the budget: explicit category budgets when set,
    /// otherwise the profile-typical discretionary share of the total.
    private static func discretionaryBudgetTotal(
        budget: Budget,
        categories: [SpendingCategory]
    ) -> Decimal {
        let explicit = budget.categories.filter { categories.contains($0.category) }
        if !explicit.isEmpty {
            return explicit.reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        }
        // No category budgets yet: assume 45% of total is discretionary.
        return budget.monthlyTotal * Decimal(0.45)
    }
}
