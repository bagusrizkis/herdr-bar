import AppKit

enum StatusIconState { case idle, working, blocked, disconnected }

/// Draws the menu bar template image from the design-system geometry (18 pt grid).
/// The canvas is a constant 18×18 pt: the working count and the blocked "!" live in a
/// corner badge, so the icon never changes width with the numbers.
enum StatusIconRenderer {
    static let size: CGFloat = 18

    static func image(state: StatusIconState, count: Int, showCount: Bool) -> NSImage {
        let badge: String? = switch state {
            case .blocked: "!"
            case .working: (showCount && count > 0) ? (count > 9 ? "9+" : "\(count)") : nil
            case .idle, .disconnected: nil
        }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawGlyph(in: ctx, state: state)
            if let badge { drawBadge(badge, in: ctx) }
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func drawGlyph(in ctx: CGContext, state: StatusIconState) {
        let cx: CGFloat = 9, cy: CGFloat = 9.6, r: CGFloat = 6.2, w: CGFloat = 1.6
        let arcAlpha: CGFloat = state == .disconnected ? 0.55 : 1
        let dotAlpha: CGFloat = switch state {
            case .idle: 0.45
            case .working, .blocked: 1
            case .disconnected: 0.35
        }
        ctx.saveGState()
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(arcAlpha).cgColor)
        let start = 125 * CGFloat.pi / 180, end = 415 * CGFloat.pi / 180
        if state == .disconnected {
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [2.2, 2.0])
        }
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(NSColor.black.withAlphaComponent(dotAlpha).cgColor)
        for (x, y) in [(9.0, 7.7), (6.55, 11.2), (11.45, 11.2)] {
            let rr: CGFloat = 1.35
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }
        ctx.restoreGState()
    }

    /// Corner badge: solid disc (or pill for two characters) with the text knocked out,
    /// plus a 0.7 pt clear ring so it separates from the arc underneath.
    private static func drawBadge(_ text: String, in ctx: CGContext) {
        let font = NSFont.systemFont(ofSize: 6.5, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let h: CGFloat = 7.8
        let wBadge = max(h, ceil(textSize.width) + 3.2)
        // keep the whole badge (and its clear ring) inside the 18 pt canvas
        let rect = CGRect(x: size - wBadge - 0.2, y: 0.2, width: wBadge, height: h)
        let ring = rect.insetBy(dx: -0.7, dy: -0.7)
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(CGPath(roundedRect: ring, cornerWidth: ring.height / 2, cornerHeight: ring.height / 2, transform: nil))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.fillPath()
        ctx.setBlendMode(.clear)
        let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 + 0.1)
        (text as NSString).draw(at: origin, withAttributes: attrs)
        ctx.restoreGState()
    }

    /// Debug helper: `HERDRBAR_DUMP_ICONS=/some/dir` writes every state as PNG (4x) and quits.
    static func dumpIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["HERDRBAR_DUMP_ICONS"] else { return }
        let cases: [(String, StatusIconState, Int)] = [("idle", .idle, 0), ("working-1", .working, 1), ("working-3", .working, 3),
                                                        ("working-12", .working, 12), ("blocked", .blocked, 2), ("off", .disconnected, 0)]
        for (name, state, count) in cases {
            let img = image(state: state, count: count, showCount: true)
            let scale: CGFloat = 8
            let px = Int(size * scale), pw = Int(img.size.width * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(white: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: pw, height: px).fill()
            img.draw(in: NSRect(x: 0, y: 0, width: pw, height: px))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        exit(0)
    }
}
