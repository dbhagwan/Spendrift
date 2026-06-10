import Foundation

/// Typed client for the Spendrift backend (see Backend/ in this repo).
/// All Plaid and model-provider credentials live server-side; this client
/// only carries the user's session token.
struct BackendAPI: Sendable {
    // TODO(config): point at the deployed backend; localhost works with
    // `npm run dev` in Backend/ for simulator development.
    var baseURL = URL(string: "http://localhost:3000")!
    var session: URLSession = .shared

    enum APIError: Error {
        case badStatus(Int)
        case notAuthenticated
    }

    // MARK: - Plaid

    func createLinkToken() async throws -> String {
        struct Response: Decodable { let linkToken: String }
        let response: Response = try await post("plaid/link-token")
        return response.linkToken
    }

    struct ExchangeResult: Decodable, Sendable {
        let itemID: String
        let institutionName: String
    }

    func exchangePublicToken(_ publicToken: String) async throws -> ExchangeResult {
        try await post("plaid/exchange", body: ["publicToken": publicToken])
    }

    // MARK: - Sync

    struct SyncPayload: Decodable, Sendable {
        let accounts: [AccountDTO]
        let transactions: [TransactionDTO]
    }

    func fetchSyncPayload() async throws -> SyncPayload {
        try await get("sync")
    }

    // MARK: - Requests

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET", body: nil as [String: String]?)
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]? = nil) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String, body: B?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainStore.get(.sessionToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - DTOs

struct AccountDTO: Decodable, Sendable {
    var providerAccountID: String
    var institutionName: String
    var name: String
    var kind: String
    var subtype: String
    var mask: String
    var currentBalance: Decimal
    var availableBalance: Decimal?
    var creditLimit: Decimal?
    var currencyCode: String

    func makeAccount() -> Account {
        Account(
            providerAccountID: providerAccountID,
            institutionName: institutionName,
            name: name,
            kind: AccountKind(rawValue: kind) ?? .other,
            subtype: subtype,
            mask: mask,
            currentBalance: currentBalance,
            availableBalance: availableBalance,
            creditLimit: creditLimit,
            currencyCode: currencyCode
        )
    }
}

struct TransactionDTO: Decodable, Sendable {
    var providerTransactionID: String
    var providerAccountID: String
    var amount: Decimal
    var date: Date
    var merchantName: String
    var rawDescription: String
    var pending: Bool
    var providerCategory: String?
    var locationCity: String?
    var locationRegion: String?

    func makeTransaction(accountID: UUID, categorization: CategorizationResult) -> Transaction {
        Transaction(
            providerTransactionID: providerTransactionID,
            accountID: accountID,
            amount: amount,
            date: date,
            merchantName: merchantName,
            rawDescription: rawDescription,
            normalizedDescription: CategorizationEngine.normalizeMerchant(rawDescription),
            status: pending ? .pending : .posted,
            category: categorization.category,
            subcategory: categorization.subcategory,
            categorySource: categorization.source,
            categoryConfidence: categorization.confidence,
            isEssential: categorization.isEssential,
            locationCity: locationCity,
            locationRegion: locationRegion
        )
    }
}
