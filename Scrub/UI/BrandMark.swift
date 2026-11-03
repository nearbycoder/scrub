import AppKit

/// Scrub's mark (a bubble with a gleam) as a template image for the menu bar.
enum BrandMark {
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.6
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let bubble = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            bubble.lineWidth = 1.5
            bubble.stroke()

            // Rim highlight on the upper left.
            let rim = NSBezierPath()
            rim.appendArc(withCenter: center, radius: radius - 2.6, startAngle: 192, endAngle: 246)
            rim.lineWidth = 1.4
            rim.lineCapStyle = .round
            rim.stroke()

            // Gleam.
            let c = CGPoint(x: center.x + 0.9, y: center.y + 0.9), r: CGFloat = 4.3, pinch: CGFloat = 0.13
            let tips = (0..<4).map { i -> CGPoint in
                let a = CGFloat(i) * .pi / 2 - .pi / 2
                return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            }
            let star = NSBezierPath()
            star.move(to: tips[0])
            for i in 0..<4 {
                let next = tips[(i + 1) % 4]
                star.curve(to: next,
                           controlPoint1: CGPoint(x: c.x + (tips[i].x - c.x) * pinch, y: c.y + (tips[i].y - c.y) * pinch),
                           controlPoint2: CGPoint(x: c.x + (next.x - c.x) * pinch, y: c.y + (next.y - c.y) * pinch))
            }
            star.close()
            star.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Scrub"
        return image
    }()
}
