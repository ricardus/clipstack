import AppKit
import CryptoKit
import Foundation

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, file, color

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .image: return "Images"
        case .file: return "Files"
        case .color: return "Colors"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }
}

/// One entry in the clipboard history.
///
/// Small payloads (text, links, colors, file paths) live inline in `text`.
/// Images are written to `blobs/<blobFile>` and only referenced from here, so
/// the JSON index stays small enough to load on every launch.
struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: ClipKind
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pinned: Bool = false
    var appBundleID: String?
    var appName: String?
    /// SHA-256 of the payload, used to collapse repeated copies of the same content.
    var contentHash: String
    var text: String?
    var blobFile: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteSize: Int = 0
    /// Text found in an image by on-device OCR. Nil until it has been tried,
    /// "" when the image holds no text.
    var recognizedText: String?

    /// Single-line text used by the list row and by the search filter.
    var preview: String {
        switch kind {
        case .text, .link, .color:
            let raw = text ?? ""
            let flattened = raw.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return flattened.isEmpty ? "(empty)" : flattened
        case .file:
            let paths = (text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
            return paths.joined(separator: ", ")
        case .image:
            let size = pixelWidth.flatMap { w in pixelHeight.map { h in "Image \(w)x\(h)" } } ?? "Image"
            let firstLine = recognizedText?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let firstLine, !firstLine.isEmpty else { return size }
            return "\(size): \(firstLine)"
        }
    }

    var searchHaystack: String {
        [preview, text ?? "", recognizedText ?? "", appName ?? ""].joined(separator: " ").lowercased()
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }
}
