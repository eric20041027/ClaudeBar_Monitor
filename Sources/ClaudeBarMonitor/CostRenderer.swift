import AppKit

/// Renders the session-cost Touch Bar view: a pixel-engineer animation frame on
/// the left with the objective cost (`$3.42`) painted to its right, baked into a
/// single image. Painting the text into the image — instead of using the
/// button's title — is deliberate: a button title beside an image gets truncated
/// in the narrow Control Strip (the original `$2....` bug). Pure drawing; no
/// state, no I/O.
enum CostRenderer {
    /// Image height, in points. Matches `GaugeRenderer.side` so the cost view and
    /// the gauge view occupy the same Control Strip height.
    static let height: CGFloat = 28

    /// Gap between the engineer icon and the cost text, in points.
    private static let iconTextGap: CGFloat = 3
    /// Trailing padding after the text so the last glyph isn't flush to the edge.
    private static let trailingPadding: CGFloat = 2
    /// Cost text font size, in points.
    private static let fontSize: CGFloat = 13

    /// Build the cost image for a display state and the current animation frame.
    /// - Parameters:
    ///   - display: the cost to render (text + colour level).
    ///   - icon: the engineer animation frame to draw on the left; nil draws
    ///     text only.
    static func image(for display: CostDisplay, icon: NSImage?) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: display.level.color,
        ]
        let text = display.text as NSString
        let textSize = text.size(withAttributes: textAttrs)

        // The icon is square (height × height); the image grows wide enough to
        // hold the icon, gap, text, and trailing padding so nothing truncates.
        let iconWidth: CGFloat = icon == nil ? 0 : height
        let leadGap: CGFloat = icon == nil ? 0 : iconTextGap
        let width = iconWidth + leadGap + ceil(textSize.width) + trailingPadding

        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if let icon {
                let box = CGRect(x: 0, y: 0, width: iconWidth, height: height)
                drawIcon(icon, in: box)
            }
            let textY = (height - textSize.height) / 2
            text.draw(at: CGPoint(x: iconWidth + leadGap, y: textY), withAttributes: textAttrs)
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = display.text
        return img
    }

    /// Draw the icon aspect-fit and centred within `box`.
    private static func drawIcon(_ icon: NSImage, in box: CGRect) {
        let fitted = aspectFit(icon.size, into: box.size)
        let rect = CGRect(x: box.midX - fitted.width / 2,
                          y: box.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
