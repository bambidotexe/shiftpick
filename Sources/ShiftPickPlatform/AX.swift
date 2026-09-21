import ApplicationServices
import CoreGraphics
import Foundation

/// Thin wrappers over the C Accessibility API. Every call is synchronous IPC to the target app, which is
/// why every element the click path touches is given `K.axTimeout` first.
public enum AX {
    public static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value
        else { return nil }
        return value as? T
    }

    public static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    public static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              let array = value as? [AnyObject] else { return [] }
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

    @discardableResult
    public static func set(_ element: AXUIElement, _ name: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    public static func perform(_ element: AXUIElement, _ action: String) {
        AXUIElementPerformAction(element, action as CFString)
    }

    /// The element the window server draws at this point, which is the top one: a Finder window behind
    /// another application's window does not answer for a point that application covers. That is what makes
    /// "decide by what is under the cursor" the same thing the user sees.
    public static func element(at point: CGPoint, timeout: Float) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        setTimeout(timeout, on: system)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success
        else { return nil }
        return hit
    }
}
