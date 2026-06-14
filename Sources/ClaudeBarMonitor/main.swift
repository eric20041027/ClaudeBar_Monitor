import AppKit

private let pollInterval: TimeInterval = 4 * 60   // 4 minutes (spec: 3-5 min)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = UsageClient()
    private var controller: TouchBarController!

    // Session-cost item (left of the usage gauge). Demo data for now; swap the
    // provider for a transcript-backed one to show real spend.
    private var costController: CostBarController!
    private let costProvider: CostProviding = DemoCostProvider()

    private var timer: Timer?
    private var lastResult: UsageResult = .needsLogin

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = TouchBarController(onTap: { [weak self] in self?.handleTap() })
        costController = CostBarController(onTap: { [weak self] in self?.refresh() })

        // Immediate first refresh, then poll.
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) {
            [weak self] _ in self?.refresh()
        }
        t.tolerance = 30
        timer = t
    }

    private func refresh() {
        // Cost is local/synchronous; update it immediately each tick.
        costController.update(CostDisplay.from(cost: costProvider.currentSessionCost()))

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
