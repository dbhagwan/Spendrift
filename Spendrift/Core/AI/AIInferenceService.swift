import Foundation

/// Boundary for model-backed inference. Implementations must return validated
/// structured values — the app never renders raw model text.
///
/// `FoundationModelsAIService` is the production implementation: all inference
/// runs on-device via Apple's Foundation Models framework. `MockAIService`
/// provides the deterministic heuristics used in previews and as the runtime
/// fallback when the on-device model is unavailable.
protocol AIInferenceService: Sendable {
    func classifyTransaction(
        merchant: String,
        rawDescription: String,
        amount: Decimal
    ) async -> (category: SpendingCategory, subcategory: String?, confidence: Double)

    /// Structured extraction from raw receipt OCR text, used when the
    /// deterministic parser's confidence is low.
    func extractReceipt(ocrText: String) async -> ReceiptExtraction?

    /// Turns computed profile/forecast/risk structures into concise,
    /// evidence-tied insight and recommendation copy.
    func generateNarratives(
        profile: SpendingProfile,
        forecast: SpendForecast,
        risk: BudgetRiskAssessment
    ) async -> (insights: [SpendingInsight], recommendations: [Recommendation])
}

/// Deterministic mock used in previews, tests, and before the backend exists.
/// Heuristics here intentionally mirror the shapes of real outputs.
struct MockAIService: AIInferenceService {
    func classifyTransaction(
        merchant: String,
        rawDescription: String,
        amount: Decimal
    ) async -> (category: SpendingCategory, subcategory: String?, confidence: Double) {
        // Cheap heuristic stand-in for the real classifier.
        if amount < 0 { return (.income, nil, 0.6) }
        if amount < 20 { return (.dining, nil, 0.45) }
        if amount > 800 { return (.housing, nil, 0.4) }
        return (.shopping, nil, 0.4)
    }

    func extractReceipt(ocrText: String) async -> ReceiptExtraction? {
        // The deterministic ReceiptParser handles mock flows; no fallback needed.
        nil
    }

    func generateNarratives(
        profile: SpendingProfile,
        forecast: SpendForecast,
        risk: BudgetRiskAssessment
    ) async -> (insights: [SpendingInsight], recommendations: [Recommendation]) {
        var insights: [SpendingInsight] = []
        var recommendations: [Recommendation] = []
        let now = Date.now

        for momentum in profile.categoryMomentum where momentum.ratioToTrailingAverage > 1.15 {
            let pct = Int((momentum.ratioToTrailingAverage - 1) * 100)
            insights.append(SpendingInsight(
                generatedAt: now,
                title: "\(momentum.category.displayName) is \(pct)% above your average",
                detail: "This month's \(momentum.category.displayName.lowercased()) pace is running \(pct)% above your trailing 3-month average.",
                severity: pct > 30 ? .critical : .warning,
                category: momentum.category,
                evidence: ["This month vs. trailing 3-month average: \(momentum.ratioToTrailingAverage.formatted(.number.precision(.fractionLength(2))))×"],
                confidence: min(0.95, 0.6 + Double(profile.monthsOfHistory) * 0.05)
            ))
        }

        if profile.subscriptionMonthlyLoadChange > 5 {
            insights.append(SpendingInsight(
                generatedAt: now,
                title: "Subscription load up \(profile.subscriptionMonthlyLoadChange.currency(showCents: false))/month",
                detail: "Your recurring subscriptions increased versus three months ago.",
                severity: .warning,
                category: .subscriptions,
                evidence: ["Current load: \(profile.subscriptionMonthlyLoad.currency())/month"],
                confidence: 0.85
            ))
        }

        if profile.savingsRate > 0 {
            insights.append(SpendingInsight(
                generatedAt: now,
                title: "Savings rate at \(profile.savingsRate.percentString)",
                detail: "You're keeping \(profile.savingsRate.percentString) of income after spend this period.",
                severity: .positive,
                category: nil,
                evidence: ["(income − spend) / income over the current period"],
                confidence: 0.8
            ))
        }

        for categoryRisk in risk.categoryRisks where categoryRisk.risk == .likelyOverspend {
            let overage = categoryRisk.projected - categoryRisk.budgeted
            recommendations.append(Recommendation(
                generatedAt: now,
                title: "Rein in \(categoryRisk.category.displayName.lowercased()) to stay on budget",
                detail: "Projected \(categoryRisk.category.displayName.lowercased()) spend is \(overage.currency(showCents: false)) over its budget. Pausing discretionary \(categoryRisk.category.displayName.lowercased()) for a few days returns you to pace.",
                severity: .warning,
                evidence: [
                    "Budgeted: \(categoryRisk.budgeted.currency(showCents: false))",
                    "Spent so far: \(categoryRisk.spent.currency(showCents: false))",
                    "Projected: \(categoryRisk.projected.currency(showCents: false))",
                ],
                confidence: forecast.confidence,
                relatedCategory: categoryRisk.category
            ))
        }

        if recommendations.isEmpty && risk.overallRisk == .onTrack {
            recommendations.append(Recommendation(
                generatedAt: now,
                title: "You're on pace — nothing to change",
                detail: "Spending is tracking within budget. Keep your current pace.",
                severity: .positive,
                evidence: ["Projected budget utilization: \(risk.projectedBudgetUtilization.percentString)"],
                confidence: forecast.confidence,
                relatedCategory: nil
            ))
        }

        return (insights, recommendations)
    }
}
