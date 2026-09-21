import CoreGraphics
import XCTest
import ShiftPickCore

/// The rule for a range whose anchor is gone: the selected file **farthest from the target**. It is one
/// rule, and it reproduces both of the cases the specification names, plus the one it does not.
final class AnchorTests: XCTestCase {
    private func grid() -> LayoutModel {
        LayoutModel(items: Layouts.filled(rows: 4, columns: 6), fallbackFlow: .rowsFromLeft)
    }

    func testATargetAfterTheSelectionMeasuresFromItsStart() {
        // 5 to 8 selected, the click on 14: the range starts at the selected item nearest its start.
        XCTAssertEqual(grid().derivedAnchor(target: 14, selection: [5, 6, 7, 8]), 5)
    }

    func testATargetBeforeTheSelectionMeasuresFromItsEnd() {
        XCTAssertEqual(grid().derivedAnchor(target: 2, selection: [5, 6, 7, 8]), 8)
    }

    /// Neither case in the specification covers a click inside the selection. The same rule answers it,
    /// and it gives the widest range the selection can justify.
    func testATargetInsideTheSelectionMeasuresFromTheFarEnd() {
        XCTAssertEqual(grid().derivedAnchor(target: 6, selection: [5, 6, 7, 8, 9, 10, 11, 12]), 12)
    }

    func testOneSelectedFileIsTheAnchor() {
        XCTAssertEqual(grid().derivedAnchor(target: 20, selection: [3]), 3)
    }

    func testTheTargetItselfSelectedGivesARangeOfOne() {
        let model = grid()
        let anchor = try? XCTUnwrap(model.derivedAnchor(target: 9, selection: [9]))
        XCTAssertEqual(anchor, 9)
        XCTAssertEqual(model.range(from: 9, to: 9), [9])
    }

    func testNothingSelectedMeansNoAnchor() {
        XCTAssertNil(grid().derivedAnchor(target: 4, selection: []))
    }

    func testAStackIsNeverAnAnchor() {
        var items = Layouts.filled(rows: 1, columns: 5, pitch: Layouts.desktopPitch,
                                   side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        let model = LayoutModel(items: items, fallbackFlow: .columnsFromRight)
        XCTAssertNil(model.derivedAnchor(target: 4, selection: [0]))
        XCTAssertEqual(model.derivedAnchor(target: 4, selection: [0, 1]), 1)
    }

    func testAnIndexThatIsNotAnItemIsIgnored() {
        XCTAssertEqual(grid().derivedAnchor(target: 10, selection: [99, 2, -4]), 2)
    }

    func testATargetThatIsNotAnItemHasNoAnchor() {
        XCTAssertNil(grid().derivedAnchor(target: 99, selection: [1, 2]))
    }

    /// With nothing arranged there is no flow order to count along, so distance is measured across the
    /// screen instead.
    func testAHandPlacedAnchorIsTheFarthestIconOnScreen() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0),
                     Layouts.item(x: 317, y: 254, axOrder: 1),
                     Layouts.item(x: 1_200, y: 690, axOrder: 2),
                     Layouts.item(x: 640, y: 111, axOrder: 3)]
        let model = LayoutModel(items: items, fallbackFlow: .rowsFromLeft)
        XCTAssertEqual(model.kind, .handPlaced)
        XCTAssertEqual(model.derivedAnchor(target: 0, selection: [1, 2, 3]), 2)
    }

    func testTiesKeepTheFirstOfTheSelectionAsItWasRead() {
        // Two selected files exactly as far from the target in flow order.
        let model = grid()
        XCTAssertEqual(model.derivedAnchor(target: 10, selection: [8, 12]), 8)
        XCTAssertEqual(model.derivedAnchor(target: 10, selection: [12, 8]), 12)
    }

    /// The whole reason the rule exists: a range measured from a derived anchor is still total and still
    /// symmetric.
    func testADerivedAnchorStillGivesATotalRange() {
        let model = grid()
        for target in 0..<24 {
            guard let anchor = model.derivedAnchor(target: target, selection: [4, 5, 6]) else {
                return XCTFail("no anchor for \(target)")
            }
            guard let range = model.range(from: anchor, to: target) else {
                return XCTFail("no range for \(target)")
            }
            XCTAssertTrue(range.contains(target))
            XCTAssertTrue(range.contains(anchor))
        }
    }
}
