// Renders the installer window background at 1x and 2x.
// Usage: swift scripts/render-dmg-background.swift <output-dir>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let width: CGFloat = 640, height: CGFloat = 400
// Icon centres used by scripts/dmg-settings.py, in top-left coordinates.
let appCenter = CGPoint(x: 170, y: 205), appsCenter = CGPoint(x: 470, y: 205)

func render(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Flip to top-left origin.
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)

    // Mid-tone gradient: Finder labels are black in Light Mode and white in Dark Mode, and both stay legible here.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Matches the app icon's aqua-to-blue gradient, kept mid-tone.
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.10, green: 0.56, blue: 0.80, alpha: 1),
        CGColor(srgbRed: 0.13, green: 0.46, blue: 0.86, alpha: 1),
        CGColor(srgbRed: 0.17, green: 0.38, blue: 0.88, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: width, y: height), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: -40), startRadius: 0, endCenter: CGPoint(x: 320, y: -40), endRadius: 420, options: [])

    // Soft wells behind the two icons.
    for c in [appCenter, appsCenter] {
        let r: CGFloat = 92
        ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - r, y: c.y - r + 6, width: r * 2, height: r * 2 + 18), cornerWidth: 28, cornerHeight: 28, transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.07))
        ctx.fillPath()
    }

    // Arrow from the app to Applications.
    let y = appCenter.y - 6
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.75))
    ctx.setLineWidth(3.5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [1, 10])
    ctx.move(to: CGPoint(x: 272, y: y))
    ctx.addLine(to: CGPoint(x: 356, y: y))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 352, y: y - 11))
    ctx.addLine(to: CGPoint(x: 366, y: y))
    ctx.addLine(to: CGPoint(x: 352, y: y + 11))
    ctx.strokePath()

    // Text is drawn unflipped.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, topY: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(white: 1, alpha: alpha),
            .paragraphStyle: style,
            .shadow: shadow,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let h = str.size().height
        str.draw(in: CGRect(x: 0, y: height - topY - h, width: width, height: h))
    }
    draw("Install Scrub", size: 24, weight: .semibold, alpha: 0.97, topY: 34)
    draw("Drag Scrub into your Applications folder", size: 13, weight: .regular, alpha: 0.82, topY: 68)
    draw("Signed and notarized by Apple  ·  Free and open source", size: 11, weight: .medium, alpha: 0.62, topY: 346)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: out + "/dmg-background.png")
render(scale: 2, to: out + "/dmg-background@2x.png")
print("ok")
