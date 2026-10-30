import AppKit
import Carbon.HIToolbox
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

        // Cmd+Shift+V. Carbon modifier masks, not NSEvent ones.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.panelController.toggle()
        }
        if hotKey == nil {
            NSLog("Clipstack: could not register Cmd+Shift+V, another app already owns it")
        }

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
                              keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.command, .shift]
        show.target = self
        menu.addItem(show)

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
    }
}
