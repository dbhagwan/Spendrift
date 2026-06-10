import Foundation
import SwiftData

enum TransactionStatus: String, Codable, Sendable {
    case pending
    case posted
}

/// Who decided the current category — drives the confidence indicator and
/// the correction feedback loop (user edits always win and are learned from).
enum CategorySource: String, Codable, Sendable {
    case provider
    case rules
    case ai
    case user
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var providerTransactionID: String
    var accountID: UUID
    /// Positive = money out, negative = money in (Plaid convention).
    var amount: Decimal
    var date: Date
    var merchantName: String
    var rawDescription: String
    var normalizedDescription: String
    var statusRaw: String
    var categoryRaw: String
    var subcategory: String?
    var categorySourceRaw: String
    /// 0...1 confidence in the assigned category. 1.0 for user-set.
    var categoryConfidence: Double
    var isTransfer: Bool
    var isRecurring: Bool
    var isReimbursement: Bool
    var isEssential: Bool
    var isAnomaly: Bool
    var isHidden: Bool
    var receiptID: UUID?
    var locationCity: String?
    var locationRegion: String?
    /// Set when a pending transaction is replaced by its posted version.
    var supersededByProviderID: String?

    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .posted }
        set { statusRaw = newValue.rawValue }
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .miscellaneous }
        set { categoryRaw = newValue.rawValue }
    }

    var categorySource: CategorySource {
        get { CategorySource(rawValue: categorySourceRaw) ?? .ai }
        set { categorySourceRaw = newValue.rawValue }
    }

    /// True if this transaction counts toward spend totals.
    var countsAsSpend: Bool {
        amount > 0
            && !isTransfer
            && !isReimbursement
            && !isHidden
            && supersededByProviderID == nil
            && !category.isExcludedFromSpend
    }

    var countsAsDiscretionarySpend: Bool {
        countsAsSpend && !isEssential
    }

    init(
        id: UUID = UUID(),
        providerTransactionID: String,
        accountID: UUID,
        amount: Decimal,
        date: Date,
        merchantName: String,
        rawDescription: String,
        normalizedDescription: String? = nil,
        status: TransactionStatus = .posted,
        category: SpendingCategory = .miscellaneous,
        subcategory: String? = nil,
        categorySource: CategorySource = .ai,
        categoryConfidence: Double = 0.5,
        isTransfer: Bool = false,
        isRecurring: Bool = false,
        isReimbursement: Bool = false,
        isEssential: Bool = false,
        isAnomaly: Bool = false,
        isHidden: Bool = false,
        receiptID: UUID? = nil,
        locationCity: String? = nil,
        locationRegion: String? = nil
    ) {
        self.id = id
        self.providerTransactionID = providerTransactionID
        self.accountID = accountID
        self.amount = amount
        self.date = date
        self.merchantName = merchantName
        self.rawDescription = rawDescription
        self.normalizedDescription = normalizedDescription ?? merchantName
        self.statusRaw = status.rawValue
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.categorySourceRaw = categorySource.rawValue
        self.categoryConfidence = categoryConfidence
        self.isTransfer = isTransfer
        self.isRecurring = isRecurring
        self.isReimbursement = isReimbursement
        self.isEssential = isEssential
        self.isAnomaly = isAnomaly
        self.isHidden = isHidden
        self.receiptID = receiptID
        self.locationCity = locationCity
        self.locationRegion = locationRegion
        self.supersededByProviderID = nil
    }
}
