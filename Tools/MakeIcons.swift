// Renders the Clipstack app icon into an .iconset directory.
//
// Run from the project root:   swift Tools/MakeIcons.swift [out-dir]
// build.sh calls it and then hands the iconset to iconutil.
//
// Core Graphics only, no AppKit: this is a build-time script, so it has no
// business touching the main actor. Geometry mirrors the design canvas, which
// draws the mark on a 24x24 grid.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Tokens

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let tileStops = [srgb(0x2A2F36), srgb(0x14181D), srgb(0x0B0E11)]
let tileLocations: [CGFloat] = [0.0, 0.54, 1.0]
let accent = srgb(0x29BBBB)          // oklch(0.72 0.115 195)
let ink: UInt32 = 0xE6E8EA

/// The three cards, in the design grid (y measured from the top).
let cards: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, fill: CGColor)] = [
    (7, 2.6, 10, 2.6, 1.3, srgb(ink, 0.30)),
    (5, 6.2, 14, 2.8, 1.4, srgb(ink, 0.55)),
    (3, 9.8, 18, 11.6, 2.6, accent),
]

// MARK: - Shapes

/// Apple-style squircle: a superellipse, not a rounded rectangle. Sampled
/// densely enough that the seam is invisible even at 1024 px.
func squircle(in rect: CGRect, exponent: CGFloat = 5, samples: Int = 1024) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0..<samples {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * pow(abs(ct), 2 / exponent) * (ct < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(st), 2 / exponent) * (st < 0 ? -1 : 1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawMark(in ctx: CGContext, box: CGRect) {
    let s = min(box.width, box.height) / 24
    for card in cards {
        let rect = CGRect(x: box.minX + card.x * s,
                          y: box.minY + (24 - card.y - card.h) * s,
                          width: card.w * s,
                          height: card.h * s)
        ctx.setFillColor(card.fill)
        ctx.addPath(CGPath(roundedRect: rect,
                           cornerWidth: card.r * s,
                           cornerHeight: card.r * s,
                           transform: nil))
        ctx.fillPath()
    }
}

// MARK: - Rendering

func renderIcon(side: Int) -> CGImage? {
    let size = CGFloat(side)
    guard let ctx = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // The macOS icon grid leaves a margin around the tile for the shadow.
    let inset = size * 0.098
    let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = squircle(in: tile)

    // Drop shadow, skipped at the small sizes where it only muddies the edge.
    if side >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.045,
                      color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(srgb(0x0B0E11))
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Tile gradient.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 colors: tileStops as CFArray,
                                 locations: tileLocations) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: tile.minX + tile.width * 0.18, y: tile.maxY),
                               end: CGPoint(x: tile.maxX, y: tile.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    // Hairline top highlight, the inset white stroke from the design.
    if side >= 64 {
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
        ctx.setLineWidth(max(1, size * 0.004))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // The mark, at 58% of the tile.
    let markSide = tile.width * 0.58
    drawMark(in: ctx, box: CGRect(x: tile.midX - markSide / 2,
                                  y: tile.midY - markSide / 2,
                                  width: markSide,
                                  height: markSide))

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "MakeIcons", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "MakeIcons", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

// MARK: - Main

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist")
let iconset = outDir.appendingPathComponent("Clipstack.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The names Apple's iconutil expects.
let variants: [(name: String, side: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let image = renderIcon(side: variant.side) else {
        FileHandle.standardError.write("MakeIcons: failed to render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try write(image, to: iconset.appendingPathComponent("\(variant.name).png"))
}

print("MakeIcons: wrote \(variants.count) images to \(iconset.path)")
