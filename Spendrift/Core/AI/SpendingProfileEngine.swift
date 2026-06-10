import Foundation

/// Builds the structured `SpendingProfile` from transaction history.
/// Deterministic feature computation — the AI narrative layer consumes this,
/// never the raw transactions.
enum SpendingProfileEngine {
    static func build(
        transactions: [Transaction],
        recurringSeries: [RecurringDetector.RecurringSeries],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> SpendingProfile {
        let spend = transactions.filter(\.countsAsSpend)
        let income = transactions.filter { $0.amount < 0 && $0.category == .income }

        // Group spend by calendar month.
        let byMonth = Dictionary(grouping: spend) {
            calendar.dateComponents([.year, .month], from: $0.date)
        }
        let monthlyTotals = byMonth.values.map { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        let monthsOfHistory = max(1, byMonth.count)
        let averageMonthly = monthlyTotals.reduce(0, +) / Decimal(monthsOfHistory)

        // Volatility = coefficient of variation of monthly totals.
        let doubles = monthlyTotals.map(\.doubleValue)
        let mean = doubles.reduce(0, +) / Double(max(1, doubles.count))
        let variance = doubles.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, doubles.count))
        let volatility = mean > 0 ? sqrt(variance) / mean : 0

        let fixed = spend.filter { $0.category.isTypicallyFixed || $0.isRecurring }
        let fixedMonthly = fixed.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(monthsOfHistory)
        let essentialSpend = spend.filter(\.isEssential).reduce(Decimal(0)) { $0 + $1.amount }
        let totalSpend = spend.reduce(Decimal(0)) { $0 + $1.amount }
        let essentialShare = totalSpend > 0 ? (essentialSpend / totalSpend).doubleValue : 0

        let totalIncome = income.reduce(Decimal(0)) { $0 - $1.amount }
        let savingsRate = totalIncome > 0 ? ((totalIncome - totalSpend) / totalIncome).doubleValue : 0

        // Subscription load now vs. ~3 months ago.
        let subscriptionSeries = recurringSeries.filter { $0.category == .subscriptions }
        let monthlyFactor = { (cadence: Int) in Decimal(30) / Decimal(max(1, cadence)) }
        let subscriptionLoad = subscriptionSeries.reduce(Decimal(0)) { $0 + $1.averageAmount * monthlyFactor($1.cadenceDays) }
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        let oldSubscriptionSpend = spend
            .filter { $0.category == .subscriptions && $0.date < threeMonthsAgo }
        let oldMonths = max(1, monthsOfHistory - 3)
        let oldLoad = oldSubscriptionSpend.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(oldMonths)

        // Category and merchant rollups.
        let byCategory = Dictionary(grouping: spend, by: \.category)
        let topCategories = byCategory
            .map { SpendingProfile.CategorySpend(category: $0.key, monthlyAverage: $0.value.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(monthsOfHistory)) }
            .sorted { $0.monthlyAverage > $1.monthlyAverage }
            .prefix(6)

        let byMerchant = Dictionary(grouping: spend, by: \.normalizedDescription)
        let topMerchants = byMerchant
            .map { merchant, txns in
                SpendingProfile.MerchantSpend(
                    merchant: merchant,
                    monthlyAverage: txns.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(monthsOfHistory),
                    transactionsPerMonth: Double(txns.count) / Double(monthsOfHistory)
                )
            }
            .sorted { $0.monthlyAverage > $1.monthlyAverage }
            .prefix(8)

        // Momentum: current month vs. trailing 3-month average per category.
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: now)
        let dayOfMonth = max(1, calendar.component(.day, from: now))
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        var momentum: [SpendingProfile.CategoryMomentum] = []
        for (category, txns) in byCategory {
            let current = txns
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == currentMonthComponents }
                .reduce(Decimal(0)) { $0 + $1.amount }
            // Project the partial month to a full-month pace before comparing.
            let projectedCurrent = current.doubleValue / Double(dayOfMonth) * Double(daysInMonth)
            let trailing = txns
                .filter { $0.date >= threeMonthsAgo && calendar.dateComponents([.year, .month], from: $0.date) != currentMonthComponents }
                .reduce(Decimal(0)) { $0 + $1.amount }
            let trailingMonthly = trailing.doubleValue / 3
            guard trailingMonthly > 20 else { continue } // skip noise categories
            momentum.append(.init(category: category, ratioToTrailingAverage: projectedCurrent / trailingMonthly))
        }

        // Timing behavior.
        let weekendSpend = spend.filter { calendar.isDateInWeekend($0.date) }.reduce(Decimal(0)) { $0 + $1.amount }
        let secondHalfSpend = spend.filter { calendar.component(.day, from: $0.date) > 15 }.reduce(Decimal(0)) { $0 + $1.amount }
        let weeks = max(1.0, Double(monthsOfHistory) * 4.33)
        let diningPerWeek = Double(spend.filter { $0.category == .dining }.count) / weeks

        var triggers: [String] = []
        if totalSpend > 0, (secondHalfSpend / totalSpend).doubleValue > 0.58 {
            triggers.append("Spending accelerates in the second half of the month")
        }
        if totalSpend > 0, (weekendSpend / totalSpend).doubleValue > 0.42 {
            triggers.append("Weekend spending runs well above weekday levels")
        }
        if diningPerWeek > 5 {
            triggers.append("High-frequency dining (\(Int(diningPerWeek.rounded()))×/week)")
        }

        return SpendingProfile(
            generatedAt: now,
            monthsOfHistory: monthsOfHistory,
            averageMonthlySpend: averageMonthly,
            spendVolatility: volatility,
            fixedMonthlySpend: fixedMonthly,
            variableMonthlySpend: max(0, averageMonthly - fixedMonthly),
            essentialShare: essentialShare,
            discretionaryShare: max(0, 1 - essentialShare),
            savingsRate: savingsRate,
            subscriptionMonthlyLoad: subscriptionLoad,
            subscriptionMonthlyLoadChange: subscriptionLoad - oldLoad,
            topCategories: Array(topCategories),
            topMerchants: Array(topMerchants),
            categoryMomentum: momentum.sorted { $0.ratioToTrailingAverage > $1.ratioToTrailingAverage },
            weekendSpendShare: totalSpend > 0 ? (weekendSpend / totalSpend).doubleValue : 0,
            secondHalfOfMonthSpendShare: totalSpend > 0 ? (secondHalfSpend / totalSpend).doubleValue : 0,
            diningTransactionsPerWeek: diningPerWeek,
            overspendTriggers: triggers
        )
    }
}
