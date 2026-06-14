import AppKit

/// How "busy"/expensive the current session looks, mapped from cumulative cost.
/// Reuses the gauge palette: low = calm (orange), mid = warning (yellow),
/// high = danger (red). Drives both the text colour and, later, which pixel
/// engineer animation plays.
enum CostLevel {
    case calm, busy, hot

    var color: NSColor {
        switch self {
        case .calm: return StatusLevel.claudeOrange
        case .busy: return .systemYellow
        case .hot:  return .systemRed
        }
    }

    /// Pixel-engineer GIF for this cost level, bundled under `cost-frames`.
    /// calm = leisurely typing, busy = fast typing, hot = head-in-hands panic.
    /// When the per-level file is missing the loader falls back to the single
    /// `engineer.gif`, then to the token coin, so the face is never blank.
    var gifName: String {
        switch self {
        case .calm: return "calm.gif"
        case .busy: return "busy.gif"
        case .hot:  return "hot.gif"
        }
    }
}

/// Display model derived from a session cost (USD). Pure mapping, no I/O.
struct CostDisplay {
    /// Objective cost shown next to the engineer, e.g. "$3.42".
    let text: String
    let level: CostLevel

    /// USD thresholds separating calm / busy / hot session cost.
    /// calm < $10 ≤ busy < $25 ≤ hot.
    static let busyThreshold = 10.0
    static let hotThreshold = 25.0

    static func from(cost: Double) -> CostDisplay {
        let level: CostLevel
        switch cost {
        case ..<busyThreshold: level = .calm
        case busyThreshold..<hotThreshold: level = .busy
        default: level = .hot
        }
        return CostDisplay(text: format(cost), level: level)
    }

    /// "$3.42"; below $10 keep cents, above round to whole dollars to stay short
    /// in the narrow Control Strip.
    private static func format(_ cost: Double) -> String {
        cost < 10 ? String(format: "$%.2f", cost) : String(format: "$%.0f", cost)
    }
}
