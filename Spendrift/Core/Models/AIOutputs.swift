import Foundation

// Structured AI output objects. Every AI stage produces one of these validated
// value types — the UI never renders raw model text. All are Codable so they
// can round-trip through the backend, local cache, and widget snapshot store.

/// Continuously updated structured model of the user's financial behavior.
struct SpendingProfile: Codable, Sendable, Equatable {
    var generatedAt: Date
    /// Months of history the profile was computed from.
    var monthsOfHistory: Int

    var averageMonthlySpend: Decimal
    /// Coefficient of variation of monthly spend (0 = perfectly steady).
    var spendVolatility: Double
    var fixedMonthlySpend: Decimal
    var variableMonthlySpend: Decimal
    var essentialShare: Double      // 0...1 of total spend
    var discretionaryShare: Double  // 0...1 of total spend
    var savingsRate: Double         // (income - spend) / income, may be negative
    var subscriptionMonthlyLoad: Decimal
    var subscriptionMonthlyLoadChange: Decimal // vs. 3 months ago

    var topCategories: [CategorySpend]
    var topMerchants: [MerchantSpend]
    var categoryMomentum: [CategoryMomentum]

    var weekendSpendShare: Double          // 0...1 of weekly spend on Sat+Sun
    var secondHalfOfMonthSpendShare: Double // 0...1 — >0.5 means back-loaded months
    var diningTransactionsPerWeek: Double
    /// Detected behavioral patterns that tend to precede overspend, as short
    /// evidence-backed labels (e.g. "late-night delivery orders").
    var overspendTriggers: [String]

    struct CategorySpend: Codable, Sendable, Equatable, Identifiable {
        var category: SpendingCategory
        var monthlyAverage: Decimal
        var id: String { category.rawValue }
    }

    struct MerchantSpend: Codable, Sendable, Equatable, Identifiable {
        var merchant: String
        var monthlyAverage: Decimal
        var transactionsPerMonth: Double
        var id: String { merchant }
    }

    struct CategoryMomentum: Codable, Sendable, Equatable, Identifiable {
        var category: SpendingCategory
        /// Recent-month spend vs. trailing-3-month average, e.g. 1.27 = +27%.
        var ratioToTrailingAverage: Double
        var id: String { category.rawValue }
    }
}

/// Forecast for the current budget period.
struct SpendForecast: Codable, Sendable, Equatable {
    var generatedAt: Date
    var periodStart: Date
    var periodEnd: Date
    var spentToDate: Decimal
    var projectedTotalSpend: Decimal
    var projectedDiscretionarySpend: Decimal
    var projectedEssentialSpend: Decimal
    var upcomingRecurringCharges: [UpcomingCharge]
    var expectedNextPaycheckDate: Date?
    var expectedNextPaycheckAmount: Decimal?
    /// 0...1 — how much history/regularity backs this forecast.
    var confidence: Double

    struct UpcomingCharge: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var merchant: String
        var amount: Decimal
        var expectedDate: Date
        var category: SpendingCategory
        var isDiscretionary: Bool
    }
}

/// Per-category overspend risk for the current period.
struct BudgetRiskAssessment: Codable, Sendable, Equatable {
    var generatedAt: Date
    var overallRisk: RiskLevel
    /// Projected total spend / total budget. >1 means projected overspend.
    var projectedBudgetUtilization: Double
    var categoryRisks: [CategoryRisk]

    enum RiskLevel: String, Codable, Sendable {
        case onTrack, watch, likelyOverspend

        var displayName: String {
            switch self {
            case .onTrack: "On track"
            case .watch: "Watch"
            case .likelyOverspend: "Likely overspend"
            }
        }
    }

    struct CategoryRisk: Codable, Sendable, Equatable, Identifiable {
        var category: SpendingCategory
        var budgeted: Decimal
        var spent: Decimal
        var projected: Decimal
        var risk: RiskLevel
        var id: String { category.rawValue }
    }
}

/// The hero number, with full provenance for the explanation drawer.
struct SafeToSpendDecision: Codable, Sendable, Equatable {
    var generatedAt: Date
    var todayAllowance: Decimal
    var weekAllowance: Decimal
    var monthRemainingAllowance: Decimal
    var confidence: Double // 0...1

    // Deterministic layer inputs (the explanation drawer renders these).
    var remainingDiscretionaryBudget: Decimal
    var upcomingRecurringDiscretionary: Decimal
    var forecastedRequiredEssentialSpend: Decimal
    var remainingDaysInPeriod: Int

    // AI adjustment layer.
    /// Multiplier applied to the deterministic daily allowance (e.g. 0.85 when
    /// discretionary acceleration was detected, 1.1 when well under pace).
    var behavioralAdjustment: Double
    /// Evidence strings for each adjustment, e.g.
    /// "Dining pace +27% vs. 3-month average → allowance reduced 10%".
    var adjustmentReasons: [String]
    var excludedCategories: [SpendingCategory]
}

enum InsightSeverity: String, Codable, Sendable {
    case positive, neutral, warning, critical
}

/// A data-backed observation. Insights observe; recommendations prescribe.
struct SpendingInsight: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var generatedAt: Date
    var title: String
    var detail: String
    var severity: InsightSeverity
    var category: SpendingCategory?
    /// Structured evidence behind the claim, e.g. "3-mo dining avg $412; this month pace $523".
    var evidence: [String]
    var confidence: Double
}

/// A concrete, confidence-scored action the user can take.
struct Recommendation: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var generatedAt: Date
    var title: String       // "Pause discretionary shopping for 4 days"
    var detail: String      // why, and what it achieves
    var severity: InsightSeverity
    var evidence: [String]
    var confidence: Double
    var relatedCategory: SpendingCategory?
}

/// Everything widgets need, precomputed and written to the App Group store
/// after each sync/AI recomputation so the extension never recomputes.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var generatedAt: Date
    var currencyCode: String

    var safeToSpendToday: Decimal
    var safeToSpendWeek: Decimal
    var safeToSpendConfidence: Double

    var budgetTotal: Decimal
    var budgetSpent: Decimal
    var budgetRemaining: Decimal
    /// Actual spend pace vs. ideal pace − 1 (e.g. 0.08 = 8% over pace).
    var spendPaceDelta: Double

    var netWorth: Decimal
    var netWorthChange30Days: Decimal

    var upcomingBills: [Bill]
    var topAlert: Alert?

    struct Bill: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var merchant: String
        var amount: Decimal
        var dueDate: Date
    }

    struct Alert: Codable, Sendable, Equatable {
        var title: String
        var detail: String
        var severity: InsightSeverity
    }
}
