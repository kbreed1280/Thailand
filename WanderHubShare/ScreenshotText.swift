import UIKit
import Vision

/// Reads text from screenshots on the device (Apple Vision), e.g. place names shown in a video.
/// NOTE: identical copies in Thailand/Services/Import and WanderHubShare. Keep both in sync.
enum ScreenshotText {
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "th-TH"]
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
