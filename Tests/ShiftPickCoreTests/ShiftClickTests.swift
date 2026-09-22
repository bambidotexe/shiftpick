import XCTest
import ShiftPickCore

/// AppKit's selection model, replayed from the measurements in the spec's Appendix A. Rows are 1-based in
/// the spec and 0-based here; `r(a, b)` is the closed range a...b as an array.
final class ShiftClickTests: XCTestCase {
    private func r(_ a: Int, _ b: Int) -> [Int] { Array(a...b) }

    /// One measured state: the selection and the anchor before, and the selection after a ⇧ Shift click on
    /// each of the twelve rows.
    private struct Measured {
        let name: String
        let selection: [Int]
        let anchor: Int?
        let after: [[Int]]   // index t-1 holds the result of a click on row t
    }

    private lazy var measured: [Measured] = [
        Measured(name: "A", selection: r(1, 5), anchor: 1,
                 after: (1...12).map { r(1, $0) }),
        Measured(name: "B", selection: [2, 5, 8], anchor: 8,
                 after: [r(1, 8), r(2, 8), r(2, 8), [2] + r(4, 8), [2] + r(5, 8), [2] + r(5, 8), [2, 5, 7, 8],
                         [2, 5, 8], [2, 5, 8, 9], [2, 5] + r(8, 10), [2, 5] + r(8, 11), [2, 5] + r(8, 12)]),
        Measured(name: "C", selection: [1, 2, 4, 5], anchor: 3,
                 after: [r(1, 4), [2, 3, 4], r(1, 4), [1, 2, 4], [1, 2, 4, 5], [1, 2] + r(4, 6), [1, 2] + r(4, 7),
                         [1, 2] + r(4, 8), [1, 2] + r(4, 9), [1, 2] + r(4, 10), [1, 2] + r(4, 11), [1, 2] + r(4, 12)]),
        Measured(name: "E", selection: [3, 7, 8, 9], anchor: 9,
                 after: [r(1, 9), r(2, 9), r(3, 9), r(3, 9), [3] + r(5, 9), [3] + r(6, 9), [3, 7, 8, 9], [3, 8, 9],
                         [3, 9], [3, 9, 10], [3, 9, 10, 11], [3] + r(9, 12)]),
        Measured(name: "F", selection: [3, 7], anchor: 3,
                 after: [[1, 2, 3, 7], [2, 3, 7], [3, 7], [3, 4, 7], [3, 4, 5, 7], r(3, 7), r(3, 7), r(3, 8),
                         r(3, 9), r(3, 10), r(3, 11), r(3, 12)]),
        Measured(name: "G", selection: [6, 7, 8], anchor: 5,
                 after: [r(1, 6), r(2, 6), r(3, 6), r(4, 6), [5, 6], [6], [6, 7], [6, 7, 8], r(6, 9), r(6, 10),
                         r(6, 11), r(6, 12)]),
        Measured(name: "H", selection: [5, 6, 8], anchor: 7,
                 after: [r(1, 8), r(2, 8), r(3, 8), r(4, 8), r(5, 8), [6, 7, 8], r(5, 8), [5, 6, 8], [5, 6, 8, 9],
                         [5, 6] + r(8, 10), [5, 6] + r(8, 11), [5, 6] + r(8, 12)]),
        Measured(name: "I", selection: r(6, 10), anchor: 10,
                 after: [r(1, 10), r(2, 10), r(3, 10), r(4, 10), r(5, 10), r(6, 10), r(7, 10), r(8, 10), [9, 10],
                         [10], [10, 11], [10, 11, 12]]),
        Measured(name: "K", selection: [9], anchor: 4,
                 after: [r(1, 9), r(2, 9), r(3, 9), r(4, 9), r(5, 9), r(6, 9), r(7, 9), [8, 9], [9], [9, 10],
                         [9, 10, 11], r(9, 12)]),
        Measured(name: "L", selection: [2], anchor: 9,
                 after: [[1, 2], [2], [2, 3], r(2, 4), r(2, 5), r(2, 6), r(2, 7), r(2, 8), r(2, 9), r(2, 10),
                         r(2, 11), r(2, 12)]),
        Measured(name: "M", selection: [4, 5, 6, 9, 11], anchor: 10,
                 after: [r(1, 11), r(2, 11), r(3, 11), r(4, 11), r(5, 11), r(6, 11), r(4, 11), [4, 5, 6] + r(8, 11),
                         [4, 5, 6, 9, 10, 11], [4, 5, 6, 9, 10, 11], [4, 5, 6, 9, 11], [4, 5, 6, 9, 11, 12]]),
        Measured(name: "N", selection: [1, 2, 3, 6, 8], anchor: 8,
                 after: [r(1, 8), r(2, 8), r(3, 8), r(1, 8), [1, 2, 3] + r(5, 8), [1, 2, 3, 6, 7, 8], [1, 2, 3, 6, 7, 8],
                         [1, 2, 3, 6, 8], [1, 2, 3, 6, 8, 9], [1, 2, 3, 6] + r(8, 10), [1, 2, 3, 6] + r(8, 11),
                         [1, 2, 3, 6] + r(8, 12)]),
        Measured(name: "P", selection: [2, 5], anchor: 9,
                 after: [r(1, 5), r(2, 5), r(2, 5), [2, 4, 5], [2, 5], [2, 5, 6], [2] + r(5, 7), [2] + r(5, 8),
                         [2] + r(5, 9), [2] + r(5, 10), [2] + r(5, 11), [2] + r(5, 12)]),
        Measured(name: "Q", selection: [2, 7], anchor: 4,
                 after: [r(1, 7), r(2, 7), r(2, 7), [2] + r(4, 7), [2] + r(5, 7), [2, 6, 7], [2, 7], [2, 7, 8],
                         [2] + r(7, 9), [2] + r(7, 10), [2] + r(7, 11), [2] + r(7, 12)]),
        Measured(name: "U", selection: [1, 3], anchor: 11,
                 after: [[1, 2, 3], [1, 2, 3], [1, 3], [1, 3, 4], [1] + r(3, 5), [1] + r(3, 6), [1] + r(3, 7),
                         [1] + r(3, 8), [1] + r(3, 9), [1] + r(3, 10), [1] + r(3, 11), [1] + r(3, 12)]),
        Measured(name: "V", selection: [10, 12], anchor: 2,
                 after: [r(1, 10) + [12], r(2, 10) + [12], r(3, 10) + [12], r(4, 10) + [12], r(5, 10) + [12],
                         r(6, 10) + [12], r(7, 10) + [12], r(8, 10) + [12], [9, 10, 12], [10, 12], [10, 11, 12],
                         [10, 11, 12]]),
    ]

    private func zeroBased(_ rows: [Int]) -> [Int] { rows.map { $0 - 1 } }

    func testEveryMeasuredStateIsReproduced() {
        for state in measured {
            let selection = Set(zeroBased(state.selection))
            let anchor = state.anchor.map { $0 - 1 }
            let from = ShiftClick.standIn(anchor: anchor, selection: selection)
            XCTAssertNotNil(from, state.name)
            for target in 0..<12 {
                let result = ShiftClick.resolve(anchor: from!, selection: selection, target: target, count: 12)
                XCTAssertEqual(result, zeroBased(state.after[target]), "\(state.name), click on row \(target + 1)")
            }
        }
    }

    // MARK: - The stand-in

    func testASelectedAnchorStandsForItself() {
        XCTAssertEqual(ShiftClick.standIn(anchor: 4, selection: [1, 4, 7]), 4)
    }

    func testADeselectedAnchorIsStoodInByTheFirstSelectedPositionAfterIt() {
        // {2,7} with anchor 4: 2 is nearer, 7 is after. Measured: 7.
        XCTAssertEqual(ShiftClick.standIn(anchor: 3, selection: [1, 6]), 6)
        XCTAssertEqual(ShiftClick.standIn(anchor: 2, selection: [0, 1, 3, 4]), 3)
    }

    func testElseByTheLastSelectedPositionBeforeIt() {
        XCTAssertEqual(ShiftClick.standIn(anchor: 8, selection: [1, 4]), 4)
    }

    func testNoAnchorCountsAsOneBeforeEverything() {
        XCTAssertEqual(ShiftClick.standIn(anchor: nil, selection: [2, 3, 4]), 2)
    }

    func testNothingSelectedHasNoStandIn() {
        XCTAssertNil(ShiftClick.standIn(anchor: 5, selection: []))
        XCTAssertNil(ShiftClick.standIn(anchor: nil, selection: []))
    }

    // MARK: - The run rule, in words

    func testARunTheRangeTouchesGoesWhole() {
        // {2,5,6,7,8} anchor 8, click 10: the run 5...8 goes, 5 to 7 with it; {2} stays.
        XCTAssertEqual(ShiftClick.resolve(anchor: 7, selection: [1, 4, 5, 6, 7], target: 9, count: 12), [1, 7, 8, 9])
    }

    func testARunTheRangeDoesNotTouchStays() {
        XCTAssertEqual(ShiftClick.resolve(anchor: 4, selection: [0, 1, 2, 4], target: 6, count: 12), [0, 1, 2, 4, 5, 6])
    }

    func testARunAdjacentToTheRangeButNotInsideItStays() {
        // {2,5,8} anchor 8, click 6: 5 is next to 6 and is not touched.
        XCTAssertEqual(ShiftClick.resolve(anchor: 7, selection: [1, 4, 7], target: 5, count: 12), [1, 4, 5, 6, 7])
    }

    func testTheRangeIsSymmetricAndTotal() {
        for anchor in 0..<12 {
            for target in 0..<12 {
                let one = ShiftClick.resolve(anchor: anchor, selection: [0, 3, 4, 9], target: target, count: 12)
                let other = ShiftClick.resolve(anchor: target, selection: [0, 3, 4, 9], target: anchor, count: 12)
                XCTAssertEqual(one, other)
                XCTAssertTrue(one?.contains(anchor) == true && one?.contains(target) == true)
                XCTAssertEqual(one, one?.sorted())
            }
        }
    }

    func testAPositionOutsideTheOrderIsRefused() {
        XCTAssertNil(ShiftClick.resolve(anchor: 12, selection: [], target: 3, count: 12))
        XCTAssertNil(ShiftClick.resolve(anchor: 0, selection: [], target: -1, count: 12))
        XCTAssertEqual(ShiftClick.resolve(anchor: 0, selection: [40], target: 2, count: 12), [0, 1, 2],
                       "a selected position outside the order is dropped, never kept")
    }
}
