import Foundation

/// Hybrid categorization pipeline:
/// 1. user correction memory (always wins)
/// 2. deterministic rules over normalized merchant text
/// 3. provider category hint, if present
/// 4. AI classifier fallback (via `AIInferenceService`)
/// Confidence reflects which stage decided.
struct CategorizationResult: Sendable {
    var category: SpendingCategory
    var subcategory: String?
    var source: CategorySource
    var confidence: Double
    var isEssential: Bool
}

final class CategorizationEngine: @unchecked Sendable {
    private let ai: AIInferenceService
    /// Normalized merchant → category learned from user corrections.
    /// Stored in iCloud key-value storage so corrections learned on one
    /// device improve categorization on all of them (UserDefaults kept as a
    /// local mirror for offline first-launch).
    private var correctionMemory: [String: SpendingCategory]
    private let memoryKey = "categorization.corrections"

    init(ai: AIInferenceService) {
        self.ai = ai
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        let raw = (cloud.dictionary(forKey: memoryKey) as? [String: String])
            ?? (UserDefaults.standard.dictionary(forKey: memoryKey) as? [String: String])
            ?? [:]
        correctionMemory = raw.compactMapValues(SpendingCategory.init(rawValue:))
    }

    func categorize(
        merchant: String,
        rawDescription: String,
        amount: Decimal,
        date: Date = .now,
        isRecurring: Bool = false,
        providerCategoryHint: String?
    ) async -> CategorizationResult {
        let normalized = Self.normalizeMerchant(rawDescription.isEmpty ? merchant : rawDescription)

        if let learned = correctionMemory[normalized.lowercased()] {
            return result(learned, source: .user, confidence: 0.98)
        }
        if let ruled = Self.ruleMatch(normalized: normalized, amount: amount) {
            return ruled
        }

        // Specific provider hints are trustworthy. Generic buckets are not —
        // Plaid files a huge long tail under GENERAL_MERCHANDISE — so those
        // go to the model as one signal among several instead of an answer.
        let mappedHint = providerCategoryHint.flatMap(Self.mapProviderCategory)
        if let mappedHint, mappedHint != .shopping, mappedHint != .miscellaneous {
            return result(mappedHint, source: .provider, confidence: 0.75)
        }

        let aiResult = await ai.classifyTransaction(TransactionClassificationRequest(
            merchant: normalized,
            rawDescription: rawDescription,
            amount: amount,
            date: date,
            isRecurring: isRecurring,
            providerCategoryHint: providerCategoryHint,
            userExamples: relevantExamples(for: normalized)
        ))
        // A weak hint still beats a wild guess.
        if let mappedHint, aiResult.confidence < 0.5 {
            return result(mappedHint, source: .provider, confidence: 0.6)
        }
        return CategorizationResult(
            category: aiResult.category,
            subcategory: aiResult.subcategory,
            source: .ai,
            confidence: aiResult.confidence,
            isEssential: aiResult.category.isTypicallyFixed || aiResult.category == .groceries
        )
    }

    /// Up to 8 correction-memory entries to use as few-shot examples, ones
    /// sharing a word with this merchant first — so a single correction
    /// ("Blue Bottle" → dining) also steers similar merchants.
    private func relevantExamples(for merchant: String) -> [TransactionClassificationRequest.UserExample] {
        let tokens = Set(merchant.lowercased().split(separator: " "))
        return correctionMemory
            .map { entry in
                (overlap: Set(entry.key.split(separator: " ")).intersection(tokens).count,
                 example: TransactionClassificationRequest.UserExample(
                     merchant: entry.key.capitalized,
                     categoryID: entry.value.rawValue
                 ))
            }
            .sorted { $0.overlap > $1.overlap }
            .prefix(8)
            .map(\.example)
    }

    /// Record a user correction so the same merchant categorizes correctly
    /// next time — on every device.
    func learn(merchant: String, category: SpendingCategory) {
        let key = Self.normalizeMerchant(merchant).lowercased()
        correctionMemory[key] = category
        let raw = correctionMemory.mapValues(\.rawValue)
        NSUbiquitousKeyValueStore.default.set(raw, forKey: memoryKey)
        UserDefaults.standard.set(raw, forKey: memoryKey)
    }

    // MARK: - Merchant normalization

    /// Strips processor noise from raw bank descriptors:
    /// "SQ *BLUE BOTTLE COF 0412 OAKLAND CA" → "Blue Bottle Cof".
    static func normalizeMerchant(_ raw: String) -> String {
        var text = raw.uppercased()
        for prefix in ["SQ *", "TST* ", "TST*", "SP * ", "SP *", "PY *", "PAYPAL *", "APLPAY ", "CKE*"] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        // Drop trailing store numbers, dates, and state codes.
        let noise = try? NSRegularExpression(
            pattern: #"\s+(#?\d{2,}|\d{1,2}/\d{1,2}|[A-Z]{2})\s*$"#
        )
        var previous = ""
        while previous != text {
            previous = text
            if let noise {
                let range = NSRange(text.startIndex..., in: text)
                text = noise.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }
        return text.trimmingCharacters(in: .whitespaces).capitalized
    }

    // MARK: - Rules

    private static let rules: [(keywords: [String], category: SpendingCategory, subcategory: String?, essential: Bool)] = [
        (["payroll", "direct dep", "dd ", "gusto", "adp"], .income, "Paycheck", false),
        (["rent", "apartment", "property mgmt"], .housing, "Rent", true),
        (["mortgage"], .housing, "Mortgage", true),
        (["pg&e", "pge", "electric", "water dist", "comcast", "xfinity", "verizon", "t-mobile", "at&t"], .utilities, nil, true),
        (["whole foods", "trader joe", "safeway", "kroger", "costco", "grocery", "aldi", "h mart"], .groceries, nil, true),
        (["doordash", "uber eats", "grubhub"], .dining, "Delivery", false),
        (["starbucks", "blue bottle", "coffee", "cafe"], .dining, "Coffee", false),
        (["restaurant", "pizza", "sushi", "taqueria", "chipotle", "mcdonald"], .dining, "Restaurants", false),
        (["united air", "delta air", "alaska air", "airbnb", "hotel", "marriott", "hilton", "expedia"], .travel, nil, false),
        (["uber", "lyft"], .transportation, "Rideshare", false),
        (["shell", "chevron", "exxon", "gas station", "clipper", "parking"], .transportation, nil, true),
        (["amazon", "target", "best buy", "nordstrom", "zara", "uniqlo", "etsy"], .shopping, nil, false),
        (["netflix", "spotify", "hulu", "max ", "disney+", "youtube prem", "icloud", "apple.com/bill", "openai", "anthropic"], .subscriptions, nil, false),
        (["amc", "cinema", "ticketmaster", "steam", "playstation", "nintendo"], .entertainment, nil, false),
        (["cvs", "walgreens", "pharmacy", "dental", "clinic", "kaiser"], .health, nil, true),
        (["geico", "state farm", "progressive", "insurance"], .insurance, nil, true),
        (["loan pmt", "student loan", "navient", "nelnet", "card payment", "autopay payment"], .debtPayments, nil, true),
        (["irs", "franchise tax", "tax pmt"], .taxes, nil, true),
        (["robinhood", "vanguard", "fidelity", "schwab", "wealthfront", "betterment"], .investments, nil, false),
        (["overdraft", "atm fee", "service fee", "interest charge", "late fee"], .fees, nil, false),
        (["zelle", "venmo", "cash app", "transfer", "wire "], .transfers, nil, false),
    ]

    private static func ruleMatch(normalized: String, amount: Decimal) -> CategorizationResult? {
        let haystack = normalized.lowercased()
        for rule in rules where rule.keywords.contains(where: haystack.contains) {
            // Income rules only apply to inflows.
            if rule.category == .income && amount > 0 { continue }
            return CategorizationResult(
                category: rule.category,
                subcategory: rule.subcategory,
                source: .rules,
                confidence: 0.9,
                isEssential: rule.essential
            )
        }
        return nil
    }

    private static func mapProviderCategory(_ hint: String) -> SpendingCategory? {
        switch hint.uppercased() {
        case "FOOD_AND_DRINK", "RESTAURANTS": .dining
        case "GROCERIES": .groceries
        case "TRAVEL": .travel
        case "TRANSPORTATION": .transportation
        case "GENERAL_MERCHANDISE", "SHOPPING": .shopping
        case "ENTERTAINMENT": .entertainment
        case "MEDICAL", "HEALTHCARE": .health
        case "RENT_AND_UTILITIES": .housing
        case "LOAN_PAYMENTS": .debtPayments
        case "TRANSFER_IN", "TRANSFER_OUT": .transfers
        case "INCOME": .income
        case "BANK_FEES": .fees
        default: nil
        }
    }

    private func result(_ category: SpendingCategory, source: CategorySource, confidence: Double) -> CategorizationResult {
        CategorizationResult(
            category: category,
            subcategory: nil,
            source: source,
            confidence: confidence,
            isEssential: category.isTypicallyFixed || category == .groceries
        )
    }
}
