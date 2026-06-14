import AppKit

// Reuses the shared ControlStripPresence helper (DFR private API) to add a
// *second* Control Strip item with its own identifier. The OS decides the
// left/right ordering of Control Strip items, so the relative position is not
// guaranteed by any public API and must be confirmed on real hardware.

/// Owns the session-cost Control Strip item: a pixel engineer animation with the
/// objective cost ("$3.42") beside it. Independent of the usage gauge item.
final class CostBarController: NSObject {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.claudebar.monitor.cost")

    /// Engineer animation playback rate.
    private static let animationFPS: TimeInterval = 10

    private let button: NSButton
    private let onTap: () -> Void

    /// Ordered animation frames; empty when none bundled (text-only fallback).
    private let frames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?

    private var lastDisplay = CostDisplay.from(cost: 0)

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        // Prefer the pixel engineer GIF; until the user supplies it, fall back to
        // the existing token GIF so the item is never blank during the demo.
        let engineer = TokenAnimation.loadFrames(directory: "cost-frames",
                                                 gifName: "engineer.gif")
        self.frames = engineer.isEmpty ? TokenAnimation.loadFrames() : engineer

        self.button = NSButton(title: "$…", target: nil, action: nil)
        super.init()
        button.target = self
        button.action = #selector(handleTap)
        button.isBordered = false
        registerInControlStrip()
        startAnimation()
        render()
    }

    deinit { animationTimer?.invalidate() }

    /// Store the latest cost and redraw. Called from the poll loop.
    func update(_ display: CostDisplay) {
        DispatchQueue.main.async {
            self.lastDisplay = display
            self.render()
        }
    }

    /// Drive the engineer animation loop. No-op when there is nothing to cycle.
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

        let sel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: sel) {
            _ = (NSTouchBarItem.self as AnyObject).perform(sel, with: item)
        }
        ControlStripPresence.set(Self.itemIdentifier.rawValue, present: true)
    }

    /// Draw the current engineer frame with the cost text to its right. When no
    /// frames are bundled, show coloured text only so the item is never blank.
    private func render() {
        let display = lastDisplay
        button.attributedTitle = NSAttributedString(
            string: display.text,
            attributes: [.foregroundColor: display.level.color])

        guard !frames.isEmpty else {
            button.imagePosition = .noImage
            return
        }
        button.image = frames[min(frameIndex, frames.count - 1)]
        button.image?.accessibilityDescription = display.text
        button.imagePosition = .imageLeading
    }

    @objc private func handleTap() { onTap() }
}
