import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    @Bindable var transaction: Transaction

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var receipts: [Receipt]
    @Query private var accounts: [Account]

    @State private var showSplit = false

    private var receipt: Receipt? {
        guard let id = transaction.receiptID else { return nil }
        return receipts.first { $0.id == id }
    }

    private var account: Account? {
        accounts.first { $0.id == transaction.accountID }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    AmountText(amount: -transaction.amount, font: .system(size: 38, weight: .bold), colorBySign: transaction.amount < 0)
                    Text(transaction.normalizedDescription).font(.headline)
                    Text(transaction.date.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Category") {
                Picker("Category", selection: categoryBinding) {
                    ForEach(SpendingCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                LabeledContent("Confidence") {
                    ConfidenceBadge(confidence: transaction.categoryConfidence, source: transaction.categorySource)
                }
                if transaction.categorySource != .user {
                    Text("Correcting the category teaches Spendrift — future \(transaction.normalizedDescription) charges will use your choice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Flags") {
                Toggle("Transfer", isOn: flagBinding(\.isTransfer))
                Toggle("Reimbursable", isOn: flagBinding(\.isReimbursement))
                Toggle("Recurring", isOn: flagBinding(\.isRecurring))
                Toggle("Essential", isOn: flagBinding(\.isEssential))
            }

            if let receipt {
                Section("Receipt") {
                    NavigationLink {
                        ReceiptDetailView(receipt: receipt)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(receipt.merchant ?? "Receipt")
                                if let total = receipt.total {
                                    Text(total.currency()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "doc.text.viewfinder")
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Account", value: account.map { "\($0.name) ••\($0.mask)" } ?? "—")
                LabeledContent("Status", value: transaction.status == .pending ? "Pending" : "Posted")
                LabeledContent("Raw description", value: transaction.rawDescription)
                if let city = transaction.locationCity {
                    LabeledContent("Location", value: [city, transaction.locationRegion].compactMap(\.self).joined(separator: ", "))
                }
            }

            Section {
                Button("Split transaction…") { showSplit = true }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSplit) {
            SplitTransactionView(transaction: transaction)
                .presentationDetents([.medium])
        }
    }

    private var categoryBinding: Binding<SpendingCategory> {
        Binding(
            get: { transaction.category },
            set: { newValue in
                Task {
                    await appEnvironment.pipeline.applyCorrection(transaction, to: newValue, in: modelContext)
                }
            }
        )
    }

    private func flagBinding(_ keyPath: ReferenceWritableKeyPath<Transaction, Bool>) -> Binding<Bool> {
        Binding(
            get: { transaction[keyPath: keyPath] },
            set: { newValue in
                transaction[keyPath: keyPath] = newValue
                transaction.categorySource = .user
                Task { await appEnvironment.pipeline.recompute(in: modelContext) }
            }
        )
    }
}

/// Splits a transaction into two: the original is reduced, a sibling is created
/// with the split amount and its own category.
struct SplitTransactionView: View {
    let transaction: Transaction

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var splitAmount: Double = 0
    @State private var splitCategory: SpendingCategory = .miscellaneous

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Original") {
                    Text(transaction.amount.currency())
                }
                HStack {
                    Text("Split amount")
                    Spacer()
                    TextField("0.00", value: $splitAmount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Picker("Split category", selection: $splitCategory) {
                    ForEach(SpendingCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
            }
            .navigationTitle("Split Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { performSplit() }
                        .disabled(splitAmount <= 0 || Decimal(splitAmount) >= transaction.amount)
                }
            }
        }
    }

    private func performSplit() {
        let amount = Decimal(splitAmount)
        let sibling = Transaction(
            providerTransactionID: transaction.providerTransactionID + "-split",
            accountID: transaction.accountID,
            amount: amount,
            date: transaction.date,
            merchantName: transaction.merchantName,
            rawDescription: transaction.rawDescription,
            normalizedDescription: transaction.normalizedDescription + " (split)",
            category: splitCategory,
            categorySource: .user,
            categoryConfidence: 1.0
        )
        transaction.amount -= amount
        modelContext.insert(sibling)
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
        dismiss()
    }
}
