import Foundation
import SwiftData

enum SyncState: Equatable, Sendable {
    case idle
    case syncing(progress: Double)
    case failed(message: String)
    case completed(Date)
}

/// Pulls normalized accounts/transactions. The production implementation talks
/// to the Spendrift backend (which owns Plaid access tokens and webhooks);
/// `MockSyncService` seeds realistic local data for development.
protocol SyncService: Sendable {
    /// Fetch latest normalized data and upsert into the local store.
    @MainActor func sync(into context: ModelContext, pipeline: AIPipeline) async throws
}

/// Backend-driven sync. The device never sees Plaid tokens — it asks the
/// backend for normalized data the webhook-driven jobs have already prepared.
struct BackendSyncService: SyncService {
    let api: BackendAPI

    @MainActor
    func sync(into context: ModelContext, pipeline: AIPipeline) async throws {
        let payload = try await api.fetchSyncPayload()

        let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for dto in payload.accounts {
            if let existing = existingAccounts.first(where: { $0.providerAccountID == dto.providerAccountID }) {
                existing.currentBalance = dto.currentBalance
                existing.availableBalance = dto.availableBalance
                existing.creditLimit = dto.creditLimit
            } else {
                context.insert(dto.makeAccount())
            }
        }

        let existingTxns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let knownIDs = Set(existingTxns.map(\.providerTransactionID))
        let accountsByProviderID = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
                .map { ($0.providerAccountID, $0.id) }
        )
        for dto in payload.transactions where !knownIDs.contains(dto.providerTransactionID) {
            guard let accountID = accountsByProviderID[dto.providerAccountID] else { continue }
            let result = await pipeline.categorization.categorize(
                merchant: dto.merchantName,
                rawDescription: dto.rawDescription,
                amount: dto.amount,
                providerCategoryHint: dto.providerCategory
            )
            context.insert(dto.makeTransaction(accountID: accountID, categorization: result))
        }

        try context.save()
        await pipeline.recompute(in: context)
    }
}

/// Seeds sample data once, then re-runs the pipeline. Lets the entire app be
/// exercised without a backend or Plaid credentials.
struct MockSyncService: SyncService {
    @MainActor
    func sync(into context: ModelContext, pipeline: AIPipeline) async throws {
        let hasData = ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) > 0
        if !hasData {
            SampleData.seed(into: context)
        }
        // Simulate network latency so loading states are visible in development.
        try? await Task.sleep(for: .milliseconds(600))
        await pipeline.recompute(in: context)
    }
}
