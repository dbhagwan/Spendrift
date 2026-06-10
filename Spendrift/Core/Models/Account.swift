import Foundation
import SwiftData

enum AccountKind: String, Codable, CaseIterable, Sendable {
    case checking
    case savings
    case creditCard
    case loan
    case investment
    case other

    var isLiability: Bool {
        switch self {
        case .creditCard, .loan: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .creditCard: "Credit Card"
        case .loan: "Loan"
        case .investment: "Investment"
        case .other: "Other"
        }
    }
}

/// How an account participates in derived numbers. Users can override per account.
enum AccountRole: String, Codable, Sendable {
    case full          // counts toward net worth and spending
    case spendingOnly  // transactions count, balance excluded from net worth
    case assetOnly     // balance counts, transactions excluded from spend
    case liabilityOnly
}

@Model
final class LinkedInstitution {
    @Attribute(.unique) var id: UUID
    /// Plaid item_id; the access token itself lives server-side only.
    var providerItemID: String
    var name: String
    var logoSystemImage: String
    var requiresRelink: Bool
    var lastSyncedAt: Date?
    var lastSyncError: String?

    @Relationship(deleteRule: .cascade, inverse: \Account.institution)
    var accounts: [Account] = []

    init(
        id: UUID = UUID(),
        providerItemID: String,
        name: String,
        logoSystemImage: String = "building.columns",
        requiresRelink: Bool = false,
        lastSyncedAt: Date? = nil,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.providerItemID = providerItemID
        self.name = name
        self.logoSystemImage = logoSystemImage
        self.requiresRelink = requiresRelink
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncError = lastSyncError
    }
}

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var providerAccountID: String
    var institutionName: String
    var name: String
    var kindRaw: String
    var subtype: String
    var mask: String
    var currentBalance: Decimal
    var availableBalance: Decimal?
    var creditLimit: Decimal?
    var currencyCode: String
    var isHidden: Bool
    var roleRaw: String
    var isClosed: Bool

    var institution: LinkedInstitution?

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var role: AccountRole {
        get { AccountRole(rawValue: roleRaw) ?? .full }
        set { roleRaw = newValue.rawValue }
    }

    /// Signed contribution to net worth: liabilities subtract.
    var netWorthContribution: Decimal {
        guard !isHidden, !isClosed, role != .spendingOnly else { return 0 }
        return kind.isLiability ? -currentBalance : currentBalance
    }

    init(
        id: UUID = UUID(),
        providerAccountID: String,
        institutionName: String,
        name: String,
        kind: AccountKind,
        subtype: String,
        mask: String,
        currentBalance: Decimal,
        availableBalance: Decimal? = nil,
        creditLimit: Decimal? = nil,
        currencyCode: String = "USD",
        isHidden: Bool = false,
        role: AccountRole = .full,
        isClosed: Bool = false
    ) {
        self.id = id
        self.providerAccountID = providerAccountID
        self.institutionName = institutionName
        self.name = name
        self.kindRaw = kind.rawValue
        self.subtype = subtype
        self.mask = mask
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.creditLimit = creditLimit
        self.currencyCode = currencyCode
        self.isHidden = isHidden
        self.roleRaw = role.rawValue
        self.isClosed = isClosed
    }
}
