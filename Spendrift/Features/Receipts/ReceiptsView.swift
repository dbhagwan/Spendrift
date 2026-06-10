import PhotosUI
import SwiftData
import SwiftUI

struct ReceiptsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.capturedAt, order: .reverse) private var receipts: [Receipt]

    @State private var searchText = ""
    @State private var segment: Segment = .all
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false

    enum Segment: String, CaseIterable {
        case all = "All"
        case matched = "Matched"
        case unmatched = "Unmatched"
    }

    private var visible: [Receipt] {
        receipts.filter { receipt in
            switch segment {
            case .all: break
            case .matched: guard receipt.matchStatus == .matched || receipt.matchStatus == .manuallyMatched else { return false }
            case .unmatched: guard receipt.matchStatus == .unmatched else { return false }
            }
            if !searchText.isEmpty {
                let haystack = "\(receipt.merchant ?? "") \(receipt.total?.currency() ?? "")".lowercased()
                return haystack.contains(searchText.lowercased())
            }
            return true
        }
    }

    var body: some View {
        List {
            Picker("Filter", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Reading receipt…").foregroundStyle(.secondary)
                }
            }

            ForEach(visible) { receipt in
                NavigationLink {
                    ReceiptDetailView(receipt: receipt)
                } label: {
                    ReceiptRow(receipt: receipt)
                }
            }

            if visible.isEmpty && !isProcessing {
                EmptyStateView(
                    systemImage: "doc.text.viewfinder",
                    title: "No receipts yet",
                    message: "Scan a receipt and Spendrift extracts the merchant, total, tip, and items — then matches it to the card charge.",
                    actionTitle: "Scan a receipt",
                    action: { showScanner = true }
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Receipts")
        .searchable(text: $searchText, prompt: "Merchant or amount")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                }
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "doc.viewfinder")
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ReceiptScannerView(
                onScan: { images in process(images: images) },
                onCancel: {}
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    process(images: [image])
                }
                photoItem = nil
            }
        }
    }

    private func process(images: [UIImage]) {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            for image in images {
                _ = try? await appEnvironment.receiptCapture.process(
                    image: image,
                    in: modelContext,
                    pipeline: appEnvironment.pipeline
                )
            }
        }
    }
}

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant ?? "Unknown merchant")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text((receipt.purchaseDate ?? receipt.capturedAt).shortDay)
                    Text("·").foregroundStyle(.tertiary)
                    Text(receipt.matchStatus.displayName)
                        .foregroundStyle(receipt.matchStatus == .unmatched ? Theme.warning : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let total = receipt.total {
                    AmountText(amount: total, font: .subheadline)
                }
                ConfidenceBadge(confidence: receipt.extractionConfidence)
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = ReceiptCaptureService.loadImage(reference: receipt.imageReference) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 52)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    NavigationStack { ReceiptsView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
