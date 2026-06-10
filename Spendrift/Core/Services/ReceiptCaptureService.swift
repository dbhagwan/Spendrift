import Foundation
import SwiftData
import SwiftUI
import Vision
import VisionKit

/// Receipt capture pipeline:
///   capture/import image → Vision OCR → deterministic parse →
///   AI extraction fallback when parse confidence is low →
///   persist Receipt → AIPipeline matches it to a transaction.
@MainActor
final class ReceiptCaptureService {
    private let ai: AIInferenceService

    init(ai: AIInferenceService) {
        self.ai = ai
    }

    /// OCR + extract + persist a captured receipt image. Returns the receipt;
    /// matching happens in the next `AIPipeline.recompute`.
    func process(image: UIImage, in context: ModelContext, pipeline: AIPipeline) async throws -> Receipt {
        let filename = "receipt-\(UUID().uuidString).jpg"
        try saveImage(image, filename: filename)

        let (text, ocrConfidence) = try await recognizeText(in: image)
        var extraction = ReceiptParser.parse(ocrText: text, ocrConfidence: ocrConfidence)

        // Escalate to AI extraction when deterministic parsing is unsure.
        if extraction.extractionConfidence < 0.6,
           let aiExtraction = await ai.extractReceipt(ocrText: text),
           aiExtraction.extractionConfidence > extraction.extractionConfidence
        {
            extraction = aiExtraction
        }

        let receipt = Receipt(imageReference: filename, ocrText: text)
        extraction.apply(to: receipt)
        context.insert(receipt)
        try context.save()

        // TODO(backend): upload image + extraction to POST /receipts for
        // durable storage and server-side enrichment.

        await pipeline.recompute(in: context)
        return receipt
    }

    // MARK: - OCR

    private func recognizeText(in image: UIImage) async throws -> (text: String, confidence: Double) {
        guard let cgImage = image.cgImage else { return ("", 0) }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        let lines = observations.compactMap { $0.topCandidates(1).first }
        let text = lines.map(\.string).joined(separator: "\n")
        let confidence = lines.isEmpty
            ? 0
            : Double(lines.map(\.confidence).reduce(0, +)) / Double(lines.count)
        return (text, confidence)
    }

    // MARK: - Image storage

    static var imagesDirectory: URL {
        let url = URL.documentsDirectory.appendingPathComponent("Receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func saveImage(_ image: UIImage, filename: String) throws {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try data.write(to: Self.imagesDirectory.appendingPathComponent(filename), options: .atomic)
    }

    static func loadImage(reference: String) -> UIImage? {
        UIImage(contentsOfFile: imagesDirectory.appendingPathComponent(reference).path)
    }
}

/// SwiftUI wrapper for the VisionKit document camera (multi-page capable).
struct ReceiptScannerView: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
            controller.dismiss(animated: true)
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            onCancel()
        }
    }
}
