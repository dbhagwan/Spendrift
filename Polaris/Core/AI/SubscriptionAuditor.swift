import Foundation

/// Deterministic audit over detected recurring series: price creep and
/// overlapping streaming services. Findings are structured, evidence-backed
/// insights — the math is the message, no model required.
enum SubscriptionAuditor {
    private static let streamingKeywords = [
        "netflix", "hulu", "max", "disney", "paramount", "peacock",
        "apple tv", "youtube prem", "spotify", "apple music", "tidal", "pandora",
    ]

    static func audit(
        series: [RecurringDetector.RecurringSeries],
        transactions: [Transaction]
    ) -> [SpendingInsight] {
        var insights: [SpendingInsight] = []
        let now = Date.now
        let subscriptions = series.filter { $0.category == .subscriptions }

        // Price creep: the latest charge vs. the series' first charge.
        for subscription in subscriptions {
            let charges = transactions
                .filter { $0.normalizedDescription.lowercased() == subscription.merchant.lowercased() && $0.amount > 0 }
                .sorted { $0.date < $1.date }
            guard let first = charges.first, let latest = charges.last,
                  first.id != latest.id, first.amount > 0 else { continue }
            let increase = ((latest.amount - first.amount) / first.amount).doubleValue
            guard increase >= 0.12 else { continue }
            insights.append(SpendingInsight(
                generatedAt: now,
                title: "\(subscription.merchant) price up \(increase.percentString)",
                detail: "This subscription was \(first.amount.currency()) when it started and is now \(latest.amount.currency()).",
                severity: .warning,
                category: .subscriptions,
                evidence: [
                    "First charge: \(first.amount.currency()) on \(first.date.shortDay)",
                    "Latest charge: \(latest.amount.currency()) on \(latest.date.shortDay)",
                ],
                confidence: 0.9
            ))
        }

        // Overlapping streaming/music services.
        let streaming = subscriptions.filter { subscription in
            streamingKeywords.contains { subscription.merchant.lowercased().contains($0) }
        }
        if streaming.count >= 3 {
            let total = streaming.reduce(Decimal(0)) { $0 + $1.averageAmount }
            insights.append(SpendingInsight(
                generatedAt: now,
                title: "\(streaming.count) streaming services — \(total.currency(showCents: false))/mo",
                detail: "You're paying for \(streaming.map(\.merchant).joined(separator: ", ")) at the same time. Dropping the one you use least is an easy save.",
                severity: .neutral,
                category: .subscriptions,
                evidence: streaming.map { "\($0.merchant): \($0.averageAmount.currency())/mo" },
                confidence: 0.85
            ))
        }
        return insights
    }
}
