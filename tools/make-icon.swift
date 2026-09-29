// Generates the app icon (1024×1024 PNG).
// Usage: swift make-icon.swift <output.png>
import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// ---- squircle background -------------------------------------------------
let inset: CGFloat = 92
let rect = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = rect.width * 0.2237
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.36, blue: 0.98, alpha: 1.0), // indigo
    NSColor(calibratedRed: 0.58, green: 0.20, blue: 0.88, alpha: 1.0), // violet
])!
gradient.draw(in: rect, angle: -90)

let shine = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.20),
    NSColor(calibratedWhite: 1, alpha: 0.0),
])!
shine.draw(in: rect, angle: -90)

// ---- wand symbol ---------------------------------------------------------
func symbolImage() -> NSImage? {
    let names = ["wand.and.stars", "wand.and.rays.inverse", "sparkles", "slider.horizontal.3"]
    for n in names {
        if let base = NSImage(systemSymbolName: n, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: rect.width * 0.54, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
            if let img = base.withSymbolConfiguration(cfg) { return img }
        }
    }
    return nil
}

if let symbol = symbolImage() {
    let size = symbol.size
    let targetH = rect.height * 0.58
    let scale = min(1.0, targetH / max(size.height, 1))
    let w = size.width * scale, h = size.height * scale
    let origin = NSPoint(x: (S - w) / 2, y: (S - h) / 2 - S * 0.015)
    symbol.draw(in: NSRect(origin: origin, size: NSSize(width: w, height: h)),
                from: .zero, operation: .sourceOver, fraction: 1.0)
} else {
    FileHandle.standardError.write("warning: no SF Symbol found\n".data(using: .utf8)!)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
