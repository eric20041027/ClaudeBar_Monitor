import Foundation

/// Per-model token pricing in USD per 1,000,000 tokens, plus the cache
/// multipliers the Anthropic API applies relative to the base input price.
///
/// `costUSD` is null in Claude Code transcripts, so cost must be computed from
/// `message.usage` token counts × these rates. Prices are matched by model-ID
/// prefix so dated snapshots (e.g. `claude-opus-4-8[1m]`, `...-20251001`)
/// resolve to the right family.
enum ModelPricing {
    /// Base input / output price per 1M tokens for a model family.
    struct Rate {
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    /// Cache pricing is derived from the input price:
    /// 5-minute write = 1.25×, 1-hour write = 2×, read = 0.1×.
    private static let cacheWrite5mMultiplier = 1.25
    private static let cacheWrite1hMultiplier = 2.0
    private static let cacheReadMultiplier = 0.1

    private static let perMillion = 1_000_000.0

    /// Prefix → rate. Longest matching prefix wins, so a more specific family
    /// can override a shorter one if ever needed. Unknown models price at $0.
    private static let table: [(prefix: String, rate: Rate)] = [
        ("claude-fable-5",  Rate(inputPerMillion: 10, outputPerMillion: 50)),
        ("claude-opus",     Rate(inputPerMillion: 5,  outputPerMillion: 25)),
        ("claude-sonnet",   Rate(inputPerMillion: 3,  outputPerMillion: 15)),
        ("claude-haiku",    Rate(inputPerMillion: 1,  outputPerMillion: 5)),
    ]

    /// Token usage for one assistant message, mirroring `message.usage`.
    struct Usage {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheRead: Int = 0
        var cacheWrite5m: Int = 0
        var cacheWrite1h: Int = 0
    }

    /// USD cost of one usage record under the given model's pricing.
    /// Unknown / synthetic models contribute $0 rather than guessing.
    static func cost(model: String, usage: Usage) -> Double {
        guard let rate = rate(for: model) else { return 0 }
        let input = Double(usage.inputTokens) * rate.inputPerMillion
        let output = Double(usage.outputTokens) * rate.outputPerMillion
        let read = Double(usage.cacheRead) * rate.inputPerMillion * cacheReadMultiplier
        let write5m = Double(usage.cacheWrite5m) * rate.inputPerMillion * cacheWrite5mMultiplier
        let write1h = Double(usage.cacheWrite1h) * rate.inputPerMillion * cacheWrite1hMultiplier
        return (input + output + read + write5m + write1h) / perMillion
    }

    /// Longest-prefix match against the pricing table.
    private static func rate(for model: String) -> Rate? {
        table
            .filter { model.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .rate
    }
}
