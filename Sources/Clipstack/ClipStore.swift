import AppKit
import Combine
import Foundation

/// Local-first history store.
///
/// The index is a single JSON file; image payloads are separate files on disk.
/// Everything lives under ~/Library/Application Support/Clipstack and never
/// leaves the machine.
@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Fired after every capture, deduplicated or not, so the UI can confirm
    /// that something landed.
    var onCapture: ((ClipItem) -> Void)?

    static let baseURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Clipstack", isDirectory: true)
    }()

    private var indexURL: URL { Self.baseURL.appendingPathComponent("index.json") }
    private var blobsURL: URL { Self.baseURL.appendingPathComponent("blobs", isDirectory: true) }

    private var saveWorkItem: DispatchWorkItem?
    private var isRecognizingText = false
    private var imageCache = NSCache<NSString, NSImage>()

    init() {
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        load()
        // Catches up on images captured before OCR existed or while it was off.
        recognizeTextIfNeeded()
    }

    // MARK: - Reading

    func image(for item: ClipItem) -> NSImage? {
        guard let blobFile = item.blobFile else { return nil }
        if let cached = imageCache.object(forKey: blobFile as NSString) { return cached }
        let url = blobsURL.appendingPathComponent(blobFile)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: blobFile as NSString)
        return image
    }

    func blobURL(for item: ClipItem) -> URL? {
        guard let blobFile = item.blobFile else { return nil }
        return blobsURL.appendingPathComponent(blobFile)
    }

    // MARK: - Writing

    /// Inserts a capture, collapsing it into the existing entry when the same
    /// content was already recorded.
    func insert(_ item: ClipItem, imageData: Data? = nil) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            items[existingIndex].updatedAt = Date()
            items[existingIndex].appBundleID = item.appBundleID ?? items[existingIndex].appBundleID
            items[existingIndex].appName = item.appName ?? items[existingIndex].appName
            // Read it before sorting moves it.
            let refreshed = items[existingIndex]
            sortAndPersist()
            onCapture?(refreshed)
            return
        }

        var stored = item
        if let imageData {
            let filename = "\(stored.id.uuidString).png"
            let url = blobsURL.appendingPathComponent(filename)
            do {
                try imageData.write(to: url, options: .atomic)
                stored.blobFile = filename
                stored.byteSize = imageData.count
            } catch {
                NSLog("Clipstack: failed to write blob: \(error.localizedDescription)")
                return
            }
        }

        items.insert(stored, at: 0)
        trim()
        sortAndPersist()
        onCapture?(stored)
        if stored.kind == .image { recognizeTextIfNeeded() }
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        sortAndPersist()
    }

    func delete(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeBlob(of: items[index])
        items.remove(at: index)
        persist()
    }

    func clear(keepPinned: Bool) {
        let survivors = keepPinned ? items.filter(\.pinned) : []
        for item in items where !survivors.contains(where: { $0.id == item.id }) {
            removeBlob(of: item)
        }
        items = survivors
        persist()
    }

    // MARK: - Text recognition

    /// Runs OCR over images that have not been read yet, one at a time and off
    /// the main actor, newest first. Safe to call often: a pass already in
    /// flight picks up whatever arrived meanwhile.
    func recognizeTextIfNeeded() {
        guard Preferences.shared.recognizeText, !isRecognizingText else { return }
        isRecognizingText = true
        Task { @MainActor in
            defer { isRecognizingText = false }
            while let item = items.first(where: { $0.kind == .image && $0.recognizedText == nil }) {
                guard let url = blobURL(for: item) else {
                    setRecognizedText("", for: item.id)
                    continue
                }
                let text = await TextRecognizer.recognize(at: url)
                setRecognizedText(text, for: item.id)
            }
        }
    }

    /// No re-sort: reading an image does not make it more recent.
    private func setRecognizedText(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recognizedText = text
        persist()
    }

    // MARK: - Internals

    private func sortAndPersist() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        persist()
    }

    /// Drops the oldest unpinned entries once the history exceeds the configured cap.
    private func trim() {
        let limit = Preferences.shared.historyLimit
        guard items.count > limit else { return }
        var unpinned = items.enumerated().filter { !$0.element.pinned }
        var overflow = items.count - limit
        while overflow > 0, let last = unpinned.popLast() {
            removeBlob(of: last.element)
            items.removeAll { $0.id == last.element.id }
            overflow -= 1
        }
    }

    private func removeBlob(of item: ClipItem) {
        guard let blobFile = item.blobFile else { return }
        imageCache.removeObject(forKey: blobFile as NSString)
        try? FileManager.default.removeItem(at: blobsURL.appendingPathComponent(blobFile))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }

    /// Debounced so a burst of copies does not rewrite the index on every keystroke.
    private func persist() {
        saveWorkItem?.cancel()
        let snapshot = items
        let url = indexURL
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Flushes any pending write. Called on termination.
    func flush() {
        saveWorkItem?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
