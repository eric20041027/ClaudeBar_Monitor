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
    /// Engineer frames keyed by cost level (calm/busy/hot). A level maps to its
    /// own GIF; levels with no bundled GIF fall back to `costFallbackFrames`.
    private let costFramesByLevel: [CostLevel: [NSImage]]
    /// Shared fallback when a level's per-level GIF is absent: the single
    /// `engineer.gif`, or the token coin if that's missing too.
    private let costFallbackFrames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?
    /// Re-asserts Control Strip presence periodically. macOS sometimes drops the
    /// item (Control Strip reset, ControlStrip agent restart) while our process
    /// keeps running — the item just vanishes from the Touch Bar. Re-registering
    /// is idempotent (no-op if already present), so a slow timer quietly heals it.
    private var presenceTimer: Timer?
    /// How often to re-assert Control Strip presence. Slow — this is a self-heal
    /// safety net, not a hot path.
    private static let presenceReassertInterval: TimeInterval = 20

    private var mode: Mode = .gauge

    /// Most recent gauge status, redrawn on every animation tick.
    private var lastDisplay = StatusDisplay.from(.needsLogin)
    /// Most recent session cost, shown in `.cost` mode.
    private var lastCost = CostDisplay.from(cost: 0)

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.gaugeFrames = TokenAnimation.loadFrames()

        // Shared fallback for the cost face: the single `engineer.gif`, or the
        // token coin if that's missing too, so the face is never blank.
        let engineer = TokenAnimation.loadFrames(directory: "cost-frames",
                                                 gifName: "engineer.gif")
        self.costFallbackFrames = engineer.isEmpty ? self.gaugeFrames : engineer

        // Per-level engineer GIFs (calm/busy/hot). Each is optional; absent
        // levels resolve to `costFallbackFrames` at render time.
        let levels: [CostLevel] = [.calm, .busy, .hot]
        self.costFramesByLevel = Dictionary(uniqueKeysWithValues: levels.compactMap {
            level in
            let frames = TokenAnimation.loadFrames(directory: "cost-frames",
                                                   gifName: level.gifName)
            return frames.isEmpty ? nil : (level, frames)
        })

        self.button = NSButton(title: "🤖 …", target: nil, action: nil)
        super.init()
        button.target = self
        button.action = #selector(handleTap)
        button.imagePosition = .imageOnly
        button.isBordered = false
        registerInControlStrip()
        startAnimation()
        startPresenceReassert()
        render()
    }

    deinit {
        animationTimer?.invalidate()
        presenceTimer?.invalidate()
    }

    /// Periodically re-assert Control Strip presence so the item self-heals if
    /// macOS dropped it while the process kept running. Only re-toggles the
    /// presence flag (the part the system actually clears) — it does NOT rebuild
    /// the tray item or re-add the button, avoiding any view-reparenting churn.
    private func startPresenceReassert() {
        let t = Timer.scheduledTimer(
            withTimeInterval: Self.presenceReassertInterval, repeats: true
        ) { _ in
            ControlStripPresence.set(Self.itemIdentifier.rawValue, present: true)
        }
        t.tolerance = Self.presenceReassertInterval * 0.5
        presenceTimer = t
    }

    /// Frames for the current face. The cost face picks the engineer GIF for the
    /// latest cost level, falling back to the shared engineer/coin frames.
    private var frames: [NSImage] {
        mode == .cost ? currentCostFrames : gaugeFrames
    }

    /// Engineer frames for the latest cost level, or the shared fallback when
    /// that level has no bundled GIF.
    private var currentCostFrames: [NSImage] {
        costFramesByLevel[lastCost.level] ?? costFallbackFrames
    }

    /// Drive the animation loop. Steps the shared frame index; redraws using the
    /// current face's frames. No-op when neither face has frames to cycle.
    private func startAnimation() {
        let anyCostAnimated = costFallbackFrames.count > 1
            || costFramesByLevel.values.contains { $0.count > 1 }
        guard gaugeFrames.count > 1 || anyCostAnimated else { return }
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
        let levelFrames = currentCostFrames
        let frame = levelFrames.isEmpty
            ? nil
            : levelFrames[min(frameIndex, levelFrames.count - 1)]
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
