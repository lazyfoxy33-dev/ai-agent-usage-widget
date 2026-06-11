import AppKit

// On macOS the always-visible Control Strip gives a single app one fixed,
// narrow cell (~6 glyphs) — it can't be widened and a process can't hold more
// than one slot. So the readout lives in two pieces:
//
//   * a small persistent tray cell (glanceable summary), pinned via
//       NSTouchBarItem +addSystemTrayItem:  and
//       DFRElementSetControlStripPresenceForIdentifier  (private)
//   * a full-width system-modal bar (the detail view) presented on tap via
//       NSTouchBar +presentSystemModalTouchBar:systemTrayItemIdentifier:
//     and dismissed with +minimizeSystemModalTouchBar:  (all private)
//
// We reach DFRFoundation through dlsym and the NSTouchBar/NSTouchBarItem class
// methods through the Objective-C runtime.

private typealias SetPresenceFn = @convention(c) (CFString, Bool) -> Void

private let setPresence: SetPresenceFn? = {
    let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
    guard let handle = dlopen(path, RTLD_NOW),
          let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
    else { return nil }
    return unsafeBitCast(sym, to: SetPresenceFn.self)
}()

enum ControlStrip {
    static let identifier = "com.quotabar.item"

    /// Pins `item` into the Control Strip as the persistent summary cell.
    @discardableResult
    static func install(_ item: NSTouchBarItem) -> Bool {
        let cls: AnyObject = NSTouchBarItem.self
        let sel = NSSelectorFromString("addSystemTrayItem:")
        guard cls.responds(to: sel), let setPresence = setPresence else { return false }
        _ = cls.perform(sel, with: item)
        setPresence(identifier as CFString, true)
        return true
    }

    static func remove(_ item: NSTouchBarItem) {
        let cls: AnyObject = NSTouchBarItem.self
        let sel = NSSelectorFromString("removeSystemTrayItem:")
        if cls.responds(to: sel) { _ = cls.perform(sel, with: item) }
        setPresence?(identifier as CFString, false)
    }

    /// Presents `bar` full-width, anchored to our tray cell.
    static func presentModal(_ bar: NSTouchBar) {
        let cls: AnyObject = NSTouchBar.self
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard cls.responds(to: sel) else { return }
        _ = cls.perform(sel, with: bar, with: identifier as NSString)
    }

    /// Collapses the modal bar back to the small tray cell.
    static func minimizeModal(_ bar: NSTouchBar) {
        let cls: AnyObject = NSTouchBar.self
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        guard cls.responds(to: sel) else { return }
        _ = cls.perform(sel, with: bar)
    }
}
