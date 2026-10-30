import AppKit

/// Process entry point.
///
/// Top-level code in a `main.swift` runs in a nonisolated context, which cannot
/// construct the main-actor-isolated `AppDelegate`. A `@MainActor` `@main` type
/// gets the isolation right.
@main
@MainActor
enum Clipstack {
    /// `NSApplication.delegate` is a weak reference, so the delegate has to be
    /// owned from somewhere that outlives `main()`.
    private static var delegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        // Menu bar only: no Dock icon, no main window.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
