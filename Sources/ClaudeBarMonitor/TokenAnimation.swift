import AppKit

/// Loads the centre-icon animation frames bundled under
/// `Resources/token-frames`. Two layouts are supported, checked in order:
///
/// 1. **Numbered PNGs** — `token-00.png`, `token-01.png`, … (any zero-padded
///    or plain integer suffix). Frames are sorted by their numeric suffix.
/// 2. **Sprite sheet** — a single `token-sheet.png` sliced into equal frames
///    laid out left-to-right. The frame count is read from `token-sheet.json`
///    (`{ "frames": N }`) or, failing that, inferred by assuming square frames
///    across one row.
///
/// Returns an empty array when no frames are present, letting the caller fall
/// back to a glyph. Pure loading — invoked once at startup.
enum TokenAnimation {
    private static let framesDir = "token-frames"

    /// Pixels whose R, G and B are all at or above this 0–255 value are treated
    /// as background and made transparent. Conservative: clears pure/near-white
    /// only, leaving the coin's yellow and black outline intact.
    private static let whiteThreshold: UInt8 = 240

    /// Load and return the ordered animation frames, or `[]` if none found.
    /// Each frame has its white background knocked out to transparency so the
    /// coin floats on the dark Touch Bar.
    static func loadFrames() -> [NSImage] {
        guard let dirURL = bundleDirectory() else { return [] }

        // Preferred source: an animated GIF whose frames are already separate
        // and transparent — no slicing or background knockout needed.
        let gif = loadGIFFrames(in: dirURL)
        if !gif.isEmpty { return gif }

        // Fallbacks: numbered PNGs, then a single sprite sheet (white knocked
        // out to transparency for the dark Touch Bar).
        let numbered = loadNumberedFrames(in: dirURL)
        let raw = numbered.isEmpty ? loadSpriteSheet(in: dirURL) : numbered
        return raw.map { removingWhiteBackground($0) ?? $0 }
    }

    // MARK: - Bundle location

    private static func bundleDirectory() -> URL? {
        Bundle.module.url(forResource: framesDir, withExtension: nil)
    }

    // MARK: - Animated GIF

    /// Load every frame of `token.gif` in order via ImageIO. Returns `[]` if the
    /// GIF is absent or unreadable.
    private static func loadGIFFrames(in dir: URL) -> [NSImage] {
        let gifURL = dir.appendingPathComponent("token.gif")
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        var frames: [NSImage] = []
        frames.reserveCapacity(count)
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(NSImage(cgImage: cg,
                                  size: NSSize(width: cg.width, height: cg.height)))
        }
        return frames
    }

    // MARK: - Numbered PNG frames

    private static func loadNumberedFrames(in dir: URL) -> [NSImage] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }

        let pngs = entries.filter { $0.pathExtension.lowercased() == "png" }
            .filter { $0.lastPathComponent.lowercased() != "token-sheet.png" }

        let sorted = pngs.sorted { lhs, rhs in
            numericSuffix(of: lhs) < numericSuffix(of: rhs)
        }
        return sorted.compactMap { NSImage(contentsOf: $0) }
    }

    /// Extract the trailing integer in a filename (e.g. `token-07.png` → 7).
    /// Files without a trailing integer sort first (suffix 0).
    private static func numericSuffix(of url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        let digits = name.reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits)) ?? 0
    }

    // MARK: - Sprite sheet (auto-detected)

    /// Load a single sprite sheet, detect the individual coin frames by content
    /// projection, and crop out any non-coin band (e.g. a watermark strip).
    ///
    /// The source may have uneven margins and a bottom watermark, so we don't
    /// slice into equal columns. Instead: knock out the white background, find
    /// the dominant row band of opaque content (drops the watermark row), then
    /// split that band into coins at the empty (fully transparent) column gaps.
    private static func loadSpriteSheet(in dir: URL) -> [NSImage] {
        let sheetURL = dir.appendingPathComponent("token-sheet.png")
        guard let sheet = NSImage(contentsOf: sheetURL),
              let bitmap = AlphaBitmap(image: sheet, whiteThreshold: whiteThreshold)
        else { return [] }

        // When the sidecar declares a frame count, the sheet is assumed to be a
        // clean, evenly-spaced single row — split into equal columns. Content
        // projection over-segments shapes with internal gaps (e.g. an octagonal
        // coin), so only auto-detect when no count is declared.
        if let count = declaredFrameCount(in: dir), count > 1 {
            return bitmap.evenColumns(count: count)
        }

        let band = bitmap.dominantContentRowBand()
        let spans = bitmap.opaqueColumnSpans(rows: band)
        guard !spans.isEmpty else { return [] }

        return spans.map { span in
            let rect = CGRect(x: span.lowerBound, y: band.lowerBound,
                              width: span.count, height: band.count)
            return bitmap.croppedImage(rect)
        }
    }

    /// The declared frame count from `token-sheet.json`, or nil if absent.
    private static func declaredFrameCount(in dir: URL) -> Int? {
        let jsonURL = dir.appendingPathComponent("token-sheet.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frames = obj["frames"] as? Int, frames > 0 else { return nil }
        return frames
    }

    // MARK: - White-background knockout (numbered-PNG path)

    /// Return a copy of `image` with near-white pixels made transparent. Returns
    /// nil if the bitmap cannot be read, so the caller keeps the original.
    private static func removingWhiteBackground(_ image: NSImage) -> NSImage? {
        guard let bitmap = AlphaBitmap(image: image, whiteThreshold: whiteThreshold)
        else { return nil }
        return bitmap.fullImage()
    }
}

/// An RGBA pixel buffer with the white background already knocked out to
/// transparency, plus helpers to locate content by projection. Origin is
/// top-left (row 0 is the top), matching CoreGraphics draw order here.
private struct AlphaBitmap {
    let width: Int
    let height: Int
    private var pixels: [UInt8]      // RGBA, premultiplied-last
    private let bytesPerRow: Int

    init?(image: NSImage, whiteThreshold t: UInt8) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return nil }
        self.width = cg.width
        self.height = cg.height
        self.bytesPerRow = width * 4
        self.pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = pixels.withUnsafeMutableBytes({ buf -> CGContext? in
            CGContext(data: buf.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Note: CGContext y-origin is bottom-left, so this buffer is bottom-up;
        // projection is symmetric in y so band detection is unaffected, and
        // crops convert back via CoreGraphics draw which flips consistently.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[i] >= t, pixels[i + 1] >= t, pixels[i + 2] >= t {
                pixels[i + 3] = 0
            }
        }
    }

    private func alpha(x: Int, y: Int) -> UInt8 { pixels[y * bytesPerRow + x * 4 + 3] }

    /// Count opaque pixels per row, then return the largest contiguous run of
    /// rows that each exceed a small fraction of the busiest row. This isolates
    /// the coin band and excludes a thin watermark strip.
    func dominantContentRowBand() -> Range<Int> {
        var perRow = [Int](repeating: 0, count: height)
        var maxCount = 0
        for y in 0..<height {
            var c = 0
            for x in 0..<width where alpha(x: x, y: y) > 0 { c += 1 }
            perRow[y] = c
            maxCount = max(maxCount, c)
        }
        guard maxCount > 0 else { return 0..<height }
        let rowThreshold = max(1, maxCount / 8)

        var best = 0..<0, current = -1
        for y in 0...height {
            let active = y < height && perRow[y] >= rowThreshold
            if active {
                if current < 0 { current = y }
            } else if current >= 0 {
                if (y - current) > best.count { best = current..<y }
                current = -1
            }
        }
        return best.isEmpty ? 0..<height : best
    }

    /// Within `rows`, find contiguous column spans that contain any opaque
    /// pixel — each span is one coin. Single-column gaps are tolerated so a
    /// coin isn't split by an internal transparent sliver.
    func opaqueColumnSpans(rows: Range<Int>) -> [Range<Int>] {
        var hasContent = [Bool](repeating: false, count: width)
        for x in 0..<width {
            for y in rows where alpha(x: x, y: y) > 0 { hasContent[x] = true; break }
        }
        let minGap = 2          // empty columns needed to separate two coins
        var spans: [Range<Int>] = []
        var start = -1, gap = 0
        for x in 0..<width {
            if hasContent[x] {
                if start < 0 { start = x }
                gap = 0
            } else if start >= 0 {
                gap += 1
                if gap >= minGap { spans.append(start..<(x - gap + 1)); start = -1; gap = 0 }
            }
        }
        if start >= 0 { spans.append(start..<width) }
        return spans.filter { $0.count >= 4 }   // drop noise
    }

    /// Split the full bitmap into `count` equal-width columns. Each frame is
    /// returned as a uniform `cellW × height` canvas with its coin content
    /// re-centred horizontally, so the coin spins in place instead of drifting
    /// left/right as the sprite's content shifts within each cell.
    func evenColumns(count: Int) -> [NSImage] {
        guard count > 0 else { return [] }
        let frameW = Double(width) / Double(count)
        let cellW = Int(frameW.rounded())
        let full = fullCGImage()

        return (0..<count).map { i in
            let x0 = Int((Double(i) * frameW).rounded())
            let x1 = Int((Double(i + 1) * frameW).rounded())
            let bounds = contentColumnBounds(in: x0..<x1)
            return centeredCell(full, content: bounds, cellW: cellW)
        }
    }

    /// Horizontal extent of opaque content within a column range, or nil if the
    /// cell is empty.
    private func contentColumnBounds(in cols: Range<Int>) -> Range<Int>? {
        var minX = cols.upperBound, maxX = cols.lowerBound
        for x in cols {
            for y in 0..<height where alpha(x: x, y: y) > 0 {
                minX = min(minX, x); maxX = max(maxX, x); break
            }
        }
        return minX <= maxX ? minX..<(maxX + 1) : nil
    }

    /// Draw the coin content centred in a fresh `cellW × height` canvas.
    private func centeredCell(_ full: CGImage?, content: Range<Int>?, cellW: Int) -> NSImage {
        let size = NSSize(width: cellW, height: height)
        guard let full, let content, content.count > 0 else { return NSImage(size: size) }

        // full is top-left origin; crop tightly to content then centre it.
        let crop = CGRect(x: content.lowerBound, y: 0, width: content.count, height: height)
        guard let coin = full.cropping(to: crop) else { return NSImage(size: size) }

        let contentW = CGFloat(content.count)
        let h = CGFloat(height)
        let coinImage = NSImage(cgImage: coin, size: NSSize(width: contentW, height: h))
        return NSImage(size: size, flipped: false) { _ in
            let drawX = (CGFloat(cellW) - contentW) / 2
            coinImage.draw(in: CGRect(x: drawX, y: 0, width: contentW, height: h),
                           from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// Crop a rect (top-left origin) into a standalone NSImage.
    func croppedImage(_ rect: CGRect) -> NSImage {
        let full = fullCGImage()
        let cropped = full?.cropping(to: rect) ?? full
        let size = NSSize(width: rect.width, height: rect.height)
        if let c = cropped { return NSImage(cgImage: c, size: size) }
        return NSImage(size: size)
    }

    func fullImage() -> NSImage {
        let size = NSSize(width: width, height: height)
        if let cg = fullCGImage() { return NSImage(cgImage: cg, size: size) }
        return NSImage(size: size)
    }

    private func fullCGImage() -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        var buf = pixels
        let ctx = buf.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        return ctx?.makeImage()
    }
}
