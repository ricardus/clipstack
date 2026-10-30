import SwiftUI

/// Brand colours, mirroring the design canvas.
///
/// The panel used `Color.accentColor` (the system accent, blue by default)
/// before the mark existed. Point this back at `.accentColor` to undo that.
enum Theme {
    /// oklch(0.72 0.115 195), the accent from the Clipstack mark.
    static let accent = Color(.sRGB, red: 41.0 / 255.0, green: 187.0 / 255.0, blue: 187.0 / 255.0, opacity: 1)
}
