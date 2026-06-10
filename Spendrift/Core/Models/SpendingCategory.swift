import Foundation

/// Canonical category taxonomy. All categorization (provider, rules, ML, user
/// corrections) resolves into one of these so every surface (budget, safe-to-spend,
/// analytics, widgets) speaks the same language.
enum SpendingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case income
    case housing
    case utilities
    case groceries
    case dining
    case travel
    case transportation
    case shopping
    case entertainment
    case health
    case insurance
    case debtPayments
    case transfers
    case investments
    case fees
    case subscriptions
    case taxes
    case miscellaneous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .income: "Income"
        case .housing: "Housing"
        case .utilities: "Utilities"
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .travel: "Travel"
        case .transportation: "Transportation"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .health: "Health"
        case .insurance: "Insurance"
        case .debtPayments: "Debt Payments"
        case .transfers: "Transfers"
        case .investments: "Investments"
        case .fees: "Fees"
        case .subscriptions: "Subscriptions"
        case .taxes: "Taxes"
        case .miscellaneous: "Miscellaneous"
        }
    }

    var systemImage: String {
        switch self {
        case .income: "arrow.down.circle"
        case .housing: "house"
        case .utilities: "bolt"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .travel: "airplane"
        case .transportation: "car"
        case .shopping: "bag"
        case .entertainment: "popcorn"
        case .health: "heart"
        case .insurance: "shield"
        case .debtPayments: "creditcard"
        case .transfers: "arrow.left.arrow.right"
        case .investments: "chart.line.uptrend.xyaxis"
        case .fees: "exclamationmark.circle"
        case .subscriptions: "repeat"
        case .taxes: "building.columns"
        case .miscellaneous: "ellipsis.circle"
        }
    }

    /// Categories that count toward discretionary spend and therefore feed
    /// the safe-to-spend computation by default. Users can override in Settings.
    var isDiscretionaryByDefault: Bool {
        switch self {
        case .dining, .travel, .shopping, .entertainment, .groceries, .transportation, .miscellaneous:
            true
        default:
            false
        }
    }

    /// Categories excluded from spend totals entirely (money movement, not spend).
    var isExcludedFromSpend: Bool {
        switch self {
        case .income, .transfers, .investments: true
        default: false
        }
    }

    /// Fixed-obligation categories used by the spending profile's fixed/variable split.
    var isTypicallyFixed: Bool {
        switch self {
        case .housing, .utilities, .insurance, .debtPayments, .subscriptions, .taxes: true
        default: false
        }
    }
}
