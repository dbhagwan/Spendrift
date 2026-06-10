import Foundation

/// Wraps the Plaid Link flow. Token lifecycle:
///   1. backend creates a `link_token` (POST /plaid/link-token)
///   2. app presents Plaid Link with it
///   3. Link returns a `public_token` on success
///   4. app posts it to the backend, which exchanges it for an `access_token`
///      and stores it server-side. The access token NEVER reaches the device.
///
/// TODO: Add the Plaid Link iOS SDK via Swift Package Manager
/// (https://github.com/plaid/plaid-link-ios) and replace the stubbed
/// presentation below with `LinkKit.Plaid.create(...)`.
@MainActor
final class PlaidLinkService {
    private let api: BackendAPI

    init(api: BackendAPI) {
        self.api = api
    }

    struct LinkResult: Sendable {
        var institutionName: String
        var providerItemID: String
    }

    func linkNewInstitution() async throws -> LinkResult {
        let linkToken = try await api.createLinkToken()

        // TODO(plaid-sdk): present Plaid Link UI with `linkToken` here.
        // let handler = try Plaid.create(LinkTokenConfiguration(token: linkToken) { success in ... })
        // handler.open(presentUsing: ...)
        _ = linkToken

        // Until the SDK is wired up, simulate a successful link so the
        // onboarding flow is fully navigable in development.
        let publicToken = "public-sandbox-simulated"
        let exchange = try await api.exchangePublicToken(publicToken)
        return LinkResult(institutionName: exchange.institutionName, providerItemID: exchange.itemID)
    }

    func relink(itemID: String) async throws {
        // TODO(plaid-sdk): create link token in update mode and re-present Link.
        _ = try await api.createLinkToken()
    }
}
