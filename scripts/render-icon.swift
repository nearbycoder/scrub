// Renders Scrub's app icon artwork. Usage: swift scripts/render-icon.swift <output-dir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func sparkle(center: CGPoint, radius: CGFloat, waist: CGFloat = 0.22) -> CGPath {
    let p = CGMutablePath()
    let points = 4
    for i in 0..<(points * 2) {
        let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
        let r = i % 2 == 0 ? radius : radius * waist
        let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 { p.move(to: pt) } else {
            // Curved edges give the sparkle a soft, modern look.
            let prevAngle = CGFloat(i - 1) * .pi / CGFloat(points) - .pi / 2
            let mid = (angle + prevAngle) / 2
            let ctrl = CGPoint(x: center.x + cos(mid) * radius * waist * 0.9, y: center.y + sin(mid) * radius * waist * 0.9)
            p.addQuadCurve(to: pt, control: ctrl)
        }
    }
    let first = CGPoint(x: center.x, y: center.y - radius)
    let lastAngle = CGFloat(points * 2 - 1) * .pi / CGFloat(points) - .pi / 2
    let mid = (lastAngle + 3 * .pi / 2) / 2
    p.addQuadCurve(to: first, control: CGPoint(x: center.x + cos(mid) * radius * waist * 0.9, y: center.y + sin(mid) * radius * waist * 0.9))
    p.closeSubpath()
    return p
}

/// Draws the white glyph: three bubbles and a sparkle. Coordinates are top-left origin.
func drawGlyph(_ ctx: CGContext, opaque: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let bubbles: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 440, y: 590), 205),
        (CGPoint(x: 690, y: 400), 118),
        (CGPoint(x: 705, y: 690), 62),
    ]
    for (c, r) in bubbles {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        // Body
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        let body = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            color(1, 1, 1, opaque ? 0.98 : 1), color(1, 1, 1, opaque ? 0.78 : 0.92),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(body, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        ctx.restoreGState()
        // Highlight crescent
        if opaque {
            ctx.saveGState()
            let hl = CGMutablePath()
            hl.addArc(center: c, radius: r * 0.72, startAngle: .pi * 1.05, endAngle: .pi * 1.45, clockwise: false)
            ctx.addPath(hl)
            ctx.setLineCap(.round)
            ctx.setLineWidth(r * 0.12)
            ctx.setStrokeColor(color(0.55, 0.85, 0.95, 0.55))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
    // Sparkle
    ctx.addPath(sparkle(center: CGPoint(x: 300, y: 290), radius: 120))
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.addPath(sparkle(center: CGPoint(x: 800, y: 205), radius: 52))
    ctx.fillPath()
    ctx.restoreGState()
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
}

// 1. Transparent glyph for the Icon Composer foreground layer.
let glyph = makeContext()
drawGlyph(glyph, opaque: false)
save(glyph, "glyph.png")

// 2. Full-bleed classic icon following the macOS grid (824pt squircle inside 1024 canvas).
let full = makeContext()
let inset: CGFloat = 100
let squircle = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: squircle, cornerWidth: 185, cornerHeight: 185, transform: nil)
full.saveGState()
full.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
full.addPath(path)
full.setFillColor(color(0.2, 0.4, 0.9))
full.fillPath()
full.restoreGState()
full.saveGState()
full.addPath(path)
full.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
    color(0.16, 0.86, 0.82), color(0.20, 0.55, 0.98), color(0.45, 0.33, 0.96),
] as CFArray, locations: [0, 0.55, 1])!
full.drawLinearGradient(bg, start: CGPoint(x: squircle.minX, y: squircle.maxY), end: CGPoint(x: squircle.maxX, y: squircle.minY), options: [])
// Soft top glow
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(1, 1, 1, 0.35), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
full.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 860), startRadius: 0, endCenter: CGPoint(x: 380, y: 860), endRadius: 560, options: [])
// Glyph, scaled into the squircle with a soft shadow.
full.saveGState()
full.translateBy(x: size / 2, y: size / 2)
full.scaleBy(x: 0.78, y: 0.78)
full.translateBy(x: -size / 2, y: -size / 2)
full.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0.05, 0.1, 0.4, 0.35))
drawGlyph(full, opaque: true)
full.restoreGState()
// Rim light
full.addPath(path)
full.setLineWidth(6)
full.setStrokeColor(color(1, 1, 1, 0.28))
full.strokePath()
full.restoreGState()
save(full, "icon-1024.png")
print("ok")
