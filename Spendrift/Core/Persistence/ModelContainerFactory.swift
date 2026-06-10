import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        UserProfile.self,
        LinkedInstitution.self,
        Account.self,
        Transaction.self,
        Receipt.self,
        Budget.self,
        BudgetCategory.self,
        NetWorthSnapshot.self,
    ])

    static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container pre-seeded with sample data for previews and UI development.
    @MainActor
    static func preview() -> ModelContainer {
        let container = make(inMemory: true)
        SampleData.seed(into: container.mainContext)
        return container
    }
}
