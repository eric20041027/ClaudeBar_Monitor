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

/// Owns the Control Strip item and updates its label/colour.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.claudebar.monitor.status")

    private let button: NSButton
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.button = NSButton(title: "🤖 …", target: nil, action: nil)
        super.init()
        button.target = self
        button.action = #selector(handleTap)
        registerInControlStrip()
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

    func update(_ display: StatusDisplay) {
        let attr = NSAttributedString(
            string: display.text,
            attributes: [.foregroundColor: display.level.color])
        DispatchQueue.main.async {
            self.button.attributedTitle = attr
        }
    }

    @objc private func handleTap() {
        onTap()
    }
}
