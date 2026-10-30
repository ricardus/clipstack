import AppKit
import Foundation

/// Watches the folder macOS writes screenshots into and files new captures
/// into the history alongside ordinary copies.
///
/// The first read of ~/Desktop triggers the system's folder-access prompt.
/// If the user declines, this quietly does nothing.
@MainActor
final class ScreenshotWatcher {
    static let sourceBundleID = "com.apple.screencapture"

    private let store: ClipStore
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var knownFiles: Set<String> = []
    private var directory: URL?

    init(store: ClipStore) {
        self.store = store
    }

    /// Honours the custom location set via `defaults write com.apple.screencapture location`.
    static func screenshotDirectory() -> URL {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (raw as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start() {
        stop()
        let directory = Self.screenshotDirectory()
        self.directory = directory

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Clipstack: cannot watch \(directory.path)")
            return
        }

        // Seed with what is already there so we only pick up captures taken
        // while the app is running.
        knownFiles = Set(imageFilenames(in: directory))

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                // Screenshots land in two steps; let the writer finish first.
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.scan()
            }
        }
        // Captured by value: the handler runs outside the main actor and must
        // not touch `self`.
        let openDescriptor = descriptor
        source.setCancelHandler { close(openDescriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func scan() {
        guard Preferences.shared.watchScreenshots, let directory else { return }
        let current = imageFilenames(in: directory)
        let added = Set(current).subtracting(knownFiles)
        knownFiles = Set(current)

        for filename in added.sorted() {
            let url = directory.appendingPathComponent(filename)
            guard let data = pngData(at: url) else { continue }
            let rep = NSBitmapImageRep(data: data)
            var item = ClipItem(kind: .image,
                                contentHash: ClipItem.hash(data),
                                pixelWidth: rep?.pixelsWide,
                                pixelHeight: rep?.pixelsHigh,
                                byteSize: data.count)
            item.appBundleID = Self.sourceBundleID
            item.appName = "Screenshot"
            store.insert(item, imageData: data)
        }
    }

    private func imageFilenames(in directory: URL) -> [String] {
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    private func pngData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() == "png" { return data }
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
