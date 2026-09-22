import CoreGraphics
import XCTest
import ShiftPickCore

/// Where a ⇧ Shift click is measured from (`docs/functional.md` §2.1): the stored anchor while it is
/// selected, else a stand-in named in reading order, else nothing.
final class StandInTests: XCTestCase {
    private func grid() -> LayoutModel {
        LayoutModel(items: Layouts.filled(rows: 4, columns: 6), fallbackFlow: .rowsFromLeft)
    }

    func testASelectedAnchorIsUsed() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 5, selection: [5, 6, 7, 8]), 5)
    }

    func testADeselectedAnchorIsStoodInByTheFirstSelectedIconAfterIt() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 3, selection: [1, 2, 4, 5]), 4)
        XCTAssertEqual(grid().effectiveAnchor(stored: 3, selection: [1, 9]), 9)
    }

    func testElseByTheLastSelectedIconBeforeIt() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 22, selection: [3, 9]), 9)
    }

    func testNoAnchorMeasuresFromTheFirstSelectedIconInReadingOrder() {
        XCTAssertEqual(grid().effectiveAnchor(stored: nil, selection: [8, 5, 6, 7]), 5)
    }

    func testNothingSelectedIsNoAnchor() {
        XCTAssertNil(grid().effectiveAnchor(stored: 4, selection: []))
        XCTAssertNil(grid().effectiveAnchor(stored: nil, selection: []))
    }

    func testAStackIsNeitherAnAnchorNorACandidate() {
        var items = Layouts.filled(rows: 1, columns: 5, pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        let model = LayoutModel(items: items, fallbackFlow: .columnsFromRight)
        XCTAssertNil(model.effectiveAnchor(stored: 0, selection: [0]))
        XCTAssertEqual(model.effectiveAnchor(stored: 0, selection: [0, 1]), 1)
    }

    func testAnIndexThatIsNotAnItemIsIgnored() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 99, selection: [99, 2, -4]), 2)
    }

    /// Reading order runs down a sorted Desktop's columns, so "after" means further down the column and
    /// then into the next one to the left.
    func testTheOrderIsTheViewsOwn() {
        let items = Layouts.filled(rows: 7, columns: 3, count: 10, flow: .columnsFromRight,
                                   origin: CGPoint(x: 1166, y: 42), pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        let model = LayoutModel(items: items, fallbackFlow: .columnsFromRight)
        XCTAssertEqual(model.effectiveAnchor(stored: 2, selection: [1, 8]), 8)
    }

    /// Clusters follow one another in reading order, so a stand-in can be found in the next cluster; a
    /// range to it is then the rubber band, which is the caller's business.
    func testAStandInMayBeInAnotherCluster() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 160), firstAXOrder: 4)
        let model = LayoutModel(items: items, fallbackFlow: .rowsFromLeft)
        XCTAssertEqual(model.effectiveAnchor(stored: 2, selection: [5]), 5)
        XCTAssertEqual(model.effectiveAnchor(stored: 6, selection: [1]), 1)
    }

    func testTheFirstItemIsTheFirstFileInReadingOrder() {
        XCTAssertEqual(grid().firstItem, 0)
        var items = Layouts.filled(rows: 1, columns: 3, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        XCTAssertEqual(LayoutModel(items: items, fallbackFlow: .columnsFromRight).firstItem, 1)
        XCTAssertNil(LayoutModel(items: [], fallbackFlow: .rowsFromLeft).firstItem)
    }
}
