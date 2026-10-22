// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

/// Shift Happens: a Shift keycap that has just toppled over. `pixels` is the output size;
/// below 64 px the motion lines are left out so the icon stays readable.
func drawIcon(in ctx: CGContext, pixels: Int) {
    // macOS icon grid: 824×824 tile centered on the 1024 canvas, with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [
        NSColor(srgbRed: 1.00, green: 0.72, blue: 0.36, alpha: 1).cgColor,
        NSColor(srgbRed: 0.96, green: 0.36, blue: 0.38, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // The "floor" the key fell onto: a soft contact shadow.
    ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
    ctx.fillEllipse(in: CGRect(x: 300, y: 205, width: 470, height: 70))

    if pixels >= 64 { drawMotionLines(in: ctx) }
    ctx.restoreGState()

    // The keycap, tipped over to the right around its bottom-right corner.
    ctx.saveGState()
    ctx.translateBy(x: 560, y: 520)
    ctx.rotate(by: -23 * .pi / 180)
    drawKeycap(in: ctx, rect: CGRect(x: -230, y: -230, width: 460, height: 460))
    ctx.restoreGState()
}

func drawMotionLines(in ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
    ctx.setLineCap(.round)
    // Arcs trailing behind the top-left corner, as if it swung down from upright.
    let center = CGPoint(x: 700, y: 300)
    for (radius, width, from, to) in [(560.0, 22.0, 128.0, 146.0), (500.0, 18.0, 133.0, 148.0), (620.0, 16.0, 125.0, 138.0)] {
        ctx.setLineWidth(width)
        ctx.addArc(center: center, radius: radius, startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func drawKeycap(in ctx: CGContext, rect: CGRect) {
    let base = CGPath(roundedRect: rect, cornerWidth: 80, cornerHeight: 80, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(base)
    ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Top face, slightly inset and raised, like a real keycap.
    let top = rect.insetBy(dx: 30, dy: 30).offsetBy(dx: 0, dy: 16)
    let topPath = CGPath(roundedRect: top, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.saveGState()
    ctx.addPath(topPath)
    ctx.clip()
    let face = CGGradient(colorsSpace: nil, colors: [
        NSColor.white.cgColor,
        NSColor(white: 0.91, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 0, y: top.maxY), end: CGPoint(x: 0, y: top.minY), options: [])
    ctx.restoreGState()

    // The ⇧ glyph, drawn as a path so it looks the same everywhere.
    let w = top.width * 0.52, h = top.height * 0.58
    let x = top.midX - w / 2, y = top.midY - h / 2
    let stem = w * 0.42
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: top.midX, y: y + h))
    arrow.addLine(to: CGPoint(x: x + w, y: y + h * 0.48))
    arrow.addLine(to: CGPoint(x: top.midX + stem / 2, y: y + h * 0.48))
    arrow.addLine(to: CGPoint(x: top.midX + stem / 2, y: y))
    arrow.addLine(to: CGPoint(x: top.midX - stem / 2, y: y))
    arrow.addLine(to: CGPoint(x: top.midX - stem / 2, y: y + h * 0.48))
    arrow.addLine(to: CGPoint(x: x, y: y + h * 0.48))
    arrow.closeSubpath()
    ctx.saveGState()
    ctx.addPath(arrow)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(top.width * 0.075)
    ctx.setStrokeColor(NSColor(srgbRed: 0.78, green: 0.27, blue: 0.24, alpha: 1).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx, pixels: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.copyItem(at: iconset.appendingPathComponent("icon_512x512@2x.png"), to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-preview.png"))
print(iconutil.terminationStatus == 0 ? "Done: Resources/AppIcon.icns" : "iconutil failed")
exit(iconutil.terminationStatus)
