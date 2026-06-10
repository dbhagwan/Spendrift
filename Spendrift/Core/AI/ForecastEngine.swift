import Foundation

/// Projects end-of-period spend and assesses budget risk.
enum ForecastEngine {
    static func forecast(
        transactions: [Transaction],
        budget: Budget?,
        recurringSeries: [RecurringDetector.RecurringSeries],
        profile: SpendingProfile,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> SpendForecast {
        let period = budget?.period(containing: now)
            ?? DateInterval(start: now.startOfMonth(calendar), end: now.endOfMonth(calendar))
        let elapsedDays = max(1, period.start.daysUntil(now) + 1)
        let totalDays = max(1, period.start.daysUntil(period.end))
        let remainingDays = max(0, totalDays - elapsedDays)

        let periodSpendTxns = transactions.filter { $0.countsAsSpend && period.contains($0.date) && $0.date <= now }
        let spentToDate = periodSpendTxns.reduce(Decimal(0)) { $0 + $1.amount }

        // Upcoming recurring charges within the remainder of the period.
        let upcoming = recurringSeries
            .filter { $0.nextExpectedDate > now && $0.nextExpectedDate <= period.end }
            .map {
                SpendForecast.UpcomingCharge(
                    merchant: $0.merchant,
                    amount: $0.averageAmount,
                    expectedDate: $0.nextExpectedDate,
                    category: $0.category,
                    isDiscretionary: $0.isDiscretionary
                )
            }
        let upcomingTotal = upcoming.reduce(Decimal(0)) { $0 + $1.amount }

        // Variable run-rate projection, blended with historical average when
        // the month is young (early days are noisy).
        let recurringSoFar = periodSpendTxns.filter(\.isRecurring).reduce(Decimal(0)) { $0 + $1.amount }
        let variableSoFar = spentToDate - recurringSoFar
        let variableDailyPace = variableSoFar.doubleValue / Double(elapsedDays)
        let historicalVariableDaily = profile.variableMonthlySpend.doubleValue / Double(totalDays)
        let paceWeight = min(1.0, Double(elapsedDays) / 10.0)
        let blendedDaily = variableDailyPace * paceWeight + historicalVariableDaily * (1 - paceWeight)
        let projectedVariableRemaining = Decimal(blendedDaily * Double(remainingDays))

        let projectedTotal = spentToDate + upcomingTotal + projectedVariableRemaining
        let essentialShare = Decimal(profile.essentialShare)
        let projectedEssential = projectedTotal * essentialShare

        let paycheck = RecurringDetector.detectPaycheck(in: transactions)

        // Confidence grows with history and shrinks with volatility.
        let confidence = max(0.2, min(0.95,
            0.4 + Double(profile.monthsOfHistory) * 0.08 - profile.spendVolatility * 0.5
        ))

        return SpendForecast(
            generatedAt: now,
            periodStart: period.start,
            periodEnd: period.end,
            spentToDate: spentToDate,
            projectedTotalSpend: projectedTotal,
            projectedDiscretionarySpend: projectedTotal - projectedEssential,
            projectedEssentialSpend: projectedEssential,
            upcomingRecurringCharges: upcoming,
            expectedNextPaycheckDate: paycheck?.nextDate,
            expectedNextPaycheckAmount: paycheck?.amount,
            confidence: confidence
        )
    }

    static func assessRisk(
        transactions: [Transaction],
        budget: Budget,
        forecast: SpendForecast,
        asOf now: Date = .now
    ) -> BudgetRiskAssessment {
        let period = DateInterval(start: forecast.periodStart, end: forecast.periodEnd)
        let periodTxns = transactions.filter { $0.countsAsSpend && period.contains($0.date) && $0.date <= now }
        let elapsedFraction = max(0.05, now.timeIntervalSince(period.start) / period.duration)

        var categoryRisks: [BudgetRiskAssessment.CategoryRisk] = []
        for budgetCategory in budget.categories {
            let spent = periodTxns
                .filter { $0.category == budgetCategory.category }
                .reduce(Decimal(0)) { $0 + $1.amount }
            // Naive per-category projection: current pace extended to period end.
            let projected = Decimal(spent.doubleValue / elapsedFraction)
            let utilization = budgetCategory.monthlyLimit > 0
                ? (projected / budgetCategory.monthlyLimit).doubleValue
                : 0
            let risk: BudgetRiskAssessment.RiskLevel = switch utilization {
            case ..<0.9: .onTrack
            case ..<1.05: .watch
            default: .likelyOverspend
            }
            categoryRisks.append(.init(
                category: budgetCategory.category,
                budgeted: budgetCategory.monthlyLimit,
                spent: spent,
                projected: projected,
                risk: risk
            ))
        }

        let utilization = budget.monthlyTotal > 0
            ? (forecast.projectedTotalSpend / budget.monthlyTotal).doubleValue
            : 0
        let overall: BudgetRiskAssessment.RiskLevel = switch utilization {
        case ..<0.95: .onTrack
        case ..<1.05: .watch
        default: .likelyOverspend
        }

        return BudgetRiskAssessment(
            generatedAt: now,
            overallRisk: overall,
            projectedBudgetUtilization: utilization,
            categoryRisks: categoryRisks.sorted { $0.projected - $0.budgeted > $1.projected - $1.budgeted }
        )
    }
}

extension Date {
    func startOfMonth(_ calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: self)) ?? self
    }

    func endOfMonth(_ calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 1, to: startOfMonth(calendar)) ?? self
    }
}
