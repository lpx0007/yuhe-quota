import AppKit
import SwiftUI

enum ReactorIcon {
    static func image(level: AlertLevel, size: CGFloat = 18, pulse: Bool = false) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = size * scale
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            let color = cgColor(level)
            let glow = pulse ? 0.95 : 0.72

            let inset: CGFloat = 1.2
            let hex = hexagon(in: rect.insetBy(dx: inset, dy: inset))
            ctx.setStrokeColor(color.copy(alpha: 0.95)!)
            ctx.setLineWidth(1.15)
            ctx.addPath(hex)
            ctx.strokePath()

            let core = hexagon(in: rect.insetBy(dx: size * 0.28, dy: size * 0.28))
            ctx.setFillColor(color.copy(alpha: glow)!)
            ctx.addPath(core)
            ctx.fillPath()

            let spokes: [(CGPoint, CGPoint, CGColor)] = [
                (CGPoint(x: rect.midX, y: rect.maxY - 1.1), CGPoint(x: rect.midX, y: rect.midY - size * 0.12), color),
                (CGPoint(x: rect.maxX - 1.1, y: rect.midY - size * 0.22), CGPoint(x: rect.midX + size * 0.16, y: rect.midY - size * 0.05), CGColor(red: 0.24, green: 1, blue: 0.82, alpha: 0.9)),
                (CGPoint(x: rect.maxX - 1.1, y: rect.midY + size * 0.22), CGPoint(x: rect.midX + size * 0.16, y: rect.midY + size * 0.05), CGColor(red: 0.37, green: 1, blue: 0.60, alpha: 0.9)),
                (CGPoint(x: rect.minX + 1.1, y: rect.midY + size * 0.22), CGPoint(x: rect.midX - size * 0.16, y: rect.midY + size * 0.05), CGColor(red: 0.29, green: 0.66, blue: 1, alpha: 0.9)),
            ]
            ctx.setLineWidth(1)
            for (a, b, c) in spokes {
                ctx.setStrokeColor(c)
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            }
            return true
        }
        image.isTemplate = false
        _ = px
        return image
    }

    private static func hexagon(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            let p = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func cgColor(_ level: AlertLevel) -> CGColor {
        switch level {
        case .ok: CGColor(red: 0.24, green: 1, blue: 0.82, alpha: 1)
        case .warn, .stale: CGColor(red: 1, green: 0.69, blue: 0.13, alpha: 1)
        case .hot, .offline: CGColor(red: 1, green: 0.24, blue: 0.43, alpha: 1)
        }
    }
}
