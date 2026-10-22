// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
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
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1).cgColor,
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // Two keycaps with a swap arrow between them.
    drawKeycap(in: ctx, rect: CGRect(x: 196, y: 456, width: 300, height: 300), glyph: "⌥")
    drawKeycap(in: ctx, rect: CGRect(x: 528, y: 268, width: 300, height: 300), glyph: "⌘")
    drawSwapArrow(in: ctx)
}

func drawKeycap(in ctx: CGContext, rect: CGRect, glyph: String) {
    let base = CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(base)
    ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Top face, slightly inset and raised, like a real keycap.
    let top = rect.insetBy(dx: 22, dy: 22).offsetBy(dx: 0, dy: 12)
    let topPath = CGPath(roundedRect: top, cornerWidth: 40, cornerHeight: 40, transform: nil)
    ctx.saveGState()
    ctx.addPath(topPath)
    ctx.clip()
    let face = CGGradient(colorsSpace: nil, colors: [
        NSColor.white.cgColor,
        NSColor(white: 0.92, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 0, y: top.maxY), end: CGPoint(x: 0, y: top.minY), options: [])
    ctx.restoreGState()

    let font = NSFont.systemFont(ofSize: 150, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.18, green: 0.22, blue: 0.55, alpha: 1),
    ]
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let size = text.size()
    text.draw(at: CGPoint(x: top.midX - size.width / 2, y: top.midY - size.height / 2))
}

func drawSwapArrow(in ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)

    // Arc from the lower-left area to the right keycap.
    let start = CGPoint(x: 300, y: 400)
    let end = CGPoint(x: 490, y: 300)
    ctx.move(to: start)
    ctx.addQuadCurve(to: end, control: CGPoint(x: 300, y: 300))
    ctx.strokePath()

    // Arrowhead pointing right.
    ctx.move(to: CGPoint(x: end.x + 34, y: end.y))
    ctx.addLine(to: CGPoint(x: end.x - 22, y: end.y + 40))
    ctx.addLine(to: CGPoint(x: end.x - 22, y: end.y - 40))
    ctx.closePath()
    ctx.fillPath()
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
    drawIcon(in: ctx)
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
