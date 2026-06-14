import AppKit

/// How often to refresh the 5h usage gauge. This hits the Claude API, so it
/// stays infrequent to avoid hammering the endpoint / rate limits.
private let usagePollInterval: TimeInterval = 4 * 60   // 4 minutes (spec: 3-5 min)

/// How often to refresh the session cost. This only reads local files
/// (costs.jsonl tail + the newest transcript), so it can poll often and cheaply
/// — a cost update then lands within ~30s of finishing a prompt. Tapping the
/// gauge also forces an immediate refresh (see `handleTap`).
private let costPollInterval: TimeInterval = 30   // 30 seconds

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = UsageClient()
    private var controller: TouchBarController!

    // Session cost shown on the gauge's alternate (tap-to-toggle) face. Real
    // spend, computed from the newest Claude Code transcript.
    private let costProvider: CostProviding = TranscriptCostProvider()

    private var usageTimer: Timer?
    private var costTimer: Timer?
    private var lastResult: UsageResult = .needsLogin

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = TouchBarController(onTap: { [weak self] in self?.handleTap() })

        // Immediate first refresh of both, then poll each on its own cadence:
        // usage (API) slowly, cost (local files) frequently.
        refreshUsage()
        refreshCost()

        let ut = Timer.scheduledTimer(withTimeInterval: usagePollInterval, repeats: true) {
            [weak self] _ in self?.refreshUsage()
        }
        ut.tolerance = 30
        usageTimer = ut

        let ct = Timer.scheduledTimer(withTimeInterval: costPollInterval, repeats: true) {
            [weak self] _ in self?.refreshCost()
        }
        ct.tolerance = 5
        costTimer = ct
    }

    /// Refresh the session cost from local files (cheap; polled often).
    private func refreshCost() {
        // The transcript can be multi-MB, so price it off the main thread and
        // hop back to update the Touch Bar. Capture into a local `let` to avoid
        // capturing the implicitly-unwrapped `var controller` in the closure.
        let costController = controller!
        let provider = costProvider
        Task.detached {
            let cost = provider.currentSessionCost()
            await MainActor.run {
                costController.updateCost(CostDisplay.from(cost: cost))
            }
        }
    }

    /// Refresh the 5h usage gauge from the Claude API (polled infrequently).
    private func refreshUsage() {
        Task {
            let result = await client.fetch()
            lastResult = result
            controller.update(StatusDisplay.from(result))
        }
    }

    /// On a login-needed state, tapping opens the Claude app so the user can
    /// re-authenticate; the next poll then recovers automatically.
    private func handleTap() {
        let display = StatusDisplay.from(lastResult)
        if display.isActionable {
            let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
            NSWorkspace.shared.openApplication(
                at: claudeURL, configuration: NSWorkspace.OpenConfiguration())
        }
        // Tapping always triggers an immediate refresh of both faces too, so a
        // user who just switched session and wants the number now gets it.
        refreshCost()
        refreshUsage()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon; background agent
app.run()
