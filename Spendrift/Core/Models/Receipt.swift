import Foundation
import SwiftData

enum ReceiptMatchStatus: String, Codable, Sendable {
    case unmatched
    case matched
    case manuallyMatched
    case noMatchExpected // e.g. cash purchase

    var displayName: String {
        switch self {
        case .unmatched: "Unmatched"
        case .matched: "Matched"
        case .manuallyMatched: "Matched (manual)"
        case .noMatchExpected: "Cash / no match"
        }
    }
}

struct ReceiptLineItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var quantity: Int
    var price: Decimal
}

@Model
final class Receipt {
    @Attribute(.unique) var id: UUID
    /// Filename within the app's receipt image directory (and backend object key once uploaded).
    var imageReference: String
    var capturedAt: Date
    var merchant: String?
    var purchaseDate: Date?
    var subtotal: Decimal?
    var tax: Decimal?
    var tip: Decimal?
    var total: Decimal?
    var lineItemsData: Data?
    var ocrText: String
    /// 0...1 — quality of the OCR pass itself.
    var ocrConfidence: Double
    /// 0...1 — confidence in the structured extraction (merchant/date/amounts).
    var extractionConfidence: Double
    var inferredCategoryRaw: String?
    var matchStatusRaw: String
    var matchedTransactionID: UUID?
    /// 0...1 — confidence of the receipt-to-transaction match.
    var matchConfidence: Double?

    var lineItems: [ReceiptLineItem] {
        get {
            guard let lineItemsData else { return [] }
            return (try? JSONDecoder().decode([ReceiptLineItem].self, from: lineItemsData)) ?? []
        }
        set { lineItemsData = try? JSONEncoder().encode(newValue) }
    }

    var matchStatus: ReceiptMatchStatus {
        get { ReceiptMatchStatus(rawValue: matchStatusRaw) ?? .unmatched }
        set { matchStatusRaw = newValue.rawValue }
    }

    var inferredCategory: SpendingCategory? {
        get { inferredCategoryRaw.flatMap(SpendingCategory.init(rawValue:)) }
        set { inferredCategoryRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        imageReference: String,
        capturedAt: Date = .now,
        merchant: String? = nil,
        purchaseDate: Date? = nil,
        subtotal: Decimal? = nil,
        tax: Decimal? = nil,
        tip: Decimal? = nil,
        total: Decimal? = nil,
        lineItems: [ReceiptLineItem] = [],
        ocrText: String = "",
        ocrConfidence: Double = 0,
        extractionConfidence: Double = 0,
        inferredCategory: SpendingCategory? = nil,
        matchStatus: ReceiptMatchStatus = .unmatched,
        matchedTransactionID: UUID? = nil,
        matchConfidence: Double? = nil
    ) {
        self.id = id
        self.imageReference = imageReference
        self.capturedAt = capturedAt
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.total = total
        self.lineItemsData = try? JSONEncoder().encode(lineItems)
        self.ocrText = ocrText
        self.ocrConfidence = ocrConfidence
        self.extractionConfidence = extractionConfidence
        self.inferredCategoryRaw = inferredCategory?.rawValue
        self.matchStatusRaw = matchStatus.rawValue
        self.matchedTransactionID = matchedTransactionID
        self.matchConfidence = matchConfidence
    }
}

/// Structured result of the receipt AI pipeline (OCR → parse → extract).
/// Plain value type so it can cross the AI service boundary and be validated
/// before anything is persisted onto the `Receipt` model.
struct ReceiptExtraction: Codable, Sendable {
    var merchant: String?
    var purchaseDate: Date?
    var subtotal: Decimal?
    var tax: Decimal?
    var tip: Decimal?
    var total: Decimal?
    var lineItems: [ReceiptLineItem]
    var inferredCategory: SpendingCategory?
    var ocrConfidence: Double
    var extractionConfidence: Double

    func apply(to receipt: Receipt) {
        receipt.merchant = merchant
        receipt.purchaseDate = purchaseDate
        receipt.subtotal = subtotal
        receipt.tax = tax
        receipt.tip = tip
        receipt.total = total
        receipt.lineItems = lineItems
        receipt.inferredCategory = inferredCategory
        receipt.ocrConfidence = ocrConfidence
        receipt.extractionConfidence = extractionConfidence
    }
}

/// Result of matching a receipt against candidate transactions.
struct ReceiptTransactionMatch: Codable, Sendable {
    var receiptID: UUID
    var transactionID: UUID
    var confidence: Double
    /// Human-readable evidence, e.g. "amount within $0.01, same day, merchant similarity 0.92".
    var rationale: String
}
