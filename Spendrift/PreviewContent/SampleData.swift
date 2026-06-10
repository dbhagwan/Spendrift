import Foundation
import SwiftData

/// Deterministic seeded data: ~6 months of realistic activity across four
/// accounts, a budget, receipts, and net worth history. Powers previews and
/// mock mode so every screen has meaningful content without a backend.
@MainActor
enum SampleData {
    static func seed(into context: ModelContext) {
        var generator = SeededGenerator(seed: 42)
        let calendar = Calendar.current
        let now = Date.now

        // MARK: Institutions & accounts

        let chase = LinkedInstitution(providerItemID: "item-chase", name: "Chase", lastSyncedAt: now)
        let amex = LinkedInstitution(providerItemID: "item-amex", name: "American Express", lastSyncedAt: now)
        let fidelity = LinkedInstitution(providerItemID: "item-fidelity", name: "Fidelity", lastSyncedAt: now)
        [chase, amex, fidelity].forEach(context.insert)

        let checking = Account(
            providerAccountID: "acc-checking", institutionName: "Chase", name: "Total Checking",
            kind: .checking, subtype: "checking", mask: "4421",
            currentBalance: 6_842.17, availableBalance: 6_742.17
        )
        let savings = Account(
            providerAccountID: "acc-savings", institutionName: "Chase", name: "Premier Savings",
            kind: .savings, subtype: "savings", mask: "8810",
            currentBalance: 24_500
        )
        let creditCard = Account(
            providerAccountID: "acc-amex", institutionName: "American Express", name: "Gold Card",
            kind: .creditCard, subtype: "credit card", mask: "1005",
            currentBalance: 1_624.55, creditLimit: 15_000
        )
        let brokerage = Account(
            providerAccountID: "acc-brokerage", institutionName: "Fidelity", name: "Individual Brokerage",
            kind: .investment, subtype: "brokerage", mask: "7733",
            currentBalance: 58_900
        )
        checking.institution = chase
        savings.institution = chase
        creditCard.institution = amex
        brokerage.institution = fidelity
        [checking, savings, creditCard, brokerage].forEach(context.insert)

        // MARK: Transactions — 6 months

        func add(
            _ daysAgo: Int, _ amount: Decimal, _ merchant: String, _ category: SpendingCategory,
            account: Account = creditCard, recurring: Bool = false, essential: Bool? = nil,
            pending: Bool = false, confidence: Double = 0.92
        ) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(Transaction(
                providerTransactionID: "txn-\(merchant.hashValue)-\(daysAgo)",
                accountID: account.id,
                amount: amount,
                date: date,
                merchantName: merchant,
                rawDescription: merchant.uppercased(),
                normalizedDescription: merchant,
                status: pending ? .pending : .posted,
                category: category,
                categorySource: .rules,
                categoryConfidence: confidence,
                isRecurring: recurring,
                isEssential: essential ?? (category.isTypicallyFixed || category == .groceries)
            ))
        }

        for monthsAgo in 0..<6 {
            let base = monthsAgo * 30

            // Income: biweekly paychecks.
            add(base + 3, -3_150, "Acme Corp Payroll", .income, account: checking, recurring: true)
            add(base + 17, -3_150, "Acme Corp Payroll", .income, account: checking, recurring: true)

            // Fixed obligations.
            add(base + 1, 1_850, "Parkline Apartments", .housing, account: checking, recurring: true)
            add(base + 4, 82.40 + Decimal(generator.next(in: -8...12)), "PG&E", .utilities, account: checking, recurring: true)
            add(base + 6, 89.99, "Xfinity", .utilities, account: checking, recurring: true)
            add(base + 9, 132.50, "Geico", .insurance, account: checking, recurring: true)
            add(base + 11, 15.49, "Netflix", .subscriptions, recurring: true)
            add(base + 12, 10.99, "Spotify", .subscriptions, recurring: true)
            add(base + 14, 9.99, "iCloud", .subscriptions, recurring: true)
            if monthsAgo < 2 { // subscription creep: new services recently
                add(base + 13, 20.00, "ChatGPT Plus", .subscriptions, recurring: true)
                add(base + 15, 16.99, "HBO Max", .subscriptions, recurring: true)
            }

            // Groceries: weekly.
            for week in 0..<4 {
                add(base + week * 7 + 2, 95 + Decimal(generator.next(in: -25...45)), "Trader Joe's", .groceries)
            }

            // Dining: accelerating in recent months (momentum signal).
            let diningCount = monthsAgo < 2 ? 14 : 9
            let diningSpots = ["Souvla", "Blue Bottle Coffee", "Doordash", "Tartine Bakery", "El Farolito", "Sweetgreen"]
            for i in 0..<diningCount {
                add(base + (i * 2) % 28, 14 + Decimal(generator.next(in: 0...48)), diningSpots[i % diningSpots.count], .dining)
            }

            // Shopping & entertainment.
            add(base + 8, 64 + Decimal(generator.next(in: -20...120)), "Amazon", .shopping)
            add(base + 19, 38 + Decimal(generator.next(in: -10...60)), "Target", .shopping)
            add(base + 22, 32, "AMC Theatres", .entertainment)

            // Transportation.
            for i in 0..<5 {
                add(base + i * 6 + 3, 11 + Decimal(generator.next(in: 0...22)), "Uber", .transportation)
            }
            add(base + 16, 52 + Decimal(generator.next(in: -6...10)), "Chevron", .transportation, account: checking)

            // Transfers (excluded from spend) + investment contribution.
            add(base + 5, 500, "Transfer to Savings", .transfers, account: checking, essential: false)
            add(base + 18, 400, "Fidelity Contribution", .investments, account: checking, recurring: true, essential: false)

            // Card payment pair (transfer detection exercise).
            add(base + 20, 1_400, "Amex Autopay Payment", .debtPayments, account: checking, essential: true)
        }

        // Recent pending + an anomaly.
        add(0, 18.40, "Blue Bottle Coffee", .dining, pending: true)
        add(1, 482.00, "Apple Store", .shopping, confidence: 0.55)

        // A low-confidence uncategorized-ish charge for the correction flow.
        add(2, 23.75, "Sq *corner Mart 0114", .miscellaneous, confidence: 0.35)

        // MARK: Receipts

        let matchedReceipt = Receipt(
            imageReference: "sample-receipt-1.jpg",
            capturedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
            merchant: "Trader Joe's",
            purchaseDate: calendar.date(byAdding: .day, value: -3, to: now),
            subtotal: 104.32, tax: 4.18, total: 108.50,
            lineItems: [
                ReceiptLineItem(name: "Organic Bananas", quantity: 1, price: 1.99),
                ReceiptLineItem(name: "Mandarin Orange Chicken", quantity: 2, price: 9.98),
                ReceiptLineItem(name: "Sparkling Water 12pk", quantity: 1, price: 4.49),
                ReceiptLineItem(name: "Unexpected Cheddar", quantity: 1, price: 4.29),
            ],
            ocrText: "TRADER JOE'S\n...",
            ocrConfidence: 0.94,
            extractionConfidence: 0.88,
            inferredCategory: .groceries,
            matchStatus: .matched,
            matchConfidence: 0.91
        )
        let unmatchedReceipt = Receipt(
            imageReference: "sample-receipt-2.jpg",
            capturedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
            merchant: "Souvla",
            purchaseDate: calendar.date(byAdding: .day, value: -1, to: now),
            subtotal: 42.00, tax: 3.78, tip: 12.60, total: 58.38,
            lineItems: [
                ReceiptLineItem(name: "Lamb Salad", quantity: 1, price: 18.00),
                ReceiptLineItem(name: "Chicken Sandwich", quantity: 1, price: 16.00),
                ReceiptLineItem(name: "Frozen Greek Yogurt", quantity: 2, price: 8.00),
            ],
            ocrText: "SOUVLA\n...",
            ocrConfidence: 0.91,
            extractionConfidence: 0.82,
            inferredCategory: .dining,
            matchStatus: .unmatched
        )
        context.insert(matchedReceipt)
        context.insert(unmatchedReceipt)

        // MARK: Budget

        let budget = Budget(monthlyTotal: 3_600)
        budget.categories = [
            BudgetCategory(category: .groceries, monthlyLimit: 480, isAIRecommended: true),
            BudgetCategory(category: .dining, monthlyLimit: 420, isAIRecommended: true),
            BudgetCategory(category: .shopping, monthlyLimit: 300, isAIRecommended: true),
            BudgetCategory(category: .transportation, monthlyLimit: 220, isAIRecommended: true),
            BudgetCategory(category: .entertainment, monthlyLimit: 90, isAIRecommended: true),
            BudgetCategory(category: .subscriptions, monthlyLimit: 80),
        ]
        context.insert(budget)

        // MARK: Net worth history (gentle upward trend with noise)

        var netWorth = 82_000.0
        for daysAgo in stride(from: 180, through: 0, by: -3) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)?.startOfDay ?? now
            netWorth += Double(generator.next(in: -300...420))
            let liabilities = 1_500 + Double(generator.next(in: -300...300))
            context.insert(NetWorthSnapshot(
                date: date,
                totalAssets: Decimal(netWorth + liabilities),
                totalLiabilities: Decimal(liabilities)
            ))
        }

        try? context.save()
    }
}

/// Deterministic PRNG so previews are stable run to run.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(state % span)
    }
}
