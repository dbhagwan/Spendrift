import Foundation
import SwiftData
import WidgetKit

/// Orchestrates the full AI pipeline after every sync or receipt capture:
/// normalization → categorization → recurring/transfer detection → receipt
/// matching → profile → forecast → risk → safe-to-spend → narratives →
/// widget snapshot. All derived state the UI renders comes from here.
@MainActor
@Observable
final class AIPipeline {
    private(set) var profile: SpendingProfile?
    private(set) var forecast: SpendForecast?
    private(set) var risk: BudgetRiskAssessment?
    private(set) var safeToSpend: SafeToSpendDecision?
    private(set) var insights: [SpendingInsight] = []
    private(set) var recommendations: [Recommendation] = []
    private(set) var lastRunAt: Date?
    private(set) var isRunning = false

    let categorization: CategorizationEngine
    private let ai: AIInferenceService

    init(ai: AIInferenceService) {
        self.ai = ai
        self.categorization = CategorizationEngine(ai: ai)
    }

    /// Full recomputation. Call after sync completes, a receipt is processed,
    /// the budget changes, or the user corrects a category.
    func recompute(in context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let receipts = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        let budget = (try? context.fetch(FetchDescriptor<Budget>()))?.first
        let userProfile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first

        // 1. Dedupe pending/posted pairs and flag internal transfers.
        RecurringDetector.deduplicatePendingPosted(in: transactions)
        let transferIDs = RecurringDetector.detectTransfers(in: transactions)
        for transaction in transactions where transferIDs.contains(transaction.id) {
            if transaction.categorySource != .user {
                transaction.isTransfer = true
                transaction.category = .transfers
            }
        }

        // 2. Recurring detection → flag transactions in stable series.
        let series = RecurringDetector.detectSeries(in: transactions)
        let recurringMerchants = Set(series.map { $0.merchant.lowercased() })
        for transaction in transactions {
            transaction.isRecurring = recurringMerchants.contains(transaction.normalizedDescription.lowercased())
        }

        // 3. Match unmatched receipts to transactions.
        for receipt in receipts where receipt.matchStatus == .unmatched {
            if let match = ReceiptMatcher.bestMatch(for: receipt, in: transactions), match.confidence >= 0.65 {
                receipt.matchStatus = .matched
                receipt.matchedTransactionID = match.transactionID
                receipt.matchConfidence = match.confidence
                if let transaction = transactions.first(where: { $0.id == match.transactionID }) {
                    transaction.receiptID = receipt.id
                    // Receipt category beats a low-confidence transaction category.
                    if let inferred = receipt.inferredCategory,
                       transaction.categorySource != .user,
                       transaction.categoryConfidence < 0.8
                    {
                        transaction.category = inferred
                        transaction.categoryConfidence = max(transaction.categoryConfidence, receipt.extractionConfidence)
                    }
                }
            }
        }

        // 4–8. Profile → forecast → risk → safe-to-spend.
        let profile = SpendingProfileEngine.build(transactions: transactions, recurringSeries: series)
        self.profile = profile

        let forecast = ForecastEngine.forecast(
            transactions: transactions,
            budget: budget,
            recurringSeries: series,
            profile: profile
        )
        self.forecast = forecast

        if let budget {
            let risk = ForecastEngine.assessRisk(transactions: transactions, budget: budget, forecast: forecast)
            self.risk = risk

            let excluded = (userProfile?.excludedSafeToSpendCategories ?? [])
                .compactMap(SpendingCategory.init(rawValue:))
            safeToSpend = SafeToSpendEngine.decide(
                budget: budget,
                forecast: forecast,
                profile: profile,
                transactions: transactions,
                excludedCategories: excluded
            )

            // 9. Narrative layer (structured in, structured out).
            let narratives = await ai.generateNarratives(profile: profile, forecast: forecast, risk: risk)
            insights = narratives.insights
            recommendations = narratives.recommendations
        }

        // 10. Net worth snapshot + widget snapshot.
        recordNetWorthSnapshot(accounts: accounts, in: context)
        writeWidgetSnapshot(accounts: accounts, budget: budget, forecast: forecast, in: context, currency: userProfile?.currencyCode ?? "USD")

        try? context.save()
        lastRunAt = .now
    }

    /// Apply a user category correction and feed the learning loop.
    func applyCorrection(_ transaction: Transaction, to category: SpendingCategory, in context: ModelContext) async {
        transaction.category = category
        transaction.categorySource = .user
        transaction.categoryConfidence = 1.0
        transaction.isEssential = category.isTypicallyFixed || category == .groceries
        categorization.learn(merchant: transaction.normalizedDescription, category: category)
        await recompute(in: context)
    }

    private func recordNetWorthSnapshot(accounts: [Account], in context: ModelContext) {
        let assets = accounts.filter { !$0.kind.isLiability }.reduce(Decimal(0)) { $0 + max(0, $1.netWorthContribution) }
        let liabilities = accounts.filter { $0.kind.isLiability }.reduce(Decimal(0)) { $0 - min(0, $1.netWorthContribution) }

        let today = Date.now.startOfDay
        let existing = (try? context.fetch(FetchDescriptor<NetWorthSnapshot>()))?
            .first { $0.date.startOfDay == today }
        if let existing {
            existing.totalAssets = assets
            existing.totalLiabilities = liabilities
        } else {
            context.insert(NetWorthSnapshot(date: today, totalAssets: assets, totalLiabilities: liabilities))
        }
    }

    private func writeWidgetSnapshot(
        accounts: [Account],
        budget: Budget?,
        forecast: SpendForecast,
        in context: ModelContext,
        currency: String
    ) {
        let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
        let snapshots = (try? context.fetch(FetchDescriptor<NetWorthSnapshot>())) ?? []
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let old = snapshots
            .filter { $0.date <= thirtyDaysAgo }
            .max { $0.date < $1.date }?.netWorth ?? netWorth

        let budgetTotal = budget?.monthlyTotal ?? 0
        let elapsed = forecast.periodStart.daysUntil(.now)
        let total = max(1, forecast.periodStart.daysUntil(forecast.periodEnd))
        let idealSpend = budgetTotal.doubleValue * Double(elapsed) / Double(total)
        let paceDelta = idealSpend > 0 ? forecast.spentToDate.doubleValue / idealSpend - 1 : 0

        let alert: WidgetSnapshot.Alert? = recommendations
            .first { $0.severity == .warning || $0.severity == .critical }
            .map { .init(title: $0.title, detail: $0.detail, severity: $0.severity) }

        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            currencyCode: currency,
            safeToSpendToday: safeToSpend?.todayAllowance ?? 0,
            safeToSpendWeek: safeToSpend?.weekAllowance ?? 0,
            safeToSpendConfidence: safeToSpend?.confidence ?? 0,
            budgetTotal: budgetTotal,
            budgetSpent: forecast.spentToDate,
            budgetRemaining: max(0, budgetTotal - forecast.spentToDate),
            spendPaceDelta: paceDelta,
            netWorth: netWorth,
            netWorthChange30Days: netWorth - old,
            upcomingBills: forecast.upcomingRecurringCharges.prefix(4).map {
                .init(merchant: $0.merchant, amount: $0.amount, dueDate: $0.expectedDate)
            },
            topAlert: alert
        )
        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
