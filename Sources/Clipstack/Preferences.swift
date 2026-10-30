import Foundation

/// Thin UserDefaults wrapper. Everything here is a personal setting; there is
/// no sync and no remote state.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let historyLimit = "historyLimit"
        static let watchScreenshots = "watchScreenshots"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let launchAtLogin = "launchAtLogin"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }

    /// Apps whose clipboard writes are never recorded. Password managers first:
    /// a clipboard history that stores secrets is a liability, not a feature.
    static let defaultExcludedBundleIDs = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "in.sinew.Enpass-Desktop",
        "com.apple.Passwords"
    ]

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: 500,
            Key.watchScreenshots: true,
            Key.excludedBundleIDs: Self.defaultExcludedBundleIDs,
            Key.launchAtLogin: false,
            Key.hotKeyCode: Int(Shortcut.default.keyCode),
            Key.hotKeyModifiers: Int(Shortcut.default.modifiers)
        ])
    }

    var historyLimit: Int {
        get { max(50, defaults.integer(forKey: Key.historyLimit)) }
        set { defaults.set(newValue, forKey: Key.historyLimit) }
    }

    var watchScreenshots: Bool {
        get { defaults.bool(forKey: Key.watchScreenshots) }
        set { defaults.set(newValue, forKey: Key.watchScreenshots) }
    }

    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.excludedBundleIDs) ?? Self.defaultExcludedBundleIDs }
        set { defaults.set(newValue, forKey: Key.excludedBundleIDs) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// The global shortcut that opens the history panel.
    var shortcut: Shortcut {
        get {
            Shortcut(keyCode: UInt32(defaults.integer(forKey: Key.hotKeyCode)),
                     modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers)))
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.modifiers), forKey: Key.hotKeyModifiers)
        }
    }
}
