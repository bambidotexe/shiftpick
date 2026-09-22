import CoreGraphics
import XCTest
import ShiftPickCore

/// The measured sequences of the spec's Appendix A, replayed through the model the way the resolver drives
/// it: a plain click and a ⌘ Command click set the anchor; a ⇧ Shift click is measured from
/// `effectiveAnchor`, or from the first icon when nothing is selected, and **leaves the anchor at
/// `Outcome.anchor`, the icon it was measured from, the stand-in included** (`docs/functional.md` §2.1).
/// `ShiftClickTests` replays the states; this replays the histories, which is the only place feeding the
/// anchor back matters. Rows are 1-based in the spec and in the steps below, 0-based in the model.
final class SequenceReplayTests: XCTestCase {
    private enum Step {
        /// A plain click on a row: the selection becomes that row, and so does the anchor.
        case click(Int)
        /// A ⌘ Command click on a row: the row is toggled, and the anchor is that row either way.
        case command(Int)
        /// A row selected without a click on an icon (a drag, ⌘ A, a script): the anchor stays where it was.
        /// Appendix A's W re-selects row 3 this way so that the anchor does not move to 3.
        case select(Int)
        /// A ⇧ Shift click on a row.
        case shift(Int)
    }

    /// What the resolver holds between two clicks: the selection Finder has, and one stored anchor, read
    /// back from `Outcome.anchor` after every ⇧ Shift click exactly as `ShiftClickResolver` reads it.
    private struct Finder {
        let model = LayoutModel(items: Layouts.filled(rows: 12, columns: 1), fallbackFlow: .rowsFromLeft)
        var selection: Set<Int> = []
        var anchor: Int?

        mutating func apply(_ step: Step) {
            switch step {
            case .click(let row):
                selection = [row - 1]
                anchor = row - 1
            case .command(let row):
                if selection.contains(row - 1) { selection.remove(row - 1) } else { selection.insert(row - 1) }
                anchor = row - 1
            case .select(let row):
                selection.insert(row - 1)
            case .shift(let row):
                let from = model.effectiveAnchor(stored: anchor, selection: Array(selection)) ?? model.firstItem!
                let outcome = model.shiftClick(from: from, selection: Array(selection), target: row - 1)!
                selection = Set(outcome.selection)
                anchor = outcome.anchor
            }
        }

        var rows: Set<Int> { Set(selection.map { $0 + 1 }) }
    }

    /// Every step with the selection Appendix A recorded after it, where it recorded one.
    private func replay(_ name: String, _ steps: [(Step, [Int]?)]) -> Finder {
        var finder = Finder()
        for (number, entry) in steps.enumerated() {
            finder.apply(entry.0)
            if let expected = entry.1 {
                XCTAssertEqual(finder.rows, Set(expected), "\(name), step \(number + 1)")
            }
        }
        return finder
    }

    func testTheMeasuredSequencesAreReproducedWithTheAnchorFedBack() {
        // S1 and S2: a ⌘ Command click moves the anchor, and three ⇧ Shift clicks are then measured from it.
        _ = replay("S1+S2", [(.click(1), [1]), (.shift(3), [1, 2, 3]), (.command(5), [1, 2, 3, 5]),
                             (.shift(7), [1, 2, 3, 5, 6, 7]), (.shift(6), [1, 2, 3, 5, 6]),
                             (.shift(9), [1, 2, 3, 5, 6, 7, 8, 9]), (.shift(4), [1, 2, 3, 4, 5])])
        // S4, both endings: the anchor deselected by ⌘ Command, the stand-in is the first selected row after it.
        _ = replay("S4 ⇧2", [(.click(1), [1]), (.shift(5), [1, 2, 3, 4, 5]), (.command(3), [1, 2, 4, 5]),
                             (.shift(2), [2, 3, 4])])
        _ = replay("S4 ⇧8", [(.click(1), [1]), (.shift(5), [1, 2, 3, 4, 5]), (.command(3), [1, 2, 4, 5]),
                             (.shift(8), [1, 2, 4, 5, 6, 7, 8])])
        // S9: a ⇧ Shift click back onto the anchor leaves exactly the anchor.
        _ = replay("S9", [(.click(3), [3]), (.shift(6), [3, 4, 5, 6]), (.shift(3), [3])])
        // S13: nothing selected, the click is measured from the first row.
        _ = replay("S13", [(.click(4), [4]), (.command(4), []), (.shift(7), [1, 2, 3, 4, 5, 6, 7])])
        // S14: two runs, the range touching one and then both.
        _ = replay("S14", [(.click(1), [1]), (.shift(3), [1, 2, 3]), (.command(8), [1, 2, 3, 8]),
                           (.shift(10), [1, 2, 3, 8, 9, 10]), (.shift(6), [1, 2, 3, 6, 7, 8]),
                           (.shift(2), [2, 3, 4, 5, 6, 7, 8])])
        // W, as Appendix A measured it: the ⇧ Shift click on 6 is measured from the stand-in 4, and the anchor
        // moves there; row 3 is then selected without a click, so the anchor stays at 4, and the ⇧ Shift click
        // on 1 replaces the run 1...6 with 1...4. Had the anchor stayed at 3, it would have left {1, 2, 3}.
        let w = replay("W", [(.click(1), [1]), (.shift(5), [1, 2, 3, 4, 5]), (.command(3), [1, 2, 4, 5]),
                             (.shift(6), [1, 2, 4, 5, 6])])
        XCTAssertEqual(w.anchor, 3, "W: after the ⇧ Shift click on 6 the anchor is the stand-in, row 4")
        var finder = w
        finder.apply(.select(3))
        XCTAssertEqual(finder.rows, [1, 2, 3, 4, 5, 6], "W: row 3 selected without a click")
        XCTAssertEqual(finder.anchor, 3, "W: a selection made without a click leaves the anchor alone")
        finder.apply(.shift(1))
        XCTAssertEqual(finder.rows, [1, 2, 3, 4], "W: measured from 4, the run 1...6 is replaced by 1...4")
    }
}
