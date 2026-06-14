import Foundation

/// Source of the current Claude Code session cost, in USD.
///
/// Abstracted so the UI never depends on where the number comes from. The demo
/// implementation fabricates a value to validate the Touch Bar presentation;
/// a real implementation (reading `~/.claude` transcripts and pricing the token
/// usage) can be dropped in later without touching the UI layer.
protocol CostProviding {
    /// The session cost so far, in USD. Called once per poll tick.
    func currentSessionCost() -> Double
}

/// Demo provider: a bounded random walk so the value drifts up and down on each
/// poll, exercising every colour/state band. Not real spend — placeholder until
/// a transcript-backed provider replaces it.
final class DemoCostProvider: CostProviding {
    /// Inclusive bounds for the fabricated cost (USD).
    private let range: ClosedRange<Double>
    /// Maximum absolute change applied per tick (USD).
    private let maxStep: Double
    private var value: Double

    init(start: Double = 1.50,
         range: ClosedRange<Double> = 0...20,
         maxStep: Double = 1.25) {
        self.range = range
        self.maxStep = maxStep
        self.value = min(max(start, range.lowerBound), range.upperBound)
    }

    func currentSessionCost() -> Double {
        let delta = Double.random(in: -maxStep...maxStep)
        value = min(max(value + delta, range.lowerBound), range.upperBound)
        return value
    }
}
