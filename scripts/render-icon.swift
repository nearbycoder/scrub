// Renders the layers of Scrub's Liquid Glass app icon (Scrub/Resources/AppIcon.icon).
// The icon is a single glass bubble with a gleam: macOS adds the glass, highlights and shadows.
// Usage: swift scripts/render-icon.swift <AppIcon.icon/Assets>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024
let center = CGPoint(x: 512, y: 512), radius: CGFloat = 330

func layer(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    draw(ctx)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: out + "/" + name))
}

/// A four-point star with concave sides.
func sparkle(_ c: CGPoint, _ r: CGFloat, pinch: CGFloat = 0.13) -> CGPath {
    let p = CGMutablePath()
    let tips = (0..<4).map { i -> CGPoint in
        let a = CGFloat(i) * .pi / 2 - .pi / 2
        return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }
    p.move(to: tips[0])
    for i in 0..<4 {
        let next = tips[(i + 1) % 4]
        p.addCurve(to: next,
                   control1: CGPoint(x: c.x + (tips[i].x - c.x) * pinch, y: c.y + (tips[i].y - c.y) * pinch),
                   control2: CGPoint(x: c.x + (next.x - c.x) * pinch, y: c.y + (next.y - c.y) * pinch))
    }
    p.closeSubpath()
    return p
}

layer("bubble.png") { ctx in
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

layer("gleam.png") { ctx in
    ctx.addPath(sparkle(CGPoint(x: 548, y: 548), 170))
    ctx.fillPath()
    // Rim highlight along the upper left of the bubble.
    ctx.setLineWidth(44)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: radius - 78, startAngle: .pi * 1.04, endAngle: .pi * 1.36, clockwise: false)
    ctx.strokePath()
}
print("ok")
