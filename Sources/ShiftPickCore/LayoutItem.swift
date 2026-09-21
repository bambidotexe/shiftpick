import CoreGraphics
import Foundation

/// One item of an icon view, as the selection math sees it. Nothing here knows about Accessibility: the
/// whole of step 3 is pure functions over these values, so every layout below can be built by hand in a
/// test.
///
/// `frame` is the **icon's own box** in screen points, origin top-left and y downwards, which is the space
/// `CGEvent.location` is in as well. Finder reports exactly that box and nothing else: measured on macOS 27,
/// a file called `file-01.txt` and one called `a-file-with-a-rather-long-name-that-wraps.txt` sitting side
/// by side both report `64 x 64` at the same `y`, although the second one's label takes two lines. That is
/// why the reference point below is the centre of this rectangle and not the centre of a cell: the cell
/// moves with the label, the icon does not.
public struct LayoutItem: Equatable, Sendable {
    /// The icon's box, screen points, y down.
    public let frame: CGRect
    /// Which group the item belongs to. `0` for every item when the view has no groups; with *Use Groups*
    /// on, one number per section, in the order Finder listed them.
    public let section: Int
    /// The position Accessibility listed this item at inside its section. It is evidence about the flow
    /// direction, never the answer on its own: `LayoutModel` only uses it to choose between candidates the
    /// geometry has already accepted.
    public let axOrder: Int
    /// False for something that is not a file: a collapsed Desktop stack. Such an item still takes up a
    /// place in the lattice, because it is drawn in one, but it is never put in a range.
    public let isFile: Bool

    public init(frame: CGRect, section: Int = 0, axOrder: Int = 0, isFile: Bool = true) {
        self.frame = frame
        self.section = section
        self.axOrder = axOrder
        self.isFile = isFile
    }

    /// The point the lattice is built from: the centre of the icon, which does not drift when a name wraps.
    public var reference: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

/// The order a laid-out view fills its lattice in. The two axes are which way the line runs and which side
/// it starts from; lines themselves always go down the screen.
///
/// Expect `rowsLeadingFirst` in a window and `columnsTrailingFirst` on the Desktop (measured: a Desktop
/// sorted by name fills a column at x 1410 from y 42 downwards, then the next column at x 1286, which is
/// to its **left**). A right-to-left system flips what leading means, which is why the caller passes the
/// fallback in rather than the code assuming one.
public enum Flow: String, CaseIterable, Sendable {
    /// Rows down the screen, each row filled from the left.
    case rowsFromLeft
    /// Rows down the screen, each row filled from the right.
    case rowsFromRight
    /// Columns filled downwards, the next column to the right.
    case columnsFromLeft
    /// Columns filled downwards, the next column to the left. The Desktop's own order.
    case columnsFromRight
}

/// What the geometry says about how the items got where they are.
public enum LayoutKind: Equatable, Sendable {
    /// Finder is laying these out: the items fill a lattice contiguously along `Flow`, allowing a partial
    /// last line and a break at every group. Flow order is meaningful, so a range is a slice of it.
    case arranged(Flow)
    /// Holes in the lattice, or items that are not on one at all: *Sort By None*, a Desktop somebody has
    /// arranged by hand. There is no order to slice, so a range is a rubber band.
    case handPlaced
}
