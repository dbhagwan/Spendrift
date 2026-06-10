import Foundation
import SwiftData

@Model
final class Budget {
    @Attribute(.unique) var id: UUID
    /// Total monthly budget across all spend categories.
    var monthlyTotal: Decimal
    /// Day of month the budget period starts (1–28).
    var periodStartDay: Int
    var currencyCode: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.budget)
    var categories: [BudgetCategory] = []

    init(
        id: UUID = UUID(),
        monthlyTotal: Decimal,
        periodStartDay: Int = 1,
        currencyCode: String = "USD",
        createdAt: Date = .now
    ) {
        self.id = id
        self.monthlyTotal = monthlyTotal
        self.periodStartDay = periodStartDay
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func limit(for category: SpendingCategory) -> Decimal? {
        categories.first { $0.category == category }?.monthlyLimit
    }

    /// Current budget period containing `date`, respecting the custom start day.
    func period(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = periodStartDay
        var start = calendar.date(from: components) ?? date
        if start > date {
            start = calendar.date(byAdding: .month, value: -1, to: start) ?? start
        }
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

@Model
final class BudgetCategory {
    @Attribute(.unique) var id: UUID
    var categoryRaw: String
    var monthlyLimit: Decimal
    /// True if this limit came from the AI recommendation rather than manual entry.
    var isAIRecommended: Bool

    var budget: Budget?

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .miscellaneous }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        category: SpendingCategory,
        monthlyLimit: Decimal,
        isAIRecommended: Bool = false
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.monthlyLimit = monthlyLimit
        self.isAIRecommended = isAIRecommended
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var appleUserID: String?
    var displayName: String
    var currencyCode: String
    var privacyModeEnabled: Bool
    var appLockEnabled: Bool
    /// Categories the user excluded from safe-to-spend, as raw values.
    var excludedSafeToSpendCategories: [String]
    var onboardingCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        appleUserID: String? = nil,
        displayName: String = "",
        currencyCode: String = "USD",
        privacyModeEnabled: Bool = false,
        appLockEnabled: Bool = false,
        excludedSafeToSpendCategories: [String] = [],
        onboardingCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.currencyCode = currencyCode
        self.privacyModeEnabled = privacyModeEnabled
        self.appLockEnabled = appLockEnabled
        self.excludedSafeToSpendCategories = excludedSafeToSpendCategories
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
    }
}

@Model
final class NetWorthSnapshot {
    @Attribute(.unique) var id: UUID
    var date: Date
    var totalAssets: Decimal
    var totalLiabilities: Decimal

    var netWorth: Decimal { totalAssets - totalLiabilities }

    init(id: UUID = UUID(), date: Date, totalAssets: Decimal, totalLiabilities: Decimal) {
        self.id = id
        self.date = date
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
    }
}
