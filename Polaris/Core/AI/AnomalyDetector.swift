import Foundation

/// Flags charges that are statistical outliers for their category and writes
/// the evidence strings the narrative layer cites. Deterministic math — the
/// on-device model only narrates what was measured.
enum AnomalyDetector {
    /// Marks `isAnomaly` on outlier transactions from the last 30 days and
    /// returns human-readable summaries (newest first, capped at 5).
    static func detect(in transactions: [Transaction]) -> [String] {
        let spend = transactions.filter(\.countsAsSpend)
        let windowStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        for transaction in spend {
            transaction.isAnomaly = false
        }

        var flagged: [(date: Date, summary: String)] = []
        for (category, group) in Dictionary(grouping: spend, by: \.category) {
            // Baseline from history *before* the window so the outlier can't
            // inflate its own yardstick.
            let history = group.filter { $0.date < windowStart }.map(\.amount.doubleValue)
            guard history.count >= 5 else { continue }
            let mean = history.reduce(0, +) / Double(history.count)
            guard mean > 0 else { continue }
            let variance = history.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(history.count)
            let threshold = mean + max(2.5 * variance.squareRoot(), mean * 0.75)

            for transaction in group
            where transaction.date >= windowStart && transaction.amount.doubleValue > threshold {
                transaction.isAnomaly = true
                let multiple = (transaction.amount.doubleValue / mean)
                    .formatted(.number.precision(.fractionLength(1)))
                flagged.append((
                    transaction.date,
                    "\(transaction.normalizedDescription) \(transaction.amount.currency(showCents: false)) on \(transaction.date.shortDay) — \(multiple)× your typical \(category.displayName.lowercased()) charge (usual: \(Decimal(mean).currency(showCents: false)))"
                ))
            }
        }
        return flagged.sorted { $0.date > $1.date }.prefix(5).map(\.summary)
    }
}
