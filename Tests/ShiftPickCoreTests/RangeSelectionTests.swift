import CoreGraphics
import XCTest
import ShiftPickCore

/// Step 3 of the specification, layout by layout: what the selection maths classifies a set of icons as,
/// and what it puts between two of them.
///
/// Every test here is pure: frames in, indices out. The layouts are `Layouts`', built with the numbers
/// measured off a real Finder.
final class RangeSelectionTests: XCTestCase {
    private func model(_ items: [LayoutItem], _ flow: Flow = .rowsFromLeft) -> LayoutModel {
        LayoutModel(items: items, fallbackFlow: flow)
    }

    // MARK: - A perfect grid

    func testAPerfectGridIsArrangedAlongItsRows() {
        let model = model(Layouts.filled(rows: 4, columns: 6))
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        // Flow order is the order the items were built in.
        XCTAssertEqual((0..<24).map { model.flowPosition(of: $0) }, (0..<24).map { $0 })
    }

    func testARangeAcrossARowIsEverythingBetween() {
        let model = model(Layouts.filled(rows: 4, columns: 6))
        // 2 is the third item of the first row, 9 the fourth of the second.
        XCTAssertEqual(model.range(from: 2, to: 9)?.items, [2, 3, 4, 5, 6, 7, 8, 9])
    }

    func testARangeIsTheSameBothWaysRound() {
        let model = model(Layouts.filled(rows: 4, columns: 6))
        XCTAssertEqual(model.range(from: 17, to: 3)?.items, model.range(from: 3, to: 17)?.items)
    }

    func testAnchorEqualToTargetSelectsExactlyIt() {
        let model = model(Layouts.filled(rows: 4, columns: 6))
        XCTAssertEqual(model.range(from: 11, to: 11)?.items, [11])
    }

    // MARK: - A partial last row

    func testAPartialLastRowIsStillArranged() {
        // 21 items in a six-wide lattice: three full rows and a row of three.
        let model = model(Layouts.filled(rows: 4, columns: 6, count: 21))
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual(model.range(from: 19, to: 20)?.items, [19, 20])
        XCTAssertEqual(model.range(from: 0, to: 20)?.items.count, 21)
    }

    // MARK: - Holes and grids nobody arranged

    func testAGridWithAHoleIsOneHandPlacedGrid() {
        var items = Layouts.filled(rows: 3, columns: 4)
        items.remove(at: 5)   // the second item of the second row
        XCTAssertEqual(model(items).kind, .handPlaced(grids: 1, scatters: 0))
    }

    /// The owner's rule: the first icon of one row to the first of the next takes the whole row between.
    func testAHandPlacedGridReadsAlongItsRows() {
        var items = Layouts.filled(rows: 2, columns: 3)
        items.remove(at: 1)   // row 0 holds columns 0 and 2; row 1 is full
        let model = model(items)
        XCTAssertEqual(model.range(from: 0, to: 2), .ordered([0, 1, 2]))
        XCTAssertEqual(model.readingPosition(of: 1), 1)
        XCTAssertEqual(model.readingPosition(of: 2), 2)
    }

    func testAGridWithAHoleReadsAcrossTheHole() {
        var items = Layouts.filled(rows: 3, columns: 4)
        items.remove(at: 5)
        // Indices after the removal: row 0 is 0...3, row 1 is 4, 5, 6 (columns 0, 2, 3), row 2 is 7...10.
        XCTAssertEqual(model(items).range(from: 1, to: 5), .ordered([1, 2, 3, 4, 5]))
    }

    /// Three icons too far apart to share a grid are three grids of one, and a range between two of them is
    /// the rubber band, the rectangle their frames span.
    func testIconsTooFarApartForAGridGetTheRubberBand() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0),
                     Layouts.item(x: 900, y: 700, axOrder: 1),
                     Layouts.item(x: 100, y: 700, axOrder: 2)]
        let model = model(items)
        XCTAssertEqual(model.kind, .handPlaced(grids: 3, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 1), .band([0, 1, 2]))
        // A band with nothing inside it is still the two icons.
        XCTAssertEqual(model.range(from: 0, to: 2), .band([0, 2]))
    }

    /// Two groups whose rows do not line up: two grids. (Two groups on the very same rows, whatever the gap
    /// between them, fill one lattice and read as arranged, which is the lattice pass's rule and not this one.)
    func testTwoGridsFarApartGiveTheRubberBandBetweenThemAndAnOrderInsideEach() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 160), firstAXOrder: 4)
        let model = model(items)
        XCTAssertEqual(model.kind, .handPlaced(grids: 2, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 3), .ordered([0, 1, 2, 3]))
        // From the first grid's top-left to the second's bottom-right: the rectangle holds all eight.
        XCTAssertEqual(model.range(from: 0, to: 7), .band([0, 1, 2, 3, 4, 5, 6, 7]))
    }

    /// Two stray icons between the rows chain the rows together into one smear wider than half a pitch,
    /// so no grid makes sense and every range in the cluster is the band. (One stray alone, within half a
    /// pitch of a row, joins that row, and the cluster stays a grid, which is also right.)
    func testAClusterWithNoGridGetsTheRubberBand() {
        var items = Layouts.filled(rows: 3, columns: 4, origin: CGPoint(x: 100, y: 100),
                                   pitch: CGSize(width: 120, height: 120))
        items.append(Layouts.item(x: 160, y: 140, axOrder: 12))   // centre (192, 172), between rows 1 and 2
        items.append(Layouts.item(x: 280, y: 180, axOrder: 13))   // centre (312, 212)
        let model = model(items)
        XCTAssertEqual(model.kind, .handPlaced(grids: 0, scatters: 1))
        XCTAssertEqual(model.range(from: 0, to: 11), .band(Array(0...13)))
        XCTAssertEqual(model.range(from: 0, to: 1), .band([0, 1]))
    }

    /// The same wobble `GridTests` fits, through the whole model: the lattice pass refuses it (its rows are
    /// not exact), the clusters keep it together, and the grid reads along its rows.
    func testAWobblyHandPlacedGridIsStillAGrid() {
        let jitter: [(CGFloat, CGFloat)] = [(-20, 15), (10, -25), (25, 20), (-15, -10), (0, 28), (18, -18)]
        let base = Layouts.filled(rows: 2, columns: 3, pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        let items = zip(base, jitter).enumerated().map { order, pair in
            LayoutItem(frame: pair.0.frame.offsetBy(dx: pair.1.0, dy: pair.1.1), axOrder: order)
        }
        let model = model(items, .columnsFromRight)
        XCTAssertEqual(model.kind, .handPlaced(grids: 1, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 3), .ordered([0, 1, 2, 3]))
    }

    /// Clusters follow one another by top edge, then by leading edge, whatever order the items were listed
    /// in: the reading order runs through the higher cluster first.
    func testClustersReadByTopEdgeThenLeadingEdge() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 160), firstAXOrder: 4)
        let lower = model(items)
        XCTAssertEqual(lower.readingPosition(of: 4), 4)
        XCTAssertEqual(lower.readingPosition(of: 7), 7)
        // The same two grids with the second one higher on the screen: it comes first.
        var mirrored = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        mirrored += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 40), firstAXOrder: 4)
        let higher = model(mirrored)
        XCTAssertEqual(higher.kind, .handPlaced(grids: 2, scatters: 0))
        XCTAssertEqual((0..<8).map { higher.readingPosition(of: $0) }, [4, 5, 6, 7, 0, 1, 2, 3])
        // Two clusters sharing a top edge: the one at the leading edge comes first, which on a right-to-left
        // layout is the one on the right, and each grid then reads its rows from the right as well.
        var tied = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        tied += [Layouts.item(x: 900, y: 100, axOrder: 4), Layouts.item(x: 900, y: 180, axOrder: 5)]
        XCTAssertEqual(model(tied).kind, .handPlaced(grids: 2, scatters: 0))
        XCTAssertEqual((0..<6).map { model(tied).readingPosition(of: $0) }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual((0..<6).map { model(tied, .rowsFromRight).readingPosition(of: $0) },
                       [3, 2, 5, 4, 0, 1])
    }

    // MARK: - A free-form scatter

    func testAScatterIsHandPlaced() {
        // The Desktop as somebody left it: no two icons on a line, nothing on a pitch.
        let positions: [(CGFloat, CGFloat)] = [(1413, 43), (1423, 145), (1309, 43), (612, 511),
                                               (277, 388), (980, 133), (1041, 702), (355, 96)]
        let items = positions.enumerated().map { order, position in
            Layouts.item(x: position.0, y: position.1, axOrder: order, side: Layouts.desktopSide)
        }
        guard case .handPlaced = model(items, .columnsFromRight).kind else { return XCTFail("hand-placed") }
    }

    func testTheRubberBandIsBoundedByTheTwoIcons() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0),
                     Layouts.item(x: 300, y: 260, axOrder: 1),
                     Layouts.item(x: 700, y: 620, axOrder: 2),
                     Layouts.item(x: 900, y: 120, axOrder: 3)]
        // The band from the first to the third holds the second and not the fourth.
        XCTAssertEqual(model(items).range(from: 0, to: 2), .band([0, 1, 2]))
    }

    // MARK: - The Desktop

    func testASortedDesktopFillsColumnsFromTheRight() {
        // Measured: a Desktop sorted by name fills x 1410 from y 42 downwards, then x 1286.
        let items = Layouts.filled(rows: 7, columns: 3, count: 10, flow: .columnsFromRight,
                                   origin: CGPoint(x: 1166, y: 42),
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        let model = model(items, .columnsFromRight)
        XCTAssertEqual(model.kind, .arranged(.columnsFromRight))
        XCTAssertEqual((0..<10).map { model.flowPosition(of: $0) }, (0..<10).map { $0 })
        XCTAssertEqual(model.range(from: 6, to: 8)?.items, [6, 7, 8])
    }

    func testARangeDownADesktopColumnAndIntoTheNext() {
        let items = Layouts.filled(rows: 7, columns: 3, flow: .columnsFromRight,
                                   origin: CGPoint(x: 1166, y: 42),
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        let model = model(items, .columnsFromRight)
        // The last of the first column and the first of the second are next to each other in flow order.
        XCTAssertEqual(model.range(from: 6, to: 7)?.items, [6, 7])
    }

    // MARK: - Right to left

    func testARightToLeftWindowFillsRowsFromTheRight() {
        let items = Layouts.filled(rows: 3, columns: 5, count: 13, flow: .rowsFromRight)
        let model = model(items, .rowsFromRight)
        XCTAssertEqual(model.kind, .arranged(.rowsFromRight))
        XCTAssertEqual((0..<13).map { model.flowPosition(of: $0) }, (0..<13).map { $0 })
    }

    /// With the same frames and the Accessibility order reversed, the geometry alone cannot decide, and the
    /// order Finder listed the items in is what does.
    func testTheAccessibilityOrderDecidesWhenTheGeometryCannot() {
        // One row: every flow accepts it, so the tie is broken by the order and then by the fallback.
        let leftToRight = (0..<5).map {
            Layouts.item(x: 540 + CGFloat($0) * 116, y: 250, axOrder: $0)
        }
        XCTAssertEqual(LayoutModel(items: leftToRight, fallbackFlow: .rowsFromRight).kind,
                       .arranged(.rowsFromLeft))
        let rightToLeft = (0..<5).map {
            Layouts.item(x: 540 + CGFloat(4 - $0) * 116, y: 250, axOrder: $0)
        }
        XCTAssertEqual(LayoutModel(items: rightToLeft, fallbackFlow: .rowsFromLeft).kind,
                       .arranged(.rowsFromRight))
    }

    // MARK: - Groups

    func testGroupedSectionsCountFromTopToBottom() {
        // Three folders, then seven files, then two pictures: three sections, each starting a new line.
        var items = Layouts.filled(rows: 1, columns: 6, count: 3,
                                   origin: CGPoint(x: 540, y: 250), section: 0)
        items += Layouts.filled(rows: 2, columns: 6, count: 7,
                                origin: CGPoint(x: 540, y: 406), section: 1)
        items += Layouts.filled(rows: 1, columns: 6, count: 2,
                                origin: CGPoint(x: 540, y: 678), section: 2)
        let model = model(items)
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual((0..<12).map { model.flowPosition(of: $0) }, (0..<12).map { $0 })
        // From the last folder to the second file of the second section's second row.
        XCTAssertEqual(model.range(from: 2, to: 8)?.items, [2, 3, 4, 5, 6, 7, 8])
    }

    func testAGroupWhoseSectionNumbersRunBackwardsIsStillOrderedByPosition() {
        // The section numbers are the order Accessibility listed them in, which is not promised to be the
        // order they are drawn in. Position decides.
        var items = Layouts.filled(rows: 1, columns: 6, count: 3,
                                   origin: CGPoint(x: 540, y: 250), section: 7)
        items += Layouts.filled(rows: 1, columns: 6, count: 3,
                                origin: CGPoint(x: 540, y: 406), section: 1)
        let model = model(items)
        XCTAssertEqual(model.flowPosition(of: 0), 0)
        XCTAssertEqual(model.flowPosition(of: 3), 3)
    }

    // MARK: - Labels

    /// Finder reports an item's icon box and not its cell, so two names of different lengths give two
    /// frames of the same height. This proves the maths survives even when they do not.
    func testFramesOfDifferentHeightsStillLandOnTheSameRow() {
        var items = Layouts.filled(rows: 3, columns: 5)
        for index in items.indices where index.isMultiple(of: 2) {
            let frame = items[index].frame
            items[index] = LayoutItem(frame: CGRect(x: frame.minX, y: frame.minY,
                                                    width: frame.width, height: frame.height + 20),
                                      section: items[index].section, axOrder: items[index].axOrder)
        }
        let model = model(items)
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual(model.range(from: 0, to: 6)?.items.count, 7)
    }

    // MARK: - Degenerate shapes

    func testASingleRow() {
        let model = model(Layouts.filled(rows: 1, columns: 8))
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual(model.range(from: 1, to: 6)?.items, [1, 2, 3, 4, 5, 6])
    }

    func testASingleColumn() {
        let items = Layouts.filled(rows: 8, columns: 1)
        let model = model(items)
        // One column reads the same under every flow, so the caller's fallback stands.
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual(model.range(from: 2, to: 5)?.items, [2, 3, 4, 5])
    }

    func testASingleItem() {
        let model = model([Layouts.item(x: 540, y: 250)])
        XCTAssertEqual(model.range(from: 0, to: 0)?.items, [0])
    }

    func testNoItemsAtAll() {
        let model = model([])
        XCTAssertNil(model.range(from: 0, to: 0)?.items)
    }

    func testAnIndexThatIsNotAnItemIsRefused() {
        let model = model(Layouts.filled(rows: 2, columns: 3))
        XCTAssertNil(model.range(from: 0, to: 99)?.items)
        XCTAssertNil(model.range(from: -1, to: 2)?.items)
    }

    // MARK: - Stacks

    func testAStackIsNeverInARange() {
        var items = Layouts.filled(rows: 1, columns: 5, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[2] = LayoutItem(frame: items[2].frame, section: 0, axOrder: 2, isFile: false)
        let model = model(items, .columnsFromRight)
        let range = model.range(from: 0, to: 4)?.items
        XCTAssertEqual(range, [0, 1, 3, 4])
    }

    func testAStackAtEitherEndLetsTheClickThrough() {
        var items = Layouts.filled(rows: 1, columns: 4, pitch: Layouts.desktopPitch,
                                   side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        let model = model(items)
        XCTAssertNil(model.range(from: 0, to: 3)?.items)
        XCTAssertNil(model.range(from: 3, to: 0)?.items)
    }

    func testAStackStillHoldsItsPlaceInTheLattice() {
        // It is drawn in a cell, so leaving it out of the lattice would put a hole where there is none.
        var items = Layouts.filled(rows: 3, columns: 4)
        items[5] = LayoutItem(frame: items[5].frame, section: 0, axOrder: 5, isFile: false)
        XCTAssertEqual(model(items).kind, .arranged(.rowsFromLeft))
    }

    // MARK: - The click

    /// The spec's §4: a 3 × 4 sorted window, icons numbered in reading order.
    func testTheOwnersExampleOnAnArrangedGrid() {
        let model = model(Layouts.filled(rows: 3, columns: 4))
        let first = model.shiftClick(from: 0, selection: [0], target: 4)
        XCTAssertEqual(first?.selection, [0, 1, 2, 3, 4])
        XCTAssertEqual(first?.anchor, 0)
        XCTAssertEqual(first?.shape, .ordered([0, 1, 2, 3, 4]))
        // ⌘ Command click 8 (index 7), then ⇧ Shift click 10 (index 9): the run {8} is replaced by 8...10.
        let second = model.shiftClick(from: 7, selection: [0, 1, 2, 3, 4, 7], target: 9)
        XCTAssertEqual(second?.selection, [0, 1, 2, 3, 4, 7, 8, 9])
        // ⇧ Shift click 6 (index 5): the range 6...8 touches {8,9,10}, which goes whole.
        let third = model.shiftClick(from: 7, selection: second!.selection, target: 5)
        XCTAssertEqual(third?.selection, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(third?.anchor, 7)
    }

    func testASelectedIconInAnotherClusterIsNeverTouched() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 160), firstAXOrder: 4)
        let outcome = model(items).shiftClick(from: 0, selection: [0, 6], target: 3)
        XCTAssertEqual(outcome?.selection, [0, 1, 2, 3, 6])
    }

    func testARubberBandIsAddedToWhatWasSelected() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 900, y: 700, axOrder: 1),
                     Layouts.item(x: 100, y: 700, axOrder: 2), Layouts.item(x: 2_000, y: 100, axOrder: 3)]
        // The fourth icon is outside the rectangle and selected: it stays selected.
        let outcome = model(items).shiftClick(from: 0, selection: [3], target: 1)
        XCTAssertEqual(outcome?.shape, .band([0, 1, 2]))
        XCTAssertEqual(outcome?.selection, [0, 1, 2, 3])
    }

    func testAStackInsideTheRangeIsNotSelected() {
        var items = Layouts.filled(rows: 1, columns: 6, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[2] = LayoutItem(frame: items[2].frame, section: 0, axOrder: 2, isFile: false)
        let outcome = model(items, .columnsFromRight).shiftClick(from: 0, selection: [0], target: 4)
        XCTAssertEqual(outcome?.selection, [0, 1, 3, 4])
    }

    /// A collapsed stack somebody selected is left exactly as it was, wherever it sits: a range never
    /// selects one and never deselects one.
    func testASelectedStackIsNeverTouchedByARange() {
        func row(stackAt stack: Int) -> [LayoutItem] {
            var items = Layouts.filled(rows: 1, columns: 6, flow: .columnsFromRight,
                                       pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
            items[stack] = LayoutItem(frame: items[stack].frame, section: 0, axOrder: stack, isFile: false)
            return items
        }
        // Selected and outside the range: it stays selected.
        let outside = model(row(stackAt: 5), .columnsFromRight).shiftClick(from: 0, selection: [0, 5], target: 2)
        XCTAssertEqual(outside?.selection, [0, 1, 2, 5])
        // Selected and inside the range: it stays selected too; the files around it are the range's.
        let inside = model(row(stackAt: 2), .columnsFromRight).shiftClick(from: 0, selection: [0, 2], target: 4)
        XCTAssertEqual(inside?.selection, [0, 1, 2, 3, 4])
    }

    /// A selected stack is not a selected position: two selected files on either side of it are two runs,
    /// and a range touching one of them leaves the other alone (docs/functional.md §3).
    func testASelectedStackBetweenTwoSelectedFilesDoesNotJoinThemIntoOneRun() {
        var items = Layouts.filled(rows: 1, columns: 6, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[2] = LayoutItem(frame: items[2].frame, section: 0, axOrder: 2, isFile: false)
        let outcome = model(items, .columnsFromRight).shiftClick(from: 3, selection: [1, 2, 3], target: 4)
        XCTAssertEqual(outcome?.selection, [1, 2, 3, 4])
    }

    func testAnIndexThatIsNotAnItemIsNeverSelected() {
        let outcome = model(Layouts.filled(rows: 2, columns: 3)).shiftClick(from: 0, selection: [40, 5], target: 1)
        XCTAssertEqual(outcome?.selection, [0, 1, 5])
    }

    // MARK: - The three properties

    func testEveryRangeHoldsBothEndsAndIsSymmetric() {
        let layouts: [[LayoutItem]] = [
            Layouts.filled(rows: 4, columns: 6),
            Layouts.filled(rows: 4, columns: 6, count: 20),
            Layouts.filled(rows: 5, columns: 4, flow: .columnsFromRight),
            [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 317, y: 254, axOrder: 1),
             Layouts.item(x: 640, y: 111, axOrder: 2), Layouts.item(x: 880, y: 590, axOrder: 3)],
        ]
        for items in layouts {
            let model = model(items)
            for anchor in items.indices {
                for target in items.indices {
                    let range = try? XCTUnwrap(model.range(from: anchor, to: target)?.items)
                    guard let range else { return XCTFail("no range for \(anchor) to \(target)") }
                    XCTAssertTrue(range.contains(anchor), "total: \(anchor) to \(target)")
                    XCTAssertTrue(range.contains(target), "total: \(anchor) to \(target)")
                    XCTAssertEqual(range, model.range(from: target, to: anchor)?.items,
                                   "symmetric: \(anchor) to \(target)")
                    XCTAssertEqual(range, range.sorted(), "ascending: \(anchor) to \(target)")
                }
            }
        }
    }

    func testTheSameLayoutAlwaysGivesTheSameAnswer() {
        let items = Layouts.filled(rows: 4, columns: 6, count: 19)
        let first = model(items)
        for _ in 0..<5 {
            let again = model(items)
            XCTAssertEqual(again.kind, first.kind)
            XCTAssertEqual(again.range(from: 3, to: 16), first.range(from: 3, to: 16))
        }
    }

    // MARK: - Five thousand items

    /// The size the specification names. The point is the complexity, not the wall clock: this runs in a
    /// debug build, where everything is an order of magnitude slower than the build that ships.
    func testFiveThousandItems() {
        let items = Layouts.filled(rows: 500, columns: 10)
        let started = Date()
        let model = model(items)
        let range = model.range(from: 137, to: 4_211)?.items
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(model.kind, .arranged(.rowsFromLeft))
        XCTAssertEqual(range?.count, 4_211 - 137 + 1)
        XCTAssertEqual(range?.first, 137)
        XCTAssertEqual(range?.last, 4_211)
        XCTAssertLessThan(elapsed, 5, "5,000 items took \(elapsed) s, which is not O(n log n)")
    }

    func testFiveThousandScatteredItems() {
        // The other shape at that size: nothing on a lattice, so whatever clusters the icons chain into, and
        // the rubber band between them, is what answers.
        var generator = SystemRandomNumberGenerator()
        var items: [LayoutItem] = []
        for order in 0..<5_000 {
            items.append(Layouts.item(x: CGFloat(UInt.random(in: 0...3_000, using: &generator)),
                                      y: CGFloat(UInt.random(in: 0...2_000, using: &generator)),
                                      axOrder: order))
        }
        let started = Date()
        let model = model(items)
        let range = model.range(from: 0, to: 4_999)?.items
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertNotNil(range)
        XCTAssertTrue(range?.contains(0) == true)
        XCTAssertTrue(range?.contains(4_999) == true)
    }
}
