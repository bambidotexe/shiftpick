import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Thin wrappers over the C Accessibility API. Every call is synchronous IPC to the target app, which is
/// why every element the click path touches is given `K.axTimeout` first, and why **none of this is ever
/// called on the thread that serves the event taps**: the worker asks, and the tap's thread waits for the
/// worker with a deadline of its own (`DeadlineGate`).
public enum AX {
    // MARK: - The grant, as the calls themselves report it

    /// How many calls have come back `apiDisabled` in the life of this process.
    ///
    /// `AXIsProcessTrusted()` is an answer the system keeps for the process and can go on giving after the
    /// grant has been taken away; a real request is refused the moment it is gone. So every call made here
    /// is also a witness: whoever needs to know compares this number before and after its work, and a
    /// difference means the grant is gone whatever the cached answer still says.
    public static var refusalCount: Int { refusals.withLock { $0 } }

    private static let refusals = OSAllocatedUnfairLock(initialState: 0)

    private static func witness(_ error: AXError) {
        if error == .apiDisabled { refusals.withLock { $0 += 1 } }
    }

    private static func copy(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        witness(error)
        return error == .success ? value : nil
    }

    // MARK: - Reading

    public static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        copy(element, name) as? T
    }

    public static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = copy(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    public static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let array = copy(element, name) as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    public static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) }

    public static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute as String)
    }

    public static func subrole(_ element: AXUIElement) -> String? {
        attribute(element, kAXSubroleAttribute as String)
    }

    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute as String)
    }

    public static func parent(_ node: AXUIElement) -> AXUIElement? {
        element(node, kAXParentAttribute as String)
    }

    /// One round trip for a whole rectangle. `AXPosition` and `AXSize` would be two, and the click path
    /// asks this of every icon on screen.
    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let value: AXValue = attribute(element, "AXFrame") else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    public static func url(_ element: AXUIElement) -> URL? {
        (attribute(element, "AXURL") as NSURL?) as URL?
    }

    public static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// How long this element is given to answer, before a call to it fails instead of waiting.
    public static func setTimeout(_ seconds: Float, on element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    // MARK: - Writing

    @discardableResult
    public static func set(_ element: AXUIElement, _ name: String, to value: CFTypeRef) -> Bool {
        let error = AXUIElementSetAttributeValue(element, name as CFString, value)
        witness(error)
        return error == .success
    }

    public static func perform(_ element: AXUIElement, _ action: String) {
        witness(AXUIElementPerformAction(element, action as CFString))
    }

    // MARK: - Hit testing

    /// The element the window server draws at this point, which is the top one: a Finder window behind
    /// another application's window does not answer for a point that application covers. That is what makes
    /// "decide by what is under the cursor" the same thing the user sees.
    public static func element(at point: CGPoint, timeout: Float) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        setTimeout(timeout, on: system)
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        witness(error)
        return error == .success ? hit : nil
    }
}
