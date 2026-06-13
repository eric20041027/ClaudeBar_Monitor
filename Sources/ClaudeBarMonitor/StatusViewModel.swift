import AppKit

/// Colour state per the spec: remaining >50% safe, 50-20% warning, <20% danger.
enum StatusLevel {
    case safe, warning, danger, error

    var color: NSColor {
        switch self {
        case .safe:    return .labelColor
        case .warning: return .systemYellow
        case .danger:  return .systemRed
        case .error:   return .systemOrange
        }
    }
}

/// Display model derived from a UsageResult. Pure mapping, no side effects.
struct StatusDisplay {
    let text: String
    let level: StatusLevel
    /// True when tapping should open the Claude app (login needed).
    let isActionable: Bool

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
                text: "🤖 \(Int(remaining.rounded()))%",
                level: level,
                isActionable: false)

        case .needsLogin:
            return StatusDisplay(text: "⚠️ 需登入", level: .error, isActionable: true)

        case .offline:
            return StatusDisplay(text: "🔌 離線", level: .error, isActionable: false)

        case .apiError:
            return StatusDisplay(text: "⚠️ API", level: .error, isActionable: false)
        }
    }
}
