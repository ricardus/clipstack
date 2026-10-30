import AppKit
import SwiftUI

/// The pill that appears under the status item when something is captured.
///
/// Borderless, non-activating and mouse-transparent: it is pure feedback, so it
/// must never take focus or interrupt what you were doing. Anchored to the
/// status item's own window so it lands under the icon wherever the icon ends up.
@MainActor
final class CaptureToast {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private let visible: Duration = .milliseconds(1200)
    private let fade = 0.15
    /// Vertical travel of the slide-in, and the gap below the menu bar.
    private let rise: CGFloat = 6

    func show(_ item: ClipItem, under statusItem: NSStatusItem) {
        guard let barFrame = statusItem.button?.window?.frame else { return }

        let hosting = NSHostingView(rootView: CaptureToastView(text: Self.label(for: item),
                                                               symbol: item.kind.symbol))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(size)

        let resting = NSPoint(x: barFrame.midX - size.width / 2,
                              y: barFrame.minY - rise - size.height)

        // A second capture while one is showing replaces the content in place
        // rather than animating from scratch.
        if panel.isVisible {
            panel.setFrameOrigin(resting)
        } else {
            panel.setFrameOrigin(NSPoint(x: resting.x, y: resting.y + rise))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            // setFrame is the animatable one on NSWindow; setFrameOrigin is not.
            let restingFrame = NSRect(origin: resting, size: size)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fade
                panel.animator().alphaValue = 1
                panel.animator().setFrame(restingFrame, display: false)
            }
        }

        let duration = visible
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        let lifted = panel.frame.offsetBy(dx: 0, dy: rise)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade
            panel.animator().alphaValue = 0
            panel.animator().setFrame(lifted, display: false)
        }, completionHandler: {
            Task { @MainActor [weak self] in
                // A new toast may have appeared during the fade; leave it alone.
                guard let panel = self?.panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// One short line per content type. The point is to confirm that something
    /// landed, not to reproduce it.
    static func label(for item: ClipItem) -> String {
        switch item.kind {
        case .text:
            return "Text copied"
        case .link:
            return "Link copied"
        case .color:
            return item.text ?? "Colour copied"
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight {
                return "Image \(width) \u{00D7} \(height)"
            }
            return "Image copied"
        case .file:
            let count = (item.text ?? "").split(separator: "\n").count
            return count == 1 ? "1 file" : "\(count) files"
        }
    }
}

private struct CaptureToastView: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
