import Foundation
import LinkKit
import UIKit

/// Presents the Plaid Link flow and completes the token exchange.
///
/// Token lifecycle (the access token never reaches the device):
///   1. backend creates a `link_token` (POST /plaid/link-token)
///   2. this service presents Plaid Link with it
///   3. Link returns a `public_token` + institution metadata on success
///   4. backend exchanges it for an `access_token` and stores it server-side
///
/// In mock mode (`simulated: true`) the SDK is skipped entirely and a fake
/// institution is returned, keeping the whole app navigable without a
/// backend or Plaid credentials.
@MainActor
final class PlaidLinkService {
    enum LinkError: LocalizedError {
        case exited(String?)
        case noPresenter

        var errorDescription: String? {
            switch self {
            case .exited(let message): message ?? "Linking was cancelled."
            case .noPresenter: "Unable to present Plaid Link."
            }
        }
    }

    private let api: BackendAPI
    private let simulated: Bool
    /// Kept alive for the duration of the Link session.
    private var handler: Handler?

    init(api: BackendAPI, simulated: Bool) {
        self.api = api
        self.simulated = simulated
    }

    struct LinkResult: Sendable {
        var institutionName: String
        var providerItemID: String
    }

    func linkNewInstitution() async throws -> LinkResult {
        if simulated {
            try? await Task.sleep(for: .milliseconds(400))
            return LinkResult(
                institutionName: "Plaid Sandbox Bank",
                providerItemID: "item-simulated-\(UUID().uuidString.prefix(8))"
            )
        }
        let linkToken = try await api.createLinkToken()
        let success = try await presentLink(token: linkToken)
        let exchange = try await api.exchangePublicToken(
            success.publicToken,
            institutionName: success.institutionName
        )
        return LinkResult(institutionName: exchange.institutionName, providerItemID: exchange.itemID)
    }

    func relink(itemID: String) async throws {
        // TODO(backend): add update-mode link tokens (POST /plaid/link-token
        // with item_id) and re-present Link here.
        _ = try await api.createLinkToken()
    }

    // MARK: - Link presentation

    private func presentLink(token: String) async throws -> (publicToken: String, institutionName: String) {
        try await withCheckedThrowingContinuation { continuation in
            var configuration = LinkTokenConfiguration(token: token) { success in
                // LinkKit calls back on the main thread.
                MainActor.assumeIsolated {
                    self.handler = nil
                    continuation.resume(returning: (
                        success.publicToken,
                        success.metadata.institution.name
                    ))
                }
            }
            configuration.onExit = { exit in
                MainActor.assumeIsolated {
                    self.handler = nil
                    continuation.resume(throwing: LinkError.exited(exit.error?.localizedDescription))
                }
            }

            switch Plaid.create(configuration) {
            case .success(let handler):
                self.handler = handler
                guard let presenter = Self.topViewController() else {
                    self.handler = nil
                    continuation.resume(throwing: LinkError.noPresenter)
                    return
                }
                handler.open(presentUsing: .viewController(presenter))
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
