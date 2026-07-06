// Draws the app icon natively (CoreGraphics, no deps) and builds AppIcon.icns.
// Usage: swift icon.swift  → writes AppIcon-1024.png + AppIcon.icns in repo root.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let S = 1024.0, margin = 100.0, tile = S - 2 * margin, radius = 185.0
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // top-left origin

func rgba(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 0xff) / 255,
                                         CGFloat((h >> 8) & 0xff) / 255,
                                         CGFloat(h & 0xff) / 255, a])!
}

// Tile: Big Sur rounded rect (plain corners as the standard squircle approximation)
let tileRect = CGRect(x: margin, y: margin, width: tile, height: tile)
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgba(0x2B3137), rgba(0x14171A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: margin), end: CGPoint(x: 0, y: margin + tile), options: [])
let hi = CGGradient(colorsSpace: cs, colors: [rgba(0xFFFFFF, 0.08), rgba(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(hi, start: CGPoint(x: 0, y: margin), end: CGPoint(x: 0, y: margin + tile * 0.18), options: [])
ctx.restoreGState()

// Markdown "M↓" glyph — vertices from the official logo path (208x128 viewBox),
// scaled so glyph width (x 30–185) = 55% of tile, centered.
let mPts: [(Double, Double)] = [(30, 98), (30, 30), (50, 30), (70, 55), (90, 30), (110, 30),
                                (110, 98), (90, 98), (90, 59), (70, 84), (50, 59), (50, 98)]
let aPts: [(Double, Double)] = [(155, 98), (125, 65), (145, 65), (145, 30), (165, 30), (165, 65), (185, 65)]
let s = 0.55 * tile / 155.0
let ox = S / 2 - s * (30 + 185) / 2, oy = S / 2 - s * (30 + 98) / 2
func fill(_ pts: [(Double, Double)]) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: ox + s * pts[0].0, y: oy + s * pts[0].1))
    for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: ox + s * p.0, y: oy + s * p.1)) }
    ctx.closePath(); ctx.fillPath()
}
ctx.setFillColor(rgba(0xFFFFFF, 0.95))
fill(mPts); fill(aPts)

// Write 1024 master
let master = root.appendingPathComponent("AppIcon-1024.png")
let dest = CGImageDestinationCreateWithURL(master as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "PNG write failed")

// iconset -> icns (intermediates in temp, only the .icns lands in the repo)
func run(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = args
    try! p.run(); p.waitUntilExit()
    precondition(p.terminationStatus == 0, "failed: \(args.joined(separator: " "))")
}
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    run(["sips", "-z", "\(px)", "\(px)", master.path,
         "--out", iconset.appendingPathComponent("icon_\(name).png").path])
}
run(["iconutil", "-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path])
try? FileManager.default.removeItem(at: iconset)
print("wrote AppIcon-1024.png + AppIcon.icns")
