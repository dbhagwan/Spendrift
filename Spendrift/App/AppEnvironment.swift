import Foundation
import SwiftData
import SwiftUI

/// Composition root: wires services together and holds cross-cutting app state.
/// Injected via SwiftUI Environment so previews can swap in mock services.
@MainActor
@Observable
final class AppEnvironment {
    let api: BackendAPI
    let ai: AIInferenceService
    let pipeline: AIPipeline
    let syncService: SyncService
    let auth: AuthService
    let plaidLink: PlaidLinkService
    let receiptCapture: ReceiptCaptureService

    var syncState: SyncState = .idle
    var privacyModeEnabled = false

    init(useMocks: Bool) {
        let api = BackendAPI()
        self.api = api
        // All AI runs on-device via Apple's Foundation Models (Apple
        // Intelligence). Falls back to deterministic heuristics wherever the
        // model is unavailable (ineligible device, AI disabled, simulators).
        let ai = FoundationModelsAIService()
        self.ai = ai
        self.pipeline = AIPipeline(ai: ai)
        self.syncService = useMocks ? MockSyncService() : BackendSyncService(api: api)
        self.auth = AuthService()
        self.plaidLink = PlaidLinkService(api: api)
        self.receiptCapture = ReceiptCaptureService(ai: ai)
    }

    /// Mock-backed environment for previews and local development.
    static func mock() -> AppEnvironment {
        AppEnvironment(useMocks: true)
    }

    func sync(context: ModelContext) async {
        syncState = .syncing(progress: 0.2)
        do {
            try await syncService.sync(into: context, pipeline: pipeline)
            syncState = .completed(.now)
        } catch {
            syncState = .failed(message: error.localizedDescription)
        }
    }
}
