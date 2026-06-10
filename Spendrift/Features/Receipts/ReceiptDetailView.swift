import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var showMatchPicker = false

    private var matchedTransaction: Transaction? {
        guard let id = receipt.matchedTransactionID else { return nil }
        return transactions.first { $0.id == id }
    }

    var body: some View {
        List {
            if let image = ReceiptCaptureService.loadImage(reference: receipt.imageReference) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowBackground(Color.clear)
                }
            }

            Section("Extraction") {
                LabeledContent("Merchant", value: receipt.merchant ?? "—")
                LabeledContent("Date", value: (receipt.purchaseDate ?? receipt.capturedAt).formatted(date: .abbreviated, time: .omitted))
                if let subtotal = receipt.subtotal { amountRow("Subtotal", subtotal) }
                if let tax = receipt.tax { amountRow("Tax", tax) }
                if let tip = receipt.tip {
                    amountRow("Tip", tip)
                    if let subtotal = receipt.subtotal, subtotal > 0 {
                        let tipPercent = (tip / subtotal).doubleValue
                        if tipPercent > 0.25 {
                            Label("Tip is \(tipPercent.percentString) — above your usual range", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
                if let total = receipt.total { amountRow("Total", total) }
                LabeledContent("Category", value: receipt.inferredCategory?.displayName ?? "—")
                LabeledContent("Extraction confidence") {
                    ConfidenceBadge(confidence: receipt.extractionConfidence)
                }
            }

            if !receipt.lineItems.isEmpty {
                Section("Items") {
                    ForEach(receipt.lineItems) { item in
                        HStack {
                            Text(item.quantity > 1 ? "\(item.quantity)× \(item.name)" : item.name)
                                .font(.subheadline)
                            Spacer()
                            Text(item.price.currency())
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Transaction match") {
                if let matchedTransaction {
                    NavigationLink {
                        TransactionDetailView(transaction: matchedTransaction)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(matchedTransaction.normalizedDescription).font(.subheadline.weight(.medium))
                            HStack {
                                Text(matchedTransaction.date.shortDay)
                                Text(matchedTransaction.amount.currency())
                                if let confidence = receipt.matchConfidence {
                                    Text("· match \(confidence.percentString)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button("Unlink", role: .destructive) { unlink() }
                } else {
                    Text("No matching card charge found yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Match manually…") { showMatchPicker = true }
                    Button("Mark as cash purchase") {
                        receipt.matchStatus = .noMatchExpected
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle(receipt.merchant ?? "Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMatchPicker) { matchPicker }
    }

    private func amountRow(_ label: String, _ amount: Decimal) -> some View {
        LabeledContent(label) {
            Text(amount.currency()).monospacedDigit()
        }
    }

    private var matchPicker: some View {
        NavigationStack {
            List {
                // Candidates: spend within ±7 days of the receipt.
                let receiptDate = receipt.purchaseDate ?? receipt.capturedAt
                let candidates = transactions.filter {
                    $0.amount > 0 && abs($0.date.timeIntervalSince(receiptDate)) < 86_400 * 7
                }
                ForEach(candidates) { transaction in
                    Button {
                        link(to: transaction)
                    } label: {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Choose transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMatchPicker = false }
                }
            }
        }
    }

    private func link(to transaction: Transaction) {
        receipt.matchedTransactionID = transaction.id
        receipt.matchStatus = .manuallyMatched
        receipt.matchConfidence = 1.0
        transaction.receiptID = receipt.id
        try? modelContext.save()
        showMatchPicker = false
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }

    private func unlink() {
        if let matchedTransaction {
            matchedTransaction.receiptID = nil
        }
        receipt.matchedTransactionID = nil
        receipt.matchStatus = .unmatched
        receipt.matchConfidence = nil
        try? modelContext.save()
    }
}
