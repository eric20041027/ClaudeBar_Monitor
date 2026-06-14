import AppKit

private let pollInterval: TimeInterval = 4 * 60   // 4 minutes (spec: 3-5 min)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = UsageClient()
    private var controller: TouchBarController!

    // Session cost shown on the gauge's alternate (tap-to-toggle) face. Real
    // spend, computed from the newest Claude Code transcript.
    private let costProvider: CostProviding = TranscriptCostProvider()

    private var timer: Timer?
    private var lastResult: UsageResult = .needsLogin

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = TouchBarController(onTap: { [weak self] in self?.handleTap() })

        // Immediate first refresh, then poll.
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) {
            [weak self] _ in self?.refresh()
        }
        t.tolerance = 30
        timer = t
    }

    private func refresh() {
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
        // Tapping always triggers an immediate refresh too.
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon; background agent
app.run()
