import AppKit

/// A closure target for any `NSControl`, so a button's action can be written where the button is built.
/// From `.claude/skills/building-onboarding/reference/ControlActionHandler.swift`.
///
/// The one hand-built AppKit window in this app is the onboarding wizard; everything else is SwiftUI, where
/// a button already carries its action.
private final class ActionTrampoline: NSObject {
    let handler: () -> Void
    init(_ h: @escaping () -> Void) { handler = h }
    @objc func fire(_ sender: Any?) { handler() }
}

private var trampolineKey: UInt8 = 0

extension NSControl {
    var actionHandler: (() -> Void)? {
        get { (objc_getAssociatedObject(self, &trampolineKey) as? ActionTrampoline)?.handler }
        set {
            guard let h = newValue else {
                objc_setAssociatedObject(self, &trampolineKey, nil, .OBJC_ASSOCIATION_RETAIN)
                return
            }
            let t = ActionTrampoline(h)
            objc_setAssociatedObject(self, &trampolineKey, t, .OBJC_ASSOCIATION_RETAIN)
            target = t
            action = #selector(ActionTrampoline.fire(_:))
        }
    }
}
