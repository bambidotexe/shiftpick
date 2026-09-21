import ApplicationServices
import CoreGraphics
import Foundation
import ShiftPickCore

/// Finder's icon views as ShiftPick reads them, and the only code that knows their shape.
///
/// **The hierarchy below was read off macOS 27.0 (build 26A428) with `swift run axdump`, not guessed.**
/// `docs/macOS.md` holds the dumps. Two shapes, one for a window and one for the Desktop:
///
/// ```
/// AXWindow                                          AXApplication (Finder)
///  └ … AXScrollArea                                  └ AXScrollArea / AXDesktop
///      └ AXList / AXCollectionList   <- container        └ AXGroup / AXDesktop   <- container
///          └ AXList / AXSectionList  <- one per group        └ AXImage           <- the items
///              ├ AXStaticText or AXGroup  <- the group's header
///              └ AXGroup                  <- an item
///                  └ AXImage              <- what a click hits
/// ```
///
/// Three facts the code leans on, each measured:
///
/// - **An item's frame is the icon's own box**, never the cell and never the label: two files side by side
///   report the same `64 x 64` at the same `y` although one of their names wraps to two lines.
/// - **A hit test over the label still answers with the item's `AXImage`**, so the point ShiftPick decides
///   from is exactly the point Finder would have acted on. A gap between icons answers with the section.
/// - **A collapsed Desktop stack is an `AXImage` with no `AXURL`.** That is the whole test; its
///   `AXRoleDescription` says "Stack", but that sentence is translated and this one is not.
public enum FinderAX {
    public static let bundleIdentifier = "com.apple.finder"

    /// Where an icon view is. The three are told apart because they are reached differently and because
    /// what a swallowed click owes them differs.
    public enum Host: Equatable, Sendable {
        /// A Finder window's icon view.
        case finderWindow
        /// The Desktop, which is not a window at all and is the only place a stack can be.
        case desktop
        /// An Open or Save panel shown as icons. **Measured**: its hierarchy is Finder's, identifier for
        /// identifier, and its own ⇧ Shift click has exactly the same gap — it adds the one item under the
        /// pointer. It is hosted by whichever application put the panel up, so the process is not Finder's
        /// and the window's `AXIdentifier` is what recognises it instead.
        case panel
    }

    /// A container a click landed in: the element the selection is set on, and what it is.
    public struct IconView {
        public let container: AXUIElement
        /// The window to raise when a click is swallowed; nil for the Desktop, which has none.
        public let window: AXUIElement?
        public let host: Host

        public init(container: AXUIElement, window: AXUIElement?, host: Host) {
            self.container = container
            self.window = window
            self.host = host
        }

        public var isDesktop: Bool { host == .desktop }

        /// What the geometry cannot infer on its own and the container knows: a window fills rows from its
        /// leading edge, the Desktop fills columns from its trailing one. Both measured.
        public var fallbackFlow: Flow {
            if host == .desktop { return layoutIsRightToLeft ? .columnsFromLeft : .columnsFromRight }
            return layoutIsRightToLeft ? .rowsFromRight : .rowsFromLeft
        }

        /// Finder states the direction it lays a view out in. Absent, the system's own is the answer, and
        /// a left-to-right system is the common case.
        var layoutIsRightToLeft: Bool {
            // The attribute is an enumeration whose right-to-left case is 1; anything else, and anything
            // missing, reads as left to right.
            if let value = AX.attribute(container, "AXLayoutDirection") as NSNumber? {
                return value.intValue == 1
            }
            return false
        }
    }

    /// What a click landed on: the view, and the item under the pointer.
    public struct Target {
        public let view: IconView
        public let item: AXUIElement
    }

    /// What is under a point, told apart far enough for the caller to act on it.
    public enum Hit {
        /// An icon in a Finder icon view.
        case item(Target)
        /// A Finder icon view, but not an icon: the gap between two of them, a group's header, the space
        /// under the last row. A plain click there is Finder deselecting everything.
        case emptyIconView
        /// Anything else at all: another application, a Finder window in another view, the sidebar, a
        /// toolbar, the menu bar, or a question Accessibility would not answer.
        case elsewhere
    }

    // MARK: - Finding the view under the pointer

    /// What is under `point`, decided by what the window server draws there and by nothing else: a Finder
    /// window behind another application's window does not answer for a point that window covers, which is
    /// what makes "decide by what is under the cursor" the same thing the user sees.
    public static func hit(at point: CGPoint, finderPID: pid_t, timeout: Float) -> Hit {
        guard let hit = AX.element(at: point, timeout: timeout) else { return .elsewhere }
        let isFinder = AX.pid(of: hit) == finderPID
        AX.setTimeout(timeout, on: hit)

        // The chain up from what was hit. Twelve is far more than any of the three shapes needs — the
        // deepest, a file panel, puts its window seven above the icon — and it bounds the walk in a
        // hierarchy this code does not own.
        var chain: [AXUIElement] = [hit]
        while chain.count < 12, let parent = AX.parent(chain[chain.count - 1]) {
            AX.setTimeout(timeout, on: parent)
            chain.append(parent)
        }

        for (depth, element) in chain.enumerated() {
            let role = AX.role(element)
            let subrole = AX.subrole(element)
            if role == "AXGroup", subrole == "AXDesktop" {
                // The Desktop is Finder's and nobody else's.
                guard isFinder else { return .elsewhere }
                let view = IconView(container: element, window: nil, host: .desktop)
                guard depth >= 1, isItem(chain[depth - 1]) else { return .emptyIconView }
                return .item(Target(view: view, item: chain[depth - 1]))
            }
            if role == "AXList", subrole == "AXCollectionList" {
                let window = self.window(of: element, above: depth, in: chain)
                // Finder's own window, or a panel, and nothing else: another application's collection
                // list is somebody else's control, whatever it looks like.
                guard let host = host(isFinder: isFinder, window: window) else { return .elsewhere }
                let view = IconView(container: element, window: window, host: host)
                // The item is a section's child, so the section has to lie between them: a hit on the
                // section itself is the gap between two icons, and a hit on a group's header is its text.
                guard depth >= 2, AX.subrole(chain[depth - 1]) == "AXSectionList",
                      isItem(chain[depth - 2]) else { return .emptyIconView }
                return .item(Target(view: view, item: chain[depth - 2]))
            }
        }
        return .elsewhere
    }

    /// The window a view is in. Finder's collection list answers `AXWindow` itself; **a file panel's does
    /// not** (measured: `AXWindow` on it is `kAXErrorNoValue`), so the chain the hit test already walked is
    /// searched for one instead.
    private static func window(of container: AXUIElement, above depth: Int,
                               in chain: [AXUIElement]) -> AXUIElement? {
        if let window = AX.element(container, "AXWindow") { return window }
        guard depth + 1 < chain.count else { return nil }
        return chain[(depth + 1)...].first { AX.role($0) == "AXWindow" }
    }

    /// The identifiers AppKit gives its two file panels. They are not translated, unlike the role
    /// descriptions beside them, which is why they are what the check reads.
    private static let panelWindowIdentifiers: Set<String> = ["open-panel", "save-panel"]

    /// nil when this collection list is neither Finder's nor a file panel's.
    private static func host(isFinder: Bool, window: AXUIElement?) -> Host? {
        if isFinder { return .finderWindow }
        guard let window, let identifier = AX.string(window, "AXIdentifier"),
              panelWindowIdentifiers.contains(identifier) else { return nil }
        return .panel
    }

    /// Whether this element is an icon and not a group's header. A header is an `AXStaticText`, or an
    /// `AXGroup` with no image in it; both are ruled out by asking for the image.
    private static func isItem(_ element: AXUIElement) -> Bool {
        let role = AX.role(element)
        if role == "AXImage" { return true }
        return role == "AXGroup" && AX.children(element).contains { AX.role($0) == "AXImage" }
    }

    // MARK: - Reading a view

    /// Every item the view is showing, as the selection maths sees them, together with the element each one
    /// came from so that a chosen range can be handed back to Finder.
    ///
    /// **Finder only builds the icons that are on screen**, plus a little beyond the edges: a folder of
    /// 2,500 files answers with the 24 to 30 that are visible. That is not a failure and it is not worked
    /// around here; `ShiftPickEngine` checks that both ends of the range are among what came back, which is
    /// what makes the answer complete or makes it let the click through. `docs/pitfalls.md` has the
    /// measurement and why Apple events are not the way out.
    public static func items(in view: IconView, timeout: Float) -> [(LayoutItem, AXUIElement)] {
        let containerWidth = AX.frame(view.container)?.width ?? .greatestFiniteMagnitude
        var result: [(LayoutItem, AXUIElement)] = []

        if view.isDesktop {
            // The Desktop has no sections, and it is the only place a stack can be, so this is the only
            // path that pays for an AXURL per item.
            for (order, child) in AX.children(view.container).enumerated() {
                AX.setTimeout(timeout, on: child)
                guard let frame = AX.frame(child), frame.width > 0, frame.height > 0 else { continue }
                result.append((LayoutItem(frame: frame, section: 0, axOrder: order,
                                          isFile: AX.url(child) != nil), child))
            }
            return result
        }

        for (section, list) in AX.children(view.container).enumerated() {
            AX.setTimeout(timeout, on: list)
            for (order, child) in AX.children(list).enumerated() {
                AX.setTimeout(timeout, on: child)
                guard let frame = AX.frame(child), frame.width > 0, frame.height > 0 else { continue }
                // A group's header runs the whole width of the view and is a band rather than a square.
                // One frame per child is all this costs, which is what keeps a screenful under 20 ms.
                if frame.width >= containerWidth * 0.9, frame.width > frame.height * 2 { continue }
                result.append((LayoutItem(frame: frame, section: section, axOrder: order, isFile: true),
                               child))
            }
        }
        return result
    }

    /// Which of `elements` Finder currently has selected. Elements compare by `CFEqual`, which Finder's own
    /// answer to `AXSelectedChildren` is built from, so this costs one round trip and no attribute reads.
    public static func selection(in view: IconView, among elements: [AXUIElement]) -> [Int] {
        let selected = AX.elements(view.container, "AXSelectedChildren")
        guard !selected.isEmpty else { return [] }
        var index: [UInt: Int] = [:]
        for (position, element) in elements.enumerated() { index[CFHash(element)] = position }
        return selected.compactMap { element in
            guard let candidate = index[CFHash(element)], CFEqual(elements[candidate], element) else { return nil }
            return candidate
        }
    }

    /// Replaces the view's selection. One call, whatever the size of the range.
    @discardableResult
    public static func select(_ elements: [AXUIElement], in view: IconView) -> Bool {
        AX.set(view.container, "AXSelectedChildren", to: elements as CFArray)
    }

    /// Where the stored anchor is now, or nil when Finder no longer has that element.
    public static func index(of anchor: AXUIElement, among elements: [AXUIElement]) -> Int? {
        elements.firstIndex { CFEqual($0, anchor) }
    }

    // MARK: - The rest of Finder

    /// True while a name is being typed in place. A rename puts a text field where the label was, and
    /// swallowing a click then would take it away from the field the user is typing in.
    public static func isRenaming(finder: AXUIElement) -> Bool {
        guard let focused = AX.element(finder, "AXFocusedUIElement") else { return false }
        let role = AX.role(focused)
        return role == "AXTextField" || role == "AXTextArea"
    }

    /// What the swallowed click would have done besides selecting: bring the owning application forward,
    /// and raise the window that was clicked. The Desktop has no window, so making Finder frontmost is the
    /// whole of it there.
    public static func raise(_ view: IconView, application: AXUIElement) {
        AX.set(application, kAXFrontmostAttribute as String, to: kCFBooleanTrue)
        guard let window = view.window else { return }
        AX.perform(window, kAXRaiseAction as String)
        AX.set(window, kAXMainAttribute as String, to: kCFBooleanTrue)
    }
}
