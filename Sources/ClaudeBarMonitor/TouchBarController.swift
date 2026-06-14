import AppKit

// Control Strip placement uses two private APIs: `+[NSTouchBarItem
// addSystemTrayItem:]` (called via the ObjC runtime below) and the DFR presence
// toggle (wrapped in ControlStripPresence). Both degrade to a safe no-op if the
// symbol is missing.

/// Owns the single Control Strip item and updates its image. The item shows one
/// of two faces, toggled by tapping:
///   - `.gauge` — the 5h usage ring with the animated token coin (default).
///   - `.cost`  — the pixel engineer with the objective session cost ($x.xx).
///
/// A single system-tray item is used because registering a *second* one
/// replaces the first rather than sitting beside it (verified on hardware).
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.claudebar.monitor.status")

    /// Which face the item currently shows.
    enum Mode { case gauge, cost }

    /// Centre-icon / engineer animation playback rate.
    private static let animationFPS: TimeInterval = 10

    private let button: NSButton
    /// Invoked when the gauge is in an actionable (login-needed) state and the
    /// item is tapped — opens the Claude app and refreshes. In every other state
    /// a tap toggles the display mode instead.
    private let onTap: () -> Void

    /// Animation frames per face; either may be empty (text-only fallback).
    private let gaugeFrames: [NSImage]
    private let costFrames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?

    private var mode: Mode = .gauge

    /// Most recent gauge status, redrawn on every animation tick.
    private var lastDisplay = StatusDisplay.from(.needsLogin)
    /// Most recent session cost, shown in `.cost` mode.
    private var lastCost = CostDisplay.from(cost: 0)

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.gaugeFrames = TokenAnimation.loadFrames()
        // Prefer the pixel engineer GIF; until the user supplies it, fall back to
        // the token GIF so the cost face is never blank during the demo.
        let engineer = TokenAnimation.loadFrames(directory: "cost-frames",
                                                 gifName: "engineer.gif")
        self.costFrames = engineer.isEmpty ? self.gaugeFrames : engineer

        self.button = NSButton(title: "🤖 …", target: nil, action: nil)
        super.init()
        button.target = self
        button.action = #selector(handleTap)
        button.imagePosition = .imageOnly
        button.isBordered = false
        registerInControlStrip()
        startAnimation()
        render()
    }

    deinit {
        animationTimer?.invalidate()
    }

    /// Frames for the current face.
    private var frames: [NSImage] {
        mode == .cost ? costFrames : gaugeFrames
    }

    /// Drive the animation loop. Steps the shared frame index; redraws using the
    /// current face's frames. No-op when neither face has frames to cycle.
    private func startAnimation() {
        guard gaugeFrames.count > 1 || costFrames.count > 1 else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1 / Self.animationFPS, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            let count = self.frames.count
            if count > 1 { self.frameIndex = (self.frameIndex + 1) % count }
            self.render()
        }
        t.tolerance = (1 / Self.animationFPS) * 0.2
        animationTimer = t
    }

    private func registerInControlStrip() {
        let item = NSCustomTouchBarItem(identifier: Self.itemIdentifier)
        item.view = button

        // `+[NSTouchBarItem addSystemTrayItem:]` is private — call it via the
        // ObjC runtime. Unverified on this dev machine (no Touch Bar).
        let sel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: sel) {
            _ = (NSTouchBarItem.self as AnyObject).perform(sel, with: item)
        }
        ControlStripPresence.set(Self.itemIdentifier.rawValue, present: true)
    }

    /// Store the latest gauge status and redraw. Called from the poll loop.
    func update(_ display: StatusDisplay) {
        DispatchQueue.main.async {
            self.lastDisplay = display
            self.render()
        }
    }

    /// Store the latest session cost and redraw. Called from the poll loop.
    func updateCost(_ display: CostDisplay) {
        DispatchQueue.main.async {
            self.lastCost = display
            if self.mode == .cost { self.render() }
        }
    }

    /// Draw the current face for the current animation frame.
    private func render() {
        switch mode {
        case .gauge: renderGauge()
        case .cost:  renderCost()
        }
    }

    /// Gauge ring + coin. When no frames are bundled, fall back to a coloured
    /// text label so the item is never blank.
    private func renderGauge() {
        let display = lastDisplay
        guard !gaugeFrames.isEmpty else {
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: display.showsGauge ? "🤖 \(display.text)" : display.text,
                attributes: [.foregroundColor: display.level.color])
            return
        }
        let frame = gaugeFrames[min(frameIndex, gaugeFrames.count - 1)]
        let image = GaugeRenderer.image(for: display, centerIcon: frame)
        image.accessibilityDescription = display.text
        button.imagePosition = .imageOnly
        button.image = image
    }

    /// Engineer + cost text baked into one image (no button title, so the cost
    /// never truncates). Falls back to text-only when no frames are bundled.
    private func renderCost() {
        let display = lastCost
        let frame = costFrames.isEmpty
            ? nil
            : costFrames[min(frameIndex, costFrames.count - 1)]
        let image = CostRenderer.image(for: display, icon: frame)
        button.imagePosition = .imageOnly
        button.image = image
    }

    /// Tap behaviour: if the gauge needs login, open Claude (existing recovery
    /// flow); otherwise toggle between the gauge and cost faces.
    @objc private func handleTap() {
        if mode == .gauge && lastDisplay.isActionable {
            onTap()
            return
        }
        mode = (mode == .gauge) ? .cost : .gauge
        frameIndex = 0
        render()
    }
}
