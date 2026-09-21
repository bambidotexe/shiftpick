import CoreGraphics
import XCTest
@testable import ShiftPickCore

/// The clustering the classification is built on: rows and columns out of nothing but positions.
final class LatticeTests: XCTestCase {
    func testValuesOnOneLineAreOneCluster() {
        let (index, count) = Lattice.cluster([250, 250, 250, 250], tolerance: 58)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(index, [0, 0, 0, 0])
    }

    func testAGapWiderThanTheToleranceOpensANewCluster() {
        let (index, count) = Lattice.cluster([250, 252, 366, 368], tolerance: 58)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(index, [0, 0, 1, 1])
    }

    func testClustersAreNumberedFromTheSmallestValueWhateverOrderTheyArriveIn() {
        let (index, _) = Lattice.cluster([366, 250, 482, 252], tolerance: 58)
        XCTAssertEqual(index, [1, 0, 2, 0])
    }

    func testEqualValuesAlwaysLandTogether() {
        let (index, count) = Lattice.cluster([100, 100, 100], tolerance: 0)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(index, [0, 0, 0])
    }

    func testNothingClustersToNothing() {
        let (index, count) = Lattice.cluster([], tolerance: 10)
        XCTAssertEqual(count, 0)
        XCTAssertTrue(index.isEmpty)
    }

    func testAGridIsMeasuredAtItsRealPitch() {
        let lattice = Lattice.build(Layouts.filled(rows: 3, columns: 4))
        XCTAssertEqual(lattice.rowCount, 3)
        XCTAssertEqual(lattice.columnCount, 4)
        XCTAssertEqual(lattice.rowPitch, Layouts.windowPitch.height, accuracy: 0.5)
        XCTAssertEqual(lattice.columnPitch, Layouts.windowPitch.width, accuracy: 0.5)
        XCTAssertTrue(lattice.isTight)
    }

    func testOneLineLeavesThePitchUnmeasuredAndTheLatticeTight() {
        let lattice = Lattice.build(Layouts.filled(rows: 1, columns: 5))
        XCTAssertEqual(lattice.rowCount, 1)
        XCTAssertEqual(lattice.columnCount, 5)
        XCTAssertTrue(lattice.isTight)
    }

    /// Single-linkage clustering walks from one hand-placed icon to the next and can chain a whole scatter
    /// into one "line". That is what `isTight` is for.
    func testASmearedClusterIsNotTight() {
        let items = (0..<12).map { Layouts.item(x: 100 + CGFloat($0) * 9, y: 100 + CGFloat($0) * 11,
                                                axOrder: $0) }
        XCTAssertFalse(Lattice.build(items).isTight)
    }

    func testTheMedianOfAnEvenNumberOfValuesIsTheMiddleOfTheTwo() {
        XCTAssertEqual(Lattice.median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(Lattice.median([5, 1, 3]), 3)
        XCTAssertNil(Lattice.median([]))
    }
}
