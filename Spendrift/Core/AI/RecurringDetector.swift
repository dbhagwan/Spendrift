import Foundation

/// Detects recurring charges, paycheck cadence, and internal transfers from
/// transaction history. Pure functions over value snapshots so it's trivially
/// testable.
enum RecurringDetector {
    struct RecurringSeries: Sendable {
        var merchant: String
        var averageAmount: Decimal
        var category: SpendingCategory
        var isDiscretionary: Bool
        var cadenceDays: Int
        var lastDate: Date
        var nextExpectedDate: Date {
            Calendar.current.date(byAdding: .day, value: cadenceDays, to: lastDate) ?? lastDate
        }
    }

    /// Groups by normalized merchant and looks for stable cadence (weekly,
    /// biweekly, monthly ±4 days) with amounts inside a ±15% band.
    static func detectSeries(in transactions: [Transaction]) -> [RecurringSeries] {
        let spend = transactions.filter { $0.amount > 0 && !$0.isTransfer && $0.supersededByProviderID == nil }
        let grouped = Dictionary(grouping: spend, by: { $0.normalizedDescription.lowercased() })
        var series: [RecurringSeries] = []

        for (_, group) in grouped where group.count >= 3 {
            let sorted = group.sorted { $0.date < $1.date }
            let gaps = zip(sorted.dropFirst(), sorted).map { $1.date.daysUntil($0.date) }
            guard let cadence = stableCadence(gaps) else { continue }

            let amounts = sorted.map(\.amount.doubleValue)
            let mean = amounts.reduce(0, +) / Double(amounts.count)
            guard mean > 0 else { continue }
            let withinBand = amounts.allSatisfy { abs($0 - mean) / mean <= 0.15 }
            guard withinBand, let last = sorted.last else { continue }

            series.append(RecurringSeries(
                merchant: last.normalizedDescription,
                averageAmount: Decimal(mean),
                category: last.category,
                isDiscretionary: !last.isEssential,
                cadenceDays: cadence,
                lastDate: last.date
            ))
        }
        return series.sorted { $0.nextExpectedDate < $1.nextExpectedDate }
    }

    /// Detects paycheck cadence from income inflows. Returns expected next
    /// paycheck date and typical amount if a stable pattern exists.
    static func detectPaycheck(in transactions: [Transaction]) -> (nextDate: Date, amount: Decimal)? {
        let income = transactions
            .filter { $0.amount < 0 && $0.category == .income }
            .sorted { $0.date < $1.date }
        guard income.count >= 3 else { return nil }
        let gaps = zip(income.dropFirst(), income).map { $1.date.daysUntil($0.date) }
        guard let cadence = stableCadence(gaps), let last = income.last else { return nil }
        let amounts = income.suffix(3).map { -$0.amount.doubleValue }
        let typical = Decimal(amounts.reduce(0, +) / Double(amounts.count))
        let next = Calendar.current.date(byAdding: .day, value: cadence, to: last.date) ?? last.date
        return (next, typical)
    }

    /// Flags opposite-amount pairs across different owned accounts within a
    /// 3-day window as internal transfers.
    static func detectTransfers(in transactions: [Transaction]) -> Set<UUID> {
        var flagged = Set<UUID>()
        let candidates = transactions.filter { $0.supersededByProviderID == nil }
        for a in candidates {
            for b in candidates
            where a.id != b.id
                && a.accountID != b.accountID
                && a.amount == -b.amount
                && abs(a.date.timeIntervalSince(b.date)) <= 86_400.0 * 3
                && a.amount > 0
            {
                flagged.insert(a.id)
                flagged.insert(b.id)
            }
        }
        return flagged
    }

    /// Marks pending transactions superseded by a posted twin (same account,
    /// same amount, within 5 days) so totals never double-count.
    static func deduplicatePendingPosted(in transactions: [Transaction]) {
        let posted = transactions.filter { $0.status == .posted }
        for pending in transactions where pending.status == .pending && pending.supersededByProviderID == nil {
            if let twin = posted.first(where: {
                $0.accountID == pending.accountID
                    && $0.amount == pending.amount
                    && abs($0.date.timeIntervalSince(pending.date)) <= 86_400.0 * 5
            }) {
                pending.supersededByProviderID = twin.providerTransactionID
            }
        }
    }

    private static func stableCadence(_ gaps: [Int]) -> Int? {
        guard !gaps.isEmpty else { return nil }
        let mean = Double(gaps.reduce(0, +)) / Double(gaps.count)
        for target in [7, 14, 15, 30, 31] {
            if abs(mean - Double(target)) <= 4,
               gaps.allSatisfy({ abs($0 - target) <= 4 })
            {
                return target
            }
        }
        return nil
    }
}
