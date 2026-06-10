import Foundation

/// Deterministic receipt parser: OCR text → `ReceiptExtraction`.
/// The receipt pipeline runs this first; if `extractionConfidence` is low,
/// `ReceiptPipeline` escalates to the AI service for structured extraction.
enum ReceiptParser {
    static func parse(ocrText: String, ocrConfidence: Double) -> ReceiptExtraction {
        let lines = ocrText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let merchant = lines.first.map { String($0.prefix(40)) }
        let total = amount(labeled: ["total", "amount due", "balance due"], in: lines)
            ?? largestAmount(in: lines)
        let subtotal = amount(labeled: ["subtotal", "sub total", "sub-total"], in: lines)
        let tax = amount(labeled: ["tax", "sales tax", "vat"], in: lines)
        let tip = amount(labeled: ["tip", "gratuity"], in: lines)
        let date = firstDate(in: lines)
        let items = lineItems(in: lines)

        var confidence = 0.2
        if merchant != nil { confidence += 0.15 }
        if total != nil { confidence += 0.3 }
        if date != nil { confidence += 0.15 }
        if subtotal != nil || tax != nil { confidence += 0.1 }
        if !items.isEmpty { confidence += 0.1 }
        // Sanity check: components should roughly reconstruct the total.
        if let total, let subtotal {
            let reconstructed = subtotal + (tax ?? 0) + (tip ?? 0)
            if abs((reconstructed - total).doubleValue) > 0.02 { confidence -= 0.15 }
        }

        return ReceiptExtraction(
            merchant: merchant,
            purchaseDate: date,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            total: total,
            lineItems: items,
            inferredCategory: inferCategory(merchant: merchant, items: items),
            ocrConfidence: ocrConfidence,
            extractionConfidence: max(0, min(1, confidence))
        )
    }

    // MARK: - Helpers

    // Computed because NSRegularExpression is not Sendable (Swift 6 strict concurrency).
    private static var amountRegex: NSRegularExpression? {
        try? NSRegularExpression(pattern: #"\$?\s?(\d{1,5}\.\d{2})"#)
    }

    private static func amounts(in line: String) -> [Decimal] {
        guard let amountRegex else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return amountRegex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: line) else { return nil }
            return Decimal(string: String(line[r]))
        }
    }

    private static func amount(labeled labels: [String], in lines: [String]) -> Decimal? {
        for line in lines {
            let lower = line.lowercased()
            guard labels.contains(where: lower.contains) else { continue }
            // "Subtotal" lines would otherwise match a bare "total" search.
            if labels == ["total", "amount due", "balance due"] && lower.contains("subtotal") { continue }
            if let value = amounts(in: line).last { return value }
        }
        return nil
    }

    private static func largestAmount(in lines: [String]) -> Decimal? {
        lines.flatMap(amounts(in:)).max()
    }

    private static func firstDate(in lines: [String]) -> Date? {
        let formats = ["MM/dd/yyyy", "MM/dd/yy", "yyyy-MM-dd", "MMM d, yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateRegex = try? NSRegularExpression(
            pattern: #"(\d{1,2}/\d{1,2}/\d{2,4}|\d{4}-\d{2}-\d{2}|[A-Z][a-z]{2} \d{1,2}, \d{4})"#
        )
        for line in lines {
            guard let dateRegex,
                  let match = dateRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let r = Range(match.range(at: 1), in: line)
            else { continue }
            let candidate = String(line[r])
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: candidate) { return date }
            }
        }
        return nil
    }

    /// Lines shaped like "<name> ... <price>", excluding summary rows.
    private static func lineItems(in lines: [String]) -> [ReceiptLineItem] {
        let summaryWords = ["total", "tax", "tip", "gratuity", "change", "cash", "card", "visa", "balance", "auth"]
        var items: [ReceiptLineItem] = []
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            guard !summaryWords.contains(where: lower.contains),
                  let price = amounts(in: line).last
            else { continue }
            var name = line
            if let priceRange = name.range(of: String(describing: price), options: .backwards) {
                name.removeSubrange(priceRange)
            }
            name = name
                .replacingOccurrences(of: #"\$?\s?\d{1,5}\.\d{2}"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .$-"))
            guard name.count >= 2 else { continue }
            let quantityMatch = name.firstMatch(of: /^(\d{1,2})\s*[xX]?\s+/)
            let quantity = quantityMatch.flatMap { Int($0.1) } ?? 1
            if let quantityMatch { name.removeSubrange(quantityMatch.range) }
            items.append(ReceiptLineItem(name: name.capitalized, quantity: quantity, price: price))
        }
        return Array(items.prefix(30))
    }

    private static func inferCategory(merchant: String?, items: [ReceiptLineItem]) -> SpendingCategory? {
        let haystack = ((merchant ?? "") + " " + items.map(\.name).joined(separator: " ")).lowercased()
        if ["grocery", "market", "produce", "organic"].contains(where: haystack.contains) { return .groceries }
        if ["latte", "espresso", "burger", "pizza", "entree", "appetizer", "cafe", "grill"].contains(where: haystack.contains) { return .dining }
        if ["pharmacy", "rx "].contains(where: haystack.contains) { return .health }
        if ["fuel", "unleaded", "gallon"].contains(where: haystack.contains) { return .transportation }
        return nil
    }
}

/// Matches a parsed receipt against candidate transactions using amount
/// proximity, date proximity, and merchant text similarity.
enum ReceiptMatcher {
    static func bestMatch(for receipt: Receipt, in transactions: [Transaction]) -> ReceiptTransactionMatch? {
        guard let total = receipt.total else { return nil }
        let receiptDate = receipt.purchaseDate ?? receipt.capturedAt

        var best: (transaction: Transaction, score: Double, rationale: String)?
        for transaction in transactions where transaction.amount > 0 && transaction.receiptID == nil {
            let amountDelta = abs((transaction.amount - total).doubleValue)
            let dayDelta = abs(Double(receiptDate.daysUntil(transaction.date)))
            guard amountDelta <= max(0.02, total.doubleValue * 0.20), dayDelta <= 4 else { continue }

            // Card transactions often include tip added after the printed subtotal,
            // so exact-amount gets a big boost but near-amount still scores.
            let amountScore = amountDelta <= 0.01 ? 1.0 : max(0, 1 - amountDelta / max(1, total.doubleValue * 0.20))
            let dateScore = max(0, 1 - dayDelta / 4)
            let merchantScore = similarity(receipt.merchant ?? "", transaction.normalizedDescription)
            let score = amountScore * 0.55 + dateScore * 0.25 + merchantScore * 0.20

            if score > (best?.score ?? 0.55) {
                best = (
                    transaction,
                    score,
                    "amount Δ$\(String(format: "%.2f", amountDelta)), \(Int(dayDelta))d apart, merchant similarity \(String(format: "%.2f", merchantScore))"
                )
            }
        }

        guard let best else { return nil }
        return ReceiptTransactionMatch(
            receiptID: receipt.id,
            transactionID: best.transaction.id,
            confidence: best.score,
            rationale: best.rationale
        )
    }

    /// Token-overlap similarity, robust to OCR noise and descriptor suffixes.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let tokensA = Set(a.lowercased().split(separator: " ").map(String.init))
        let tokensB = Set(b.lowercased().split(separator: " ").map(String.init))
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }
        let overlap = tokensA.intersection(tokensB).count
        return Double(overlap) / Double(min(tokensA.count, tokensB.count))
    }
}
