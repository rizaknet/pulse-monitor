// Renders Pulse's app icon (1024×1024 PNG, transparent corners) with CoreGraphics.
// Usage: swiftc scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon Resources/AppIcon-1024.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Apple's macOS icon grid: 824pt squircle centred in a 1024 canvas, corner radius ≈ 185.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.28))
ctx.addPath(squircle); ctx.setFillColor(rgb(0x2A5BD7)); ctx.fillPath()
ctx.restoreGState()

// Background gradient: bright blue (top) → deep indigo (bottom).
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x46A3FF), rgb(0x3D6CF0), rgb(0x5B3FD9)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

// Soft top highlight.
let hl = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40), options: [])

// Faint activity bars along the bottom (a nod to the in-app sparklines).
let barCount = 15
let barW: CGFloat = 26, gap: CGFloat = (body.width - 120 - barW * CGFloat(barCount)) / CGFloat(barCount - 1)
let heights: [CGFloat] = [60, 90, 70, 120, 95, 150, 110, 80, 130, 100, 160, 120, 90, 110, 70]
for i in 0..<barCount {
    let x = body.minX + 60 + CGFloat(i) * (barW + gap)
    let r = CGRect(x: x, y: body.minY + 70, width: barW, height: heights[i])
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
}
ctx.setFillColor(rgb(0xFFFFFF, 0.16)); ctx.fillPath()

// The pulse line.
let midY = body.midY + 40
let pts: [CGPoint] = [
    CGPoint(x: body.minX + 70, y: midY),
    CGPoint(x: body.minX + 230, y: midY),
    CGPoint(x: body.minX + 285, y: midY + 55),
    CGPoint(x: body.minX + 335, y: midY),
    CGPoint(x: body.minX + 375, y: midY),
    CGPoint(x: body.minX + 430, y: midY + 230),
    CGPoint(x: body.minX + 500, y: midY - 210),
    CGPoint(x: body.minX + 560, y: midY + 60),
    CGPoint(x: body.minX + 600, y: midY),
    CGPoint(x: body.minX + 650, y: midY),
    CGPoint(x: body.minX + 690, y: midY + 40),
    CGPoint(x: body.minX + 730, y: midY),
    CGPoint(x: body.maxX - 70, y: midY),
]
let line = CGMutablePath()
line.addLines(between: pts)

// Glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: rgb(0xFFFFFF, 0.75))
ctx.addPath(line)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(46); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.strokePath()
ctx.restoreGState()

// Crisp stroke on top.
ctx.addPath(line)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(42); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.strokePath()

// Live dot at the end of the trace.
let dot = CGRect(x: body.maxX - 70 - 34, y: midY - 34, width: 68, height: 68)
ctx.setFillColor(rgb(0x7CF5C4)); ctx.fillEllipse(in: dot)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(12); ctx.strokeEllipse(in: dot.insetBy(dx: 6, dy: 6))
ctx.restoreGState()

// Thin inner border for definition on light backgrounds.
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(3); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
