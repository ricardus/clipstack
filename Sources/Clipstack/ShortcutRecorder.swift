import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Small window that records the next key combination as the global shortcut.
///
/// The owner suspends the live hotkey while this is open, otherwise Carbon
/// would swallow the current combination before the window ever saw it.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    /// Called when the window opens, so the owner can suspend its hotkey.
    var onBegin: (() -> Void)?
    /// Asked to adopt a shortcut; returns false when macOS refuses it.
    var onRecord: ((Shortcut) -> Bool)?
    /// Called when the window closes, so the owner can re-arm its hotkey.
    var onEnd: (() -> Void)?

    private let model = RecorderModel()
    private var window: NSPanel?
    private var keyMonitor: Any?
    private var closeWork: DispatchWorkItem?

    func show(current: Shortcut) {
        model.current = current
        model.message = .prompt
        let window = self.window ?? makeWindow()
        self.window = window
        onBegin?()
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Clipstack Shortcut"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShortcutRecorderView(
            model: model,
            onReset: { [weak self] in self?.record(.default) },
            onDone: { [weak self] in self?.window?.close() }
        ))
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Int(event.keyCode) == kVK_Escape, flags.isDisjoint(with: [.command, .option, .control, .shift]) {
                window.close()
                return nil
            }
            guard let shortcut = Shortcut(event: event) else {
                self.model.message = .needsModifier
                return nil
            }
            self.record(shortcut)
            return nil
        }
    }

    private func record(_ shortcut: Shortcut) {
        closeWork?.cancel()
        guard onRecord?(shortcut) == true else {
            model.message = .taken(shortcut.displayString)
            return
        }
        model.current = shortcut
        model.message = .saved
        // Long enough to read the confirmation, short enough not to linger.
        let work = DispatchWorkItem { [weak self] in self?.window?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func windowWillClose(_ notification: Notification) {
        closeWork?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onEnd?()
    }
}

@MainActor
final class RecorderModel: ObservableObject {
    enum Message: Equatable {
        case prompt, needsModifier, saved
        case taken(String)
    }

    @Published var current: Shortcut = .default
    @Published var message: Message = .prompt
}

@MainActor
struct ShortcutRecorderView: View {
    @ObservedObject var model: RecorderModel
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(model.current.displayString)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.9), lineWidth: 1.5)
                )

            Text(messageText)
                .font(.system(size: 12))
                .foregroundStyle(messageColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)

            HStack {
                Button("Reset to \(Shortcut.default.displayString)", action: onReset)
                    .disabled(model.current == .default)
                Spacer()
                Button("Done", action: onDone)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var messageText: String {
        switch model.message {
        case .prompt: return "Press the new shortcut. Esc cancels."
        case .needsModifier: return "Include ⌘, ⌥ or ⌃, so normal typing keeps working."
        case .saved: return "Saved."
        case .taken(let combo): return "\(combo) is already registered by another app. Try another."
        }
    }

    private var messageColor: Color {
        switch model.message {
        case .prompt, .needsModifier: return .secondary
        case .saved: return Theme.accent
        case .taken: return .red
        }
    }
}
