// Renders the DiscScanner app icon as a 1024x1024 PNG.
// Usage: swift scripts/render-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Background: rounded rect with vertical gradient (macOS icon grid inset).
let content = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = CGPath(roundedRect: content, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(0x2A3242), rgb(0x11151D)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: content.midX, y: content.maxY),
    end: CGPoint(x: content.midX, y: content.minY),
    options: []
)

// Treemap mosaic (relative layout inside the content area).
let mosaic = content.insetBy(dx: 78, dy: 78)
let gap: CGFloat = 14
func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
    let rect = CGRect(
        x: mosaic.minX + x * mosaic.width + gap / 2,
        y: mosaic.minY + (1 - y - h) * mosaic.height + gap / 2,
        width: w * mosaic.width - gap,
        height: h * mosaic.height - gap
    )
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
}
// y measured from the top, sizes as fractions of the mosaic square.
tile(0.00, 0.00, 0.58, 0.62, rgb(0x3B82F6))          // large blue block
tile(0.58, 0.00, 0.42, 0.38, rgb(0x0EA5E9))          // sky
tile(0.58, 0.38, 0.42, 0.24, rgb(0x14B8A6))          // teal
tile(0.00, 0.62, 0.34, 0.38, rgb(0x22D3EE))          // cyan
tile(0.34, 0.62, 0.36, 0.38, rgb(0x2563EB))          // deep blue
tile(0.70, 0.62, 0.30, 0.20, rgb(0x64748B))          // slate
tile(0.70, 0.82, 0.30, 0.18, rgb(0x94A3B8))          // light slate
ctx.restoreGState()

// Magnifying glass overlay with soft shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x000000, 0.55))
let lensCenter = CGPoint(x: 560, y: 560)
let lensRadius: CGFloat = 168
ctx.setStrokeColor(rgb(0xF8FAFC))
ctx.setLineWidth(40)
ctx.strokeEllipse(in: CGRect(
    x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
    width: lensRadius * 2, height: lensRadius * 2
))
ctx.setLineCap(.round)
ctx.setLineWidth(52)
let handleStart = CGPoint(x: lensCenter.x + lensRadius * 0.72, y: lensCenter.y - lensRadius * 0.72)
ctx.move(to: handleStart)
ctx.addLine(to: CGPoint(x: handleStart.x + 150, y: handleStart.y - 150))
ctx.strokePath()
ctx.restoreGState()

// Subtle glass tint inside the lens.
ctx.setFillColor(rgb(0xFFFFFF, 0.10))
ctx.fillEllipse(in: CGRect(
    x: lensCenter.x - lensRadius + 20, y: lensCenter.y - lensRadius + 20,
    width: (lensRadius - 20) * 2, height: (lensRadius - 20) * 2
))

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
