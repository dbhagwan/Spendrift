import SwiftData
import SwiftUI

struct TransactionFilter: Equatable {
    var category: SpendingCategory?
    var accountID: UUID?
    var recurringOnly = false
    var uncategorizedOnly = false

    var isActive: Bool {
        category != nil || accountID != nil || recurringOnly || uncategorizedOnly
    }
}

struct TransactionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]

    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var showFilters = false

    private var visible: [Transaction] {
        transactions.filter { transaction in
            guard !transaction.isHidden, transaction.supersededByProviderID == nil else { return false }
            if let category = filter.category, transaction.category != category { return false }
            if let accountID = filter.accountID, transaction.accountID != accountID { return false }
            if filter.recurringOnly && !transaction.isRecurring { return false }
            if filter.uncategorizedOnly && transaction.categoryConfidence >= 0.5 { return false }
            if !searchText.isEmpty {
                let haystack = "\(transaction.merchantName) \(transaction.normalizedDescription) \(transaction.category.displayName)".lowercased()
                if !haystack.contains(searchText.lowercased()) { return false }
            }
            return true
        }
    }

    private var groupedByDay: [(day: Date, transactions: [Transaction])] {
        Dictionary(grouping: visible, by: \.date.startOfDay)
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            ForEach(groupedByDay, id: \.day) { group in
                Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.transactions) { transaction in
                        NavigationLink(value: transaction.id) {
                            TransactionRow(transaction: transaction)
                        }
                        .swipeActions(edge: .trailing) {
                            swipeActions(for: transaction)
                        }
                    }
                }
            }
            if visible.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: searchText.isEmpty && !filter.isActive ? "No transactions yet" : "No matches",
                    message: searchText.isEmpty && !filter.isActive
                        ? "Transactions appear automatically after your accounts sync."
                        : "Try adjusting your search or filters."
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Transactions")
        .navigationDestination(for: UUID.self) { id in
            if let transaction = transactions.first(where: { $0.id == id }) {
                TransactionDetailView(transaction: transaction)
            }
        }
        .searchable(text: $searchText, prompt: "Merchant, category…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet.presentationDetents([.medium])
        }
        .refreshable { await appEnvironment.sync(context: modelContext) }
    }

    @ViewBuilder
    private func swipeActions(for transaction: Transaction) -> some View {
        Button {
            transaction.isHidden = true
            recompute()
        } label: {
            Label("Hide", systemImage: "eye.slash")
        }
        .tint(.gray)

        Button {
            transaction.isTransfer.toggle()
            transaction.categorySource = .user
            recompute()
        } label: {
            Label("Transfer", systemImage: "arrow.left.arrow.right")
        }
        .tint(.indigo)

        Button {
            transaction.isReimbursement.toggle()
            recompute()
        } label: {
            Label("Reimbursable", systemImage: "arrow.uturn.left.circle")
        }
        .tint(.teal)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $filter.category) {
                    Text("All").tag(SpendingCategory?.none)
                    ForEach(SpendingCategory.allCases) { category in
                        Text(category.displayName).tag(SpendingCategory?.some(category))
                    }
                }
                Picker("Account", selection: $filter.accountID) {
                    Text("All").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text("\(account.name) ••\(account.mask)").tag(UUID?.some(account.id))
                    }
                }
                Toggle("Recurring only", isOn: $filter.recurringOnly)
                Toggle("Low-confidence only", isOn: $filter.uncategorizedOnly)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = TransactionFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
    }

    private func recompute() {
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(transaction.normalizedDescription)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if transaction.receiptID != nil {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if transaction.isAnomaly {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                }
                HStack(spacing: 4) {
                    Text(transaction.category.displayName)
                    if transaction.isRecurring {
                        Image(systemName: "repeat").font(.caption2)
                    }
                    if transaction.status == .pending {
                        Text("Pending").italic()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: -transaction.amount, font: .subheadline, colorBySign: transaction.amount < 0)
                ConfidenceBadge(confidence: transaction.categoryConfidence, source: transaction.categorySource)
            }
        }
        .opacity(transaction.isTransfer ? 0.55 : 1)
    }
}

#Preview {
    NavigationStack { TransactionsView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
