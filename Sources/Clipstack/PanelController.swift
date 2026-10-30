import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the floating history window.
///
/// The panel deliberately activates the app: the search field has to receive
/// keystrokes. The app that was frontmost is captured beforehand so pasting can
/// hand focus straight back to it.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let store: ClipStore
    private let monitor: ClipboardMonitor

    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(state: AppState, store: ClipStore, monitor: ClipboardMonitor) {
        self.state = state
        self.store = store
        self.monitor = monitor
        super.init()
    }

    // MARK: - Presentation

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = self.panel ?? makePanel()
        self.panel = panel

        state.reset()
        positionOnActiveScreen(panel)
        installKeyMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let root = HistoryView(state: state) { [weak self] item in
            self?.activate(item)
        }
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    private func positionOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    /// Arrow keys, Return and Escape are handled here so they never reach the
    /// search field.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            switch Int(event.keyCode) {
            case kVK_DownArrow:
                self.state.moveSelection(by: 1)
                return nil
            case kVK_UpArrow:
                self.state.moveSelection(by: -1)
                return nil
            case kVK_LeftArrow where self.arrowsCycleKinds(event):
                self.state.cycleKindFilter(by: -1)
                return nil
            case kVK_RightArrow where self.arrowsCycleKinds(event):
                self.state.cycleKindFilter(by: 1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let item = self.state.selectedItem { self.activate(item) }
                return nil
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_Delete where event.modifierFlags.contains(.command):
                if let item = self.state.selectedItem {
                    self.store.delete(item)
                    self.state.moveSelection(by: 0)
                }
                return nil
            case kVK_ANSI_P where event.modifierFlags.contains(.command):
                if let item = self.state.selectedItem { self.store.togglePin(item) }
                return nil
            default:
                return event
            }
        }
    }

    /// Left and right switch the type filter only while the search field is
    /// empty and no modifier is held; otherwise they move the caret as usual.
    private func arrowsCycleKinds(_ event: NSEvent) -> Bool {
        state.query.isEmpty
            && event.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Actions

    private func activate(_ item: ClipItem) {
        monitor.suppressedHash = Paster.copyToPasteboard(item, store: store)
        hide()
        Paster.pasteInto(previousApp)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

/// Borderless-ish panels refuse key status by default; SwiftUI text fields need it.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
