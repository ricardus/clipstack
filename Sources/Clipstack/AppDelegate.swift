import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var state: AppState!
    private var monitor: ClipboardMonitor!
    private var screenshots: ScreenshotWatcher!
    private var panelController: PanelController!
    private var toast: CaptureToast!
    private var hotKey: HotKey?
    private var shortcutRecorder: ShortcutRecorder!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipStore()
        state = AppState(store: store)
        monitor = ClipboardMonitor(store: store)
        screenshots = ScreenshotWatcher(store: store)
        panelController = PanelController(state: state, store: store, monitor: monitor)
        toast = CaptureToast()

        monitor.start()
        if Preferences.shared.watchScreenshots { screenshots.start() }

        armHotKey()
        setUpShortcutRecorder()

        setUpStatusItem()

        // Wired after the status item exists: the toast anchors to its frame.
        store.onCapture = { [weak self] item in
            guard let self else { return }
            self.toast.show(item, under: self.statusItem)
        }

        // Ask once at launch so the first paste actually works.
        _ = Paster.hasAccessibilityPermission(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        screenshots.stop()
        store.flush()
    }

    // MARK: - Hotkey

    /// Registers the saved shortcut. On failure the menu says so and offers to
    /// change it; the menu bar item keeps working meanwhile.
    private func armHotKey() {
        let shortcut = Preferences.shared.shortcut
        hotKey = nil
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.panelController.toggle()
        }
        if hotKey == nil {
            NSLog("Clipstack: could not register \(shortcut.displayString), another app already owns it")
        }
    }

    private func setUpShortcutRecorder() {
        shortcutRecorder = ShortcutRecorder()
        // Suspended while recording, or pressing the current combination would
        // toggle the panel instead of reaching the recorder.
        shortcutRecorder.onBegin = { [weak self] in self?.hotKey = nil }
        shortcutRecorder.onRecord = { shortcut in
            // A trial registration: if Carbon accepts it, it is free. Dropped at
            // once and armed for real when the recorder closes.
            guard HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, action: {}) != nil else {
                return false
            }
            Preferences.shared.shortcut = shortcut
            return true
        }
        shortcutRecorder.onEnd = { [weak self] in self?.armHotKey() }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusItemIcon.make()
        statusItem.button?.setAccessibilityLabel("Clipstack")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let show = NSMenuItem(title: "Show History",
                              action: #selector(showPanel),
                              keyEquivalent: "")
        show.target = self
        show.tag = 3
        menu.addItem(show)

        let shortcutItem = NSMenuItem(title: "Change Shortcut…",
                                      action: #selector(changeShortcut),
                                      keyEquivalent: "")
        shortcutItem.target = self
        shortcutItem.tag = 4
        menu.addItem(shortcutItem)

        menu.addItem(.separator())

        let screenshotsItem = NSMenuItem(title: "Capture Screenshots",
                                         action: #selector(toggleScreenshots),
                                         keyEquivalent: "")
        screenshotsItem.target = self
        screenshotsItem.tag = 1
        menu.addItem(screenshotsItem)

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = 2
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History (keep pinned)",
                               action: #selector(clearHistory),
                               keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let reveal = NSMenuItem(title: "Reveal Data Folder",
                                action: #selector(revealDataFolder),
                                keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clipstack",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func changeShortcut() {
        shortcutRecorder.show(current: Preferences.shared.shortcut)
    }

    @objc private func toggleScreenshots() {
        let enabled = !Preferences.shared.watchScreenshots
        Preferences.shared.watchScreenshots = enabled
        if enabled { screenshots.start() } else { screenshots.stop() }
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = !Preferences.shared.launchAtLogin
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Preferences.shared.launchAtLogin = enabled
        } catch {
            NSLog("Clipstack: launch at login failed: \(error.localizedDescription)")
        }
    }

    @objc private func clearHistory() {
        store.clear(keepPinned: true)
    }

    @objc private func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ClipStore.baseURL])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = Preferences.shared.watchScreenshots ? .on : .off
        menu.item(withTag: 2)?.state = Preferences.shared.launchAtLogin ? .on : .off

        // The key equivalent only labels the item; the hotkey does the work.
        let shortcut = Preferences.shared.shortcut
        if let show = menu.item(withTag: 3) {
            show.keyEquivalent = hotKey == nil ? "" : shortcut.menuKeyEquivalent
            show.keyEquivalentModifierMask = shortcut.modifierFlags
        }
        menu.item(withTag: 4)?.title = hotKey == nil
            ? "\(shortcut.displayString) Is Taken, Change Shortcut…"
            : "Change Shortcut…"
    }
}
