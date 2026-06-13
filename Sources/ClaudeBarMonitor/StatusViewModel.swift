import AppKit

/// Colour state for the gauge ring: remaining >50% orange (safe), 20-50%
/// yellow (warning), <20% red (danger). `error` is used for non-success states.
enum StatusLevel {
    case safe, warning, danger, error

    /// Claude-brand orange used for the healthy state.
    static let claudeOrange = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)

    var color: NSColor {
        switch self {
        case .safe:    return Self.claudeOrange
        case .warning: return .systemYellow
        case .danger:  return .systemRed
        case .error:   return .systemGray
        }
    }
}

/// Display model derived from a UsageResult. Pure mapping, no side effects.
struct StatusDisplay {
    /// Short text shown for error/login states (and as accessibility label).
    let text: String
    let level: StatusLevel
    /// True when tapping should open the Claude app (login needed).
    let isActionable: Bool
    /// Remaining quota 0–100 for the gauge ring; nil for non-success states.
    let remaining: Double?

    /// Whether the gauge ring should be drawn (true only on success).
    var showsGauge: Bool { remaining != nil }

    static func from(_ result: UsageResult) -> StatusDisplay {
        switch result {
        case .success(let usage):
            let remaining = max(0, 100 - usage.fiveHour.utilization)
            let level: StatusLevel
            switch remaining {
            case 50...: level = .safe
            case 20..<50: level = .warning
            default: level = .danger
            }
            return StatusDisplay(
                text: "\(Int(remaining.rounded()))%",
                level: level,
                isActionable: false,
                remaining: remaining)

        case .needsLogin:
            return StatusDisplay(text: "⚠️ 需登入", level: .error, isActionable: true, remaining: nil)

        case .offline:
            return StatusDisplay(text: "🔌 離線", level: .error, isActionable: false, remaining: nil)

        case .apiError:
            return StatusDisplay(text: "⚠️ API", level: .error, isActionable: false, remaining: nil)
        }
    }
}
