import AppKit

/// The menu bar mark, drawn at runtime instead of shipped as a PNG so it stays
/// crisp on any scale factor and needs no bundle lookup.
///
/// Deliberately not isolated to the main actor: it reads nothing and touches no
/// shared state, so it can be called from anywhere.
enum StatusItemIcon {
    /// Cards in the design grid (y measured from the top), with the alpha tiers
    /// the template uses in place of colour.
    private static let cards: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, alpha: CGFloat)] = [
        (7, 2.6, 10, 2.6, 1.3, 0.42),
        (5, 6.2, 14, 2.8, 1.4, 0.70),
        (3, 9.8, 18, 11.6, 2.6, 1.00),
    ]

    /// A template image: macOS recolours it for the current theme and inverts it
    /// while the menu is open, so it must carry shape in alpha and nothing else.
    static func make(size: CGFloat = 17) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, box: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(in ctx: CGContext, box: CGRect) {
        let scale = min(box.width, box.height) / 24
        for card in cards {
            // The design grid measures y from the top, Core Graphics from the bottom.
            let rect = CGRect(x: box.minX + card.x * scale,
                              y: box.minY + (24 - card.y - card.h) * scale,
                              width: card.w * scale,
                              height: card.h * scale)
            ctx.setFillColor(CGColor(gray: 0, alpha: card.alpha))
            ctx.addPath(CGPath(roundedRect: rect,
                               cornerWidth: card.r * scale,
                               cornerHeight: card.r * scale,
                               transform: nil))
            ctx.fillPath()
        }
    }
}
