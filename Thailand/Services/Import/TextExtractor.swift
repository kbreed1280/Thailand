import UIKit
import Vision
import PDFKit

/// Reads text from screenshots, photos and PDFs entirely on the device.
enum TextExtractor {
    /// Vision OCR. Recognizes English, plus Thai where the OS supports it.
    static func text(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["en-US", "th-TH"].filter { supported.contains($0) }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image.imageOrientation))
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    /// PDF text layer first; scanned PDFs (no text) are rendered and OCR'd (first 5 pages).
    static func text(fromPDF data: Data) async -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        let layer = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if layer.count >= 20 { return layer }

        var pages: [String] = []
        for index in 0..<min(document.pageCount, 5) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: bounds.width * scale, height: bounds.height * scale))
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
                context.cgContext.translateBy(x: 0, y: bounds.height * scale)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            pages.append(await text(from: image))
        }
        return pages.joined(separator: "\n")
    }

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
