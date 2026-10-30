import Foundation
import Vision

/// On-device OCR for images in the history, so a screenshot can be found by
/// the words in it. Vision runs locally; nothing is uploaded.
enum TextRecognizer {
    /// Recognised lines joined with newlines, or "" when the image holds no
    /// text or cannot be read. Never nil, so callers can record that an image
    /// was already tried.
    static func recognize(at url: URL) async -> String {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(url: url)
            do {
                try handler.perform([request])
            } catch {
                NSLog("Clipstack: text recognition failed: \(error.localizedDescription)")
                return ""
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
