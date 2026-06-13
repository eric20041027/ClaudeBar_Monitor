import AppKit

/// Renders the Touch Bar gauge: a circular ring whose filled arc length
/// represents remaining quota, with an icon (animated token frame) at the
/// centre. Pure drawing — no state, no I/O. Sized for the Control Strip.
enum GaugeRenderer {
    /// Square side of the rendered image, in points. The Control Strip item is
    /// ~30pt tall; a square keeps the ring circular.
    static let side: CGFloat = 28

    private static let ringWidth: CGFloat = 3
    /// Inset of the ring centreline from the image edge.
    private static let ringInset: CGFloat = 3
    /// Gap between the ring and the centre icon.
    private static let iconGap: CGFloat = 2

    /// Build the gauge image for a display state.
    /// - Parameters:
    ///   - display: the status to render (gauge drawn only when `showsGauge`).
    ///   - centerIcon: optional icon drawn in the centre (the current animation
    ///     frame). When nil, the centre is left empty for the caller's fallback.
    static func image(for display: StatusDisplay, centerIcon: NSImage?) -> NSImage {
        let s = side
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: s / 2, y: s / 2)
            let radius = s / 2 - ringInset

            if display.showsGauge, let remaining = display.remaining {
                drawTrack(ctx, center: center, radius: radius)
                drawProgress(ctx, center: center, radius: radius,
                             fraction: remaining / 100, color: display.level.color)
            }

            if let icon = centerIcon {
                drawCenterIcon(icon, center: center, ringRadius: radius)
            }
            return true
        }
        // Template images would be re-tinted by the system; we draw real colours.
        img.isTemplate = false
        return img
    }

    /// Faint full-circle background track.
    private static func drawTrack(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
        ctx.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
        ctx.setLineWidth(ringWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }

    /// Coloured progress arc, starting at 12 o'clock and sweeping clockwise.
    private static func drawProgress(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                     fraction: Double, color: NSColor) {
        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return }
        let start = CGFloat.pi / 2                       // 12 o'clock (CG y-up)
        let end = start - CGFloat(clamped) * .pi * 2     // sweep clockwise
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(ringWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius,
                   startAngle: start, endAngle: end, clockwise: true)
        ctx.strokePath()
    }

    /// Draw the centre icon, aspect-fit inside the ring's inner circle.
    private static func drawCenterIcon(_ icon: NSImage, center: CGPoint, ringRadius: CGFloat) {
        let inner = ringRadius - ringWidth / 2 - iconGap
        let box = inner * 2
        let fitted = aspectFit(icon.size, into: CGSize(width: box, height: box))
        let rect = CGRect(x: center.x - fitted.width / 2,
                          y: center.y - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
