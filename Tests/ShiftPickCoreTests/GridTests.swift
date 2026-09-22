import CoreGraphics
import XCTest
@testable import ShiftPickCore

/// One cluster fitted with rows and columns and read along its rows, or refused as a scatter.
final class GridTests: XCTestCase {
    private let pitch = Layouts.windowPitch.width

    func testAnExactGridReadsAlongItsRowsFromTheLeft() {
        let items = Layouts.filled(rows: 2, columns: 3)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    func testARightToLeftLayoutReadsEachRowFromTheRight() {
        let items = Layouts.filled(rows: 2, columns: 3)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: false)
        XCTAssertEqual(grid.order, [2, 1, 0, 5, 4, 3])
    }

    func testAHoleIsSkippedInTheOrder() {
        var items = Layouts.filled(rows: 2, columns: 3)
        items.remove(at: 1)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4])
    }

    /// Up to a quarter of a pitch off the line either way is a hand-placed row, not a scatter.
    func testAWobblyGridIsStillAGrid() {
        let jitter: [(CGFloat, CGFloat)] = [(-20, 15), (10, -25), (25, 20), (-15, -10), (0, 28), (18, -18)]
        let items = zip(Layouts.filled(rows: 2, columns: 3, pitch: Layouts.desktopPitch, side: Layouts.desktopSide), jitter)
            .enumerated().map { order, pair in
                LayoutItem(frame: pair.0.frame.offsetBy(dx: pair.1.0, dy: pair.1.1), axOrder: order)
            }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: Layouts.desktopPitch.width,
                            leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    /// A row wider than half a pitch is a scatter chained together, and its order is by top edge then left.
    func testASmearedClusterIsAScatterOrderedTopToBottom() {
        let items = (0..<6).map { Layouts.item(x: 100 + CGFloat($0) * 40, y: 100 + CGFloat($0) * 30, axOrder: 5 - $0) }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: 120, leadingIsLeft: true)
        XCTAssertFalse(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    func testTwoIconsInOneCellKeepTheirAccessibilityOrder() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 3), Layouts.item(x: 104, y: 98, axOrder: 1),
                     Layouts.item(x: 216, y: 100, axOrder: 2)]
        let grid = Grid.fit(members: [0, 1, 2], items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [1, 0, 2])
    }

    func testOneIconIsAGridOfOne() {
        let items = [Layouts.item(x: 300, y: 200)]
        let grid = Grid.fit(members: [0], items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0])
        XCTAssertEqual(grid.top, 200)
        XCTAssertEqual(grid.leading, 300)
    }

    // MARK: - What a real hand-placed view does to the rules

    /// A Desktop with *Snap to Grid*, icons dropped into whichever cells came to hand, the rest empty.
    /// Reading is row by row across the holes, whatever order Accessibility lists them in:
    ///
    ///     . . A . . . . .
    ///     . . . . . . B C
    ///     D . . . . . . .
    ///     E . . . . F G H
    func testASnappedDesktopWithHolesReadsRowByRowAcrossTheHoles() {
        let cells: [(row: Int, column: Int)] = [(0, 2), (1, 6), (1, 7), (2, 0), (3, 0), (3, 5), (3, 6), (3, 7)]
        let items = cells.enumerated().map { order, cell in
            Layouts.item(x: 100 + CGFloat(cell.column) * 122, y: 100 + CGFloat(cell.row) * 122,
                         axOrder: 7 - order, side: Layouts.desktopSide)
        }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: 122, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5, 6, 7])
    }

    /// A Desktop grid tidied by hand without snapping, every icon up to twenty points off its cell: a grid,
    /// read in cell order, for every one of forty wobbles. Detection breaks at a quarter pitch: the
    /// designed worst case below holds at ±30 and fails at ±31 on the Desktop's 122-point pitch; under a
    /// random wobble the first of these forty seeds falls to a scatter at ±28 and most of them from ±34,
    /// and the order is never wrong while the verdict is a grid.
    func testAGridTidiedByHandIsAGridReadInCellOrderWhateverTheWobble() {
        for seed in 1...40 {
            let items = Layouts.wobbled(rows: 4, columns: 5, amplitude: 20, seed: UInt64(seed))
            let grid = Grid.fit(members: Array(items.indices), items: items,
                                pitch: Clusters.build(items).pitch, leadingIsLeft: true)
            XCTAssertTrue(grid.isGrid, "seed \(seed)")
            XCTAssertEqual(grid.order, Array(0..<20), "seed \(seed)")
        }
    }

    /// Where the tolerance ends, exactly. In the first row one icon is pushed down by the amplitude and
    /// its neighbour up by it, so the row is two amplitudes wide; the icon below the first is pushed up
    /// by it, so the gap to the next row is a pitch less two amplitudes. Both measure against half a
    /// pitch, which is why a quarter pitch is the most a hand may wobble: 30 points holds on the Desktop's
    /// 122, 31 does not.
    func testTheWobbleCliffIsAQuarterPitch() {
        func verdict(amplitude: CGFloat) -> Bool {
            var items = Layouts.filled(rows: 3, columns: 4, pitch: Layouts.desktopPitch,
                                       side: Layouts.desktopSide)
            items[1] = LayoutItem(frame: items[1].frame.offsetBy(dx: 0, dy: amplitude), axOrder: 1)
            items[2] = LayoutItem(frame: items[2].frame.offsetBy(dx: 0, dy: -amplitude), axOrder: 2)
            items[5] = LayoutItem(frame: items[5].frame.offsetBy(dx: 0, dy: -amplitude), axOrder: 5)
            return Grid.fit(members: Array(items.indices), items: items,
                            pitch: Clusters.build(items).pitch, leadingIsLeft: true).isGrid
        }
        XCTAssertTrue(verdict(amplitude: 30))
        XCTAssertFalse(verdict(amplitude: 31))
    }

    /// Five icons each one step right and one step down from the last. Every icon is its own row and its
    /// own column, so nothing in the layout says which comes first: not a grid, however even the steps,
    /// and a range across it is the rubber band. The order it keeps is by top edge.
    func testAStaircaseIsAScatter() {
        let items = (0..<5).map {
            Layouts.item(x: 100 + CGFloat($0) * 116, y: 100 + CGFloat($0) * 116, axOrder: 4 - $0)
        }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertFalse(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4])
    }

    /// The rule that refuses the staircase must not refuse a grid with holes. A checkerboard shares rows
    /// and never a column; three icons of which two share a row share nothing else. Both are grids.
    func testAGridWithHolesIsAGridAsSoonAsTwoIconsShareALine() {
        let checkerboard = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 216, y: 216, axOrder: 1),
                            Layouts.item(x: 332, y: 100, axOrder: 2), Layouts.item(x: 448, y: 216, axOrder: 3)]
        let board = Grid.fit(members: [0, 1, 2, 3], items: checkerboard, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(board.isGrid)
        XCTAssertEqual(board.order, [0, 2, 1, 3])

        let three = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 332, y: 100, axOrder: 1),
                     Layouts.item(x: 216, y: 216, axOrder: 2)]
        XCTAssertTrue(Grid.fit(members: [0, 1, 2], items: three, pitch: pitch, leadingIsLeft: true).isGrid)
    }

    /// Two icons are a grid whatever their shape, a diagonal included: there is nothing to misread.
    func testTwoIconsAreAlwaysAGrid() {
        let diagonal = [Layouts.item(x: 300, y: 300, axOrder: 1), Layouts.item(x: 100, y: 100, axOrder: 0)]
        let grid = Grid.fit(members: [0, 1], items: diagonal, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [1, 0])
    }

    /// Four icons in a row, listed backwards by Accessibility, one and a half pitches apart and then two:
    /// icons a pitch and a half apart still chain into one row (rule 2's link, `K.gridLinkPitches`), but two
    /// pitches is the gap that separates two groups — an empty column or more between them — so the fourth
    /// icon is a cluster of its own and a range to it is the rubber band, not a read across the row. Proven
    /// through the engine, at its own measured pitch: the icons sit 116, 174 and 232 apart at the true
    /// 116-point pitch, the pass samples the first two gaps from both of their ends, 116, 116, 174 and 174,
    /// whose median is 145, and the third gap is beyond the reach and gives nothing. `Clusters.build`
    /// answers two clusters, the first three icons together and the fourth alone; the first three, read at
    /// that pitch, are one row left to right.
    func testARowWithGapsOfOneAndAHalfPitchesStaysOneRowAndAGapOfTwoBreaksIt() {
        let offsets: [CGFloat] = [0, 116, 116 + 174, 116 + 174 + 232]
        let items = offsets.enumerated().map { order, offset in
            Layouts.item(x: 100 + offset, y: 100, axOrder: 3 - order)
        }
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.index[0], clusters.index[1])
        XCTAssertEqual(clusters.index[1], clusters.index[2])
        XCTAssertNotEqual(clusters.index[2], clusters.index[3])

        let row = items.indices.filter { clusters.index[$0] == clusters.index[0] }
        let grid = Grid.fit(members: row, items: items, pitch: clusters.pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2])
    }

    /// One icon dropped between two columns, hugging the first row (48 points below it, 72 above the
    /// next). It reads in that row, between the two columns, and the grid around it stays a grid: a
    /// column two icons wide changes nothing about which icon follows which along a row.
    func testAStrayBetweenTwoColumnsReadsInItsRowAndLeavesTheGridAGrid() {
        var items = Layouts.filled(rows: 3, columns: 4, origin: CGPoint(x: 100, y: 100),
                                   pitch: CGSize(width: 120, height: 120))
        items.append(Layouts.item(x: 160, y: 148, axOrder: 12))   // centre (192, 180); columns at 132 and 252
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: 120, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    }

    /// Two rows of icons pushed together until they nearly touch, the second row offset by half a step:
    /// the rows are plain to see and read along, although no two icons share a column.
    func testRowsPackedTighterThanThePitchAreStillRows() {
        var items = (0..<5).map { Layouts.item(x: 100 + CGFloat($0) * 70, y: 100, axOrder: $0) }
        items += (0..<4).map { Layouts.item(x: 135 + CGFloat($0) * 70, y: 216, axOrder: 5 + $0) }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, Array(0..<9))
    }

    /// Four icons dropped on top of one another in one cell of a grid: they read where the cell is, in the
    /// order Accessibility lists them, and the rest of the grid reads around them.
    func testAPileInOneCellReadsInAccessibilityOrderWhereTheCellIs() {
        var items = Layouts.filled(rows: 2, columns: 3)
        for stacked in 0..<4 {
            items.append(Layouts.item(x: 540 + 116 + CGFloat(stacked) * 3, y: 250 - CGFloat(stacked) * 2,
                                      axOrder: 10 - stacked))
        }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 9, 8, 7, 6, 2, 3, 4, 5])
    }

    /// Finder reports an icon's box and not its cell, so a wrapping name never changes a frame; should a
    /// frame ever be taller, its centre moves by half the difference, well inside a quarter pitch.
    func testFramesOfDifferentHeightsStillReadAsOneGrid() {
        var items = Layouts.filled(rows: 3, columns: 4)
        items.remove(at: 5)
        for index in items.indices where index.isMultiple(of: 2) {
            let frame = items[index].frame
            items[index] = LayoutItem(frame: CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                                    height: frame.height + 20), axOrder: items[index].axOrder)
        }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, Array(0..<11))
    }

    /// A scatter reads by top edge, and two icons with the same top edge from the leading edge: the left
    /// one first, or the right one first under a right-to-left layout. Three icons stepping down twenty
    /// points at a time chain into a row forty wide, over the tolerance of thirty for a pitch of sixty.
    func testAScatterReadsByTopEdgeThenFromTheLeadingEdge() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 400, y: 100, axOrder: 1),
                     Layouts.item(x: 250, y: 120, axOrder: 2), Layouts.item(x: 350, y: 140, axOrder: 3),
                     Layouts.item(x: 300, y: 500, axOrder: 4)]
        let fromTheLeft = Grid.fit(members: [0, 1, 2, 3, 4], items: items, pitch: 60, leadingIsLeft: true)
        XCTAssertFalse(fromTheLeft.isGrid)
        XCTAssertEqual(fromTheLeft.order, [0, 1, 2, 3, 4])
        let fromTheRight = Grid.fit(members: [0, 1, 2, 3, 4], items: items, pitch: 60, leadingIsLeft: false)
        XCTAssertFalse(fromTheRight.isGrid)
        XCTAssertEqual(fromTheRight.order, [1, 0, 2, 3, 4])
    }

    /// Accessibility lists the icons in whatever order it likes; the reading order is the same order of
    /// the same icons.
    func testTheOrderIsTheSameWhateverOrderTheItemsArriveIn() {
        let items = Layouts.wobbled(rows: 3, columns: 4, amplitude: 15, seed: 21)
        let straight = Grid.fit(members: Array(items.indices), items: items, pitch: 122, leadingIsLeft: true)
        var generator = SeededGenerator(seed: 8)
        let shuffledOrder = items.indices.shuffled(using: &generator)
        let shuffledItems = shuffledOrder.map { items[$0] }
        let shuffled = Grid.fit(members: Array(shuffledItems.indices), items: shuffledItems, pitch: 122,
                                leadingIsLeft: true)
        XCTAssertEqual(shuffled.isGrid, straight.isGrid)
        XCTAssertEqual(shuffled.order.map { shuffledOrder[$0] }, straight.order)
    }

    func testNothingFitsToNothing() {
        let grid = Grid.fit(members: [], items: [], pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.order.isEmpty)
        XCTAssertTrue(grid.isGrid)
    }

    /// Five thousand icons in one cluster, in the shape that costs most: a scatter, which is sorted whole.
    func testFiveThousandIconsInOneClusterFitInWellUnderASecond() {
        var generator = SeededGenerator(seed: 4)
        let items = (0..<5_000).map { order in
            Layouts.item(x: CGFloat(Int.random(in: 0...3_000, using: &generator)),
                         y: CGFloat(Int.random(in: 0...2_000, using: &generator)), axOrder: order)
        }
        let started = Date()
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: 72, leadingIsLeft: true)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 1, "5,000 icons took \(elapsed) s")
        XCTAssertEqual(grid.order.count, 5_000)
        XCTAssertEqual(Set(grid.order).count, 5_000)
    }

    func testTheLeadingEdgeOfARightToLeftClusterIsItsRightEdgeNegated() {
        let items = Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 50))
        let grid = Grid.fit(members: [0, 1], items: items, pitch: pitch, leadingIsLeft: false)
        // The right edge of the rightmost frame is 100 + 116 + 64; negated so that a smaller key sorts first.
        XCTAssertEqual(grid.leading, -(100 + 116 + 64))
    }
}
