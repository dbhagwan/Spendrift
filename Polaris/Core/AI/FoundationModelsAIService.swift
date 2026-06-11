import Foundation
import FoundationModels

/// On-device implementation of `AIInferenceService` using Apple's Foundation
/// Models framework (the Apple Intelligence on-device LLM, iOS 26+).
///
/// All three model-backed jobs — transaction classification, receipt
/// extraction, and narrative generation — run entirely on device: private,
/// free, and offline-capable. Guided generation (`@Generable`) enforces the
/// app's structured-AI-only rule at the framework level.
///
/// When the model is unavailable (device not eligible, Apple Intelligence
/// disabled, model assets still downloading, or CI simulators), every call
/// degrades gracefully to `MockAIService`'s deterministic heuristics.
struct FoundationModelsAIService: AIInferenceService {
    private let fallback = MockAIService()

    private var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let categoryIDs = [
        "income", "housing", "utilities", "groceries", "dining", "travel",
        "transportation", "shopping", "entertainment", "health", "insurance",
        "debtPayments", "transfers", "investments", "fees", "subscriptions",
        "taxes", "miscellaneous",
    ]

    // MARK: - Transaction classification

    @Generable
    struct TransactionClassification {
        @Guide(description: "The category id for this transaction", .anyOf([
            "income", "housing", "utilities", "groceries", "dining", "travel",
            "transportation", "shopping", "entertainment", "health", "insurance",
            "debtPayments", "transfers", "investments", "fees", "subscriptions",
            "taxes", "miscellaneous",
        ]))
        var category: String
        @Guide(description: "Optional finer-grained subcategory, e.g. 'Coffee' or 'Rideshare'")
        var subcategory: String?
        @Guide(description: "Confidence in the classification, between 0 and 1. Use below 0.5 when the descriptor is ambiguous.")
        var confidence: Double
    }

    func classifyTransaction(
        _ request: TransactionClassificationRequest
    ) async -> (category: SpendingCategory, subcategory: String?, confidence: Double) {
        guard isModelAvailable else {
            return await fallback.classifyTransaction(request)
        }
        do {
            let session = LanguageModelSession(instructions: """
                You classify US personal-finance bank transactions into a fixed \
                category taxonomy. Positive amounts are money out, negative are \
                money in. Recurring monthly charges are usually subscriptions, \
                utilities, insurance, housing, or debt payments. When a merchant \
                resembles one the user already filed, follow the user's filing. \
                Be conservative with confidence.
                """)
            let result = try await session.respond(
                to: Self.classificationPrompt(for: request),
                generating: TransactionClassification.self
            ).content
            return (
                SpendingCategory(rawValue: result.category) ?? .miscellaneous,
                result.subcategory,
                min(max(result.confidence, 0), 1)
            )
        } catch {
            return await fallback.classifyTransaction(request)
        }
    }

    /// Terse, line-per-signal prompt — the on-device model has a small
    /// context window, so examples are capped and every line earns its place.
    private static func classificationPrompt(for request: TransactionClassificationRequest) -> String {
        var lines = [
            "Merchant: \(request.merchant)",
            "Raw descriptor: \(request.rawDescription)",
            "Amount: \(request.amount) (\(request.amount < 0 ? "money in" : "money out"))",
            "Day: \(request.date.formatted(.dateTime.weekday(.wide)))",
        ]
        if request.isRecurring {
            lines.append("Pattern: part of a stable recurring series")
        }
        if let hint = request.providerCategoryHint {
            lines.append("Bank's coarse category hint: \(hint)")
        }
        if !request.userExamples.isEmpty {
            lines.append("How this user filed other merchants:")
            for example in request.userExamples.prefix(8) {
                lines.append("- \(example.merchant) → \(example.categoryID)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Receipt extraction

    @Generable
    struct ReceiptFields {
        @Guide(description: "Merchant or store name, if present")
        var merchant: String?
        @Guide(description: "Purchase date in yyyy-MM-dd format, if present")
        var purchaseDate: String?
        var subtotal: Double?
        var tax: Double?
        var tip: Double?
        var total: Double?
        @Guide(description: "Purchased line items; empty if unreadable")
        var lineItems: [ReceiptLineItemFields]
        @Guide(description: "Best-fit category id for this purchase", .anyOf([
            "groceries", "dining", "travel", "transportation", "shopping",
            "entertainment", "health", "subscriptions", "miscellaneous",
        ]))
        var category: String?
        @Guide(description: "Return policy window in days, only if explicitly printed on the receipt")
        var returnWindowDays: Int?
        @Guide(description: "Confidence in this extraction, between 0 and 1")
        var confidence: Double
    }

    @Generable
    struct ReceiptLineItemFields {
        var name: String
        var quantity: Int
        var price: Double
        @Guide(description: "Best-fit category id for this specific line item", .anyOf([
            "groceries", "dining", "shopping", "health", "entertainment",
            "transportation", "miscellaneous",
        ]))
        var category: String?
    }

    func extractReceipt(ocrText: String) async -> ReceiptExtraction? {
        guard isModelAvailable else {
            return await fallback.extractReceipt(ocrText: ocrText)
        }
        do {
            let session = LanguageModelSession(instructions: """
                You extract structured data from noisy receipt OCR text. Only \
                report values actually present in the text. Never invent line \
                items or amounts.
                """)
            let result = try await session.respond(
                to: "Extract the receipt data:\n\n\(ocrText)",
                generating: ReceiptFields.self
            ).content

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd"

            return ReceiptExtraction(
                merchant: result.merchant,
                purchaseDate: result.purchaseDate.flatMap(dateFormatter.date(from:)),
                subtotal: result.subtotal.map { Decimal($0) },
                tax: result.tax.map { Decimal($0) },
                tip: result.tip.map { Decimal($0) },
                total: result.total.map { Decimal($0) },
                lineItems: result.lineItems.map {
                    ReceiptLineItem(
                        name: $0.name,
                        quantity: max(1, $0.quantity),
                        price: Decimal($0.price),
                        category: $0.category.flatMap(SpendingCategory.init(rawValue:))
                    )
                },
                inferredCategory: result.category.flatMap(SpendingCategory.init(rawValue:)),
                ocrConfidence: 0,
                extractionConfidence: min(max(result.confidence, 0), 1),
                returnWindowDays: result.returnWindowDays
            )
        } catch {
            return await fallback.extractReceipt(ocrText: ocrText)
        }
    }

    // MARK: - Natural-language transaction search

    @Generable
    struct TransactionQueryFields {
        @Guide(description: "Category id filter, only if the search clearly names one", .anyOf([
            "income", "housing", "utilities", "groceries", "dining", "travel",
            "transportation", "shopping", "entertainment", "health", "insurance",
            "debtPayments", "transfers", "investments", "fees", "subscriptions",
            "taxes", "miscellaneous",
        ]))
        var category: String?
        @Guide(description: "Merchant name fragment, only if the search names a specific merchant")
        var merchant: String?
        @Guide(description: "Minimum amount in dollars, if stated (e.g. 'over $20' = 20)")
        var minAmount: Double?
        @Guide(description: "Maximum amount in dollars, if stated")
        var maxAmount: Double?
        @Guide(description: "Days of history, if a period is stated ('last month' = 30, 'this week' = 7)")
        var daysBack: Int?
        @Guide(description: "True only if the search asks for recurring or subscription charges")
        var recurringOnly: Bool
    }

    func parseTransactionQuery(_ text: String) async -> TransactionSearchQuery {
        guard isModelAvailable else {
            return await fallback.parseTransactionQuery(text)
        }
        do {
            let session = LanguageModelSession(instructions: """
                You convert a natural-language personal-finance transaction \
                search into a structured filter. Leave every field empty that \
                the search does not clearly state. 'Coffee' implies the dining \
                category.
                """)
            let result = try await session.respond(
                to: "Search: \(text)",
                generating: TransactionQueryFields.self
            ).content
            return TransactionSearchQuery(
                category: result.category.flatMap(SpendingCategory.init(rawValue:)),
                merchantContains: result.merchant?.isEmpty == false ? result.merchant : nil,
                minAmount: result.minAmount.map { Decimal($0) },
                maxAmount: result.maxAmount.map { Decimal($0) },
                daysBack: result.daysBack,
                recurringOnly: result.recurringOnly
            )
        } catch {
            return await fallback.parseTransactionQuery(text)
        }
    }

    // MARK: - Narrative generation

    @Generable
    struct NarrativeItem {
        @Guide(description: "Short, specific headline citing a number, e.g. 'Dining is 27% above your average'")
        var title: String
        @Guide(description: "One or two sentences of detail grounded in the provided data")
        var detail: String
        @Guide(description: "Severity of this item", .anyOf(["positive", "neutral", "warning", "critical"]))
        var severity: String
        @Guide(description: "Specific numbers from the input that back this claim")
        var evidence: [String]
        @Guide(description: "Confidence between 0 and 1")
        var confidence: Double
    }

    @Generable
    struct Narratives {
        @Guide(description: "At most 4 data-backed observations")
        var insights: [NarrativeItem]
        @Guide(description: "At most 3 concrete actions the user can take")
        var recommendations: [NarrativeItem]
    }

    func generateNarratives(
        profile: SpendingProfile,
        forecast: SpendForecast,
        risk: BudgetRiskAssessment
    ) async -> (insights: [SpendingInsight], recommendations: [Recommendation]) {
        guard isModelAvailable else {
            return await fallback.generateNarratives(profile: profile, forecast: forecast, risk: risk)
        }
        do {
            let session = LanguageModelSession(instructions: """
                You are the narration layer of a personal-finance copilot. You \
                receive pre-computed financial analysis and write concise \
                insights (observations) and recommendations (concrete actions). \
                Every claim must cite a number from the input in its evidence. \
                Never invent data, never give generic advice, never moralize.
                """)
            let result = try await session.respond(
                to: Self.compactSummary(profile: profile, forecast: forecast, risk: risk),
                generating: Narratives.self
            ).content

            let now = Date.now
            let insights = result.insights.prefix(5).map {
                SpendingInsight(
                    generatedAt: now,
                    title: $0.title,
                    detail: $0.detail,
                    severity: InsightSeverity(rawValue: $0.severity) ?? .neutral,
                    category: nil,
                    evidence: $0.evidence,
                    confidence: min(max($0.confidence, 0), 1)
                )
            }
            let recommendations = result.recommendations.prefix(3).map {
                Recommendation(
                    generatedAt: now,
                    title: $0.title,
                    detail: $0.detail,
                    severity: InsightSeverity(rawValue: $0.severity) ?? .neutral,
                    evidence: $0.evidence,
                    confidence: min(max($0.confidence, 0), 1),
                    relatedCategory: nil
                )
            }
            return (Array(insights), Array(recommendations))
        } catch {
            return await fallback.generateNarratives(profile: profile, forecast: forecast, risk: risk)
        }
    }

    /// Compact text summary of the structured inputs — the on-device model has
    /// a small context window, so this stays terse and numeric.
    private static func compactSummary(
        profile: SpendingProfile,
        forecast: SpendForecast,
        risk: BudgetRiskAssessment
    ) -> String {
        let momentum = profile.categoryMomentum.prefix(4)
            .map { "\($0.category.displayName) \(Int(($0.ratioToTrailingAverage - 1) * 100))% vs 3-mo avg" }
            .joined(separator: "; ")
        let categoryRisks = risk.categoryRisks.prefix(4)
            .map { "\($0.category.displayName): spent \($0.spent) of \($0.budgeted), projected \($0.projected) (\($0.risk.displayName))" }
            .joined(separator: "; ")
        return """
            Months of history: \(profile.monthsOfHistory)
            Average monthly spend: \(profile.averageMonthlySpend)
            Spend volatility: \(Int(profile.spendVolatility * 100))%
            Savings rate: \(Int(profile.savingsRate * 100))%
            Subscriptions: \(profile.subscriptionMonthlyLoad)/mo, change vs 3 months ago: \(profile.subscriptionMonthlyLoadChange)
            Category momentum: \(momentum)
            Spent so far this period: \(forecast.spentToDate); projected total: \(forecast.projectedTotalSpend)
            Overall budget risk: \(risk.overallRisk.displayName); projected utilization \(Int(risk.projectedBudgetUtilization * 100))%
            Category budgets: \(categoryRisks)
            Overspend triggers: \(profile.overspendTriggers.joined(separator: "; "))
            Unusual charges: \(profile.recentAnomalies.isEmpty ? "none" : profile.recentAnomalies.prefix(3).joined(separator: "; "))
            """
    }
}
