import AppKit

// Private DFR (DigitalFunctionRow) entry points for placing an item directly
// into the Control Strip. Declared via dlsym so the build does not link a
// private framework. NOTE: this layer is unverified on a no-Touch-Bar dev
// machine — it must be tested on the real Touch Bar hardware.
private typealias DFRPresenceFn = @convention(c) (NSString, Bool) -> Void

private let dfrHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

private let dfrSetPresence: DFRPresenceFn? = {
    guard let h = dfrHandle,
          let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier")
    else { return nil }
    return unsafeBitCast(sym, to: DFRPresenceFn.self)
}()

/// Owns the Control Strip item and updates its gauge image.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.claudebar.monitor.status")

    /// Centre-icon animation playback rate.
    private static let animationFPS: TimeInterval = 10

    private let button: NSButton
    private let onTap: () -> Void

    /// Ordered animation frames for the gauge centre; empty when none bundled.
    private let frames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?

    /// Most recent status, redrawn on every animation tick.
    private var lastDisplay = StatusDisplay.from(.needsLogin)

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.frames = TokenAnimation.loadFrames()
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

    /// Drive the centre-icon loop. No-op when there are no frames to cycle.
    private func startAnimation() {
        guard frames.count > 1 else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1 / Self.animationFPS, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frames.count
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
        dfrSetPresence?(Self.itemIdentifier.rawValue as NSString, true)
    }

    /// Store the latest status and redraw. Called from the poll loop.
    func update(_ display: StatusDisplay) {
        DispatchQueue.main.async {
            self.lastDisplay = display
            self.render()
        }
    }

    /// Draw the gauge image for the current status + animation frame. When no
    /// frames are bundled, fall back to a coloured text label so the item is
    /// never blank.
    private func render() {
        let display = lastDisplay
        guard !frames.isEmpty else {
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(
                string: display.showsGauge ? "🤖 \(display.text)" : display.text,
                attributes: [.foregroundColor: display.level.color])
            return
        }
        let frame = frames[min(frameIndex, frames.count - 1)]
        let image = GaugeRenderer.image(for: display, centerIcon: frame)
        image.accessibilityDescription = display.text
        button.imagePosition = .imageOnly
        button.image = image
    }

    @objc private func handleTap() {
        onTap()
    }
}
