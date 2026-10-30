import AppKit
import Carbon.HIToolbox

/// Writes an item back to the pasteboard and synthesises Cmd+V into whatever
/// app was frontmost before the panel opened.
///
/// Posting the keystroke needs Accessibility permission; without it the item is
/// still copied, the user just has to paste manually.
@MainActor
enum Paster {
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Puts the item on the general pasteboard and returns its content hash so
    /// the monitor can ignore the write.
    @discardableResult
    static func copyToPasteboard(_ item: ClipItem, store: ClipStore) -> String {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text, .link:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .color:
            let hex = item.text ?? ""
            if let color = NSColor(hexString: hex) {
                pasteboard.writeObjects([color])
            }
            pasteboard.setString(hex, forType: .string)
        case .file:
            let urls = (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
        case .image:
            if let url = store.blobURL(for: item), let data = try? Data(contentsOf: url) {
                pasteboard.setData(data, forType: .png)
            }
        }

        return item.contentHash
    }

    /// Restores focus to `target` and sends Cmd+V.
    static func pasteInto(_ target: NSRunningApplication?) {
        target?.activate()

        Task { @MainActor in
            // Let the target app take focus before the keystroke lands.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard hasAccessibilityPermission(prompt: false) else { return }
            let source = CGEventSource(stateID: .combinedSessionState)
            let key = CGKeyCode(kVK_ANSI_V)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
