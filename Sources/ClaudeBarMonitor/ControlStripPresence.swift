import AppKit

/// Wraps the private DFR (DigitalFunctionRow) entry point that toggles whether a
/// Control Strip item is present. Resolved via dlsym so the build links no
/// private framework; if the symbol is missing the call is a safe no-op.
///
/// Shared by every Control Strip item (usage gauge, session cost). These are
/// private APIs — a future macOS update could break them, in which case items
/// silently stop appearing (no crash).
enum ControlStripPresence {
    private typealias PresenceFn = @convention(c) (NSString, Bool) -> Void

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
               RTLD_NOW)

    private static let setPresence: PresenceFn? = {
        guard let h = handle,
              let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier")
        else { return nil }
        return unsafeBitCast(sym, to: PresenceFn.self)
    }()

    /// Show or hide the Control Strip item with the given identifier.
    static func set(_ identifier: String, present: Bool) {
        setPresence?(identifier as NSString, present)
    }
}
