import CoreGraphics
import XCTest
@testable import ShiftPickCore

/// Which icons could be one grid together, and how far apart neighbours sit. Built for a view Finder is
/// not laying out.
final class ClustersTests: XCTestCase {
    func testAGridIsOneClusterAtItsOwnPitch() {
        let clusters = Clusters.build(Layouts.filled(rows: 3, columns: 4))
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters.index), [0])
        XCTAssertEqual(clusters.pitch, Layouts.windowPitch.width, accuracy: 0.5)
    }

    func testTwoGridsThreePitchesApartAreTwoClusters() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100 + 4 * 116, y: 100), firstAXOrder: 4)
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.index[0], clusters.index[3])
        XCTAssertNotEqual(clusters.index[0], clusters.index[4])
    }

    /// One empty column between two groups is two pitches, which breaks the link.
    func testOneEmptyColumnBetweenTwoGroupsSeparatesThem() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100 + 3 * 116, y: 100), firstAXOrder: 4)
        XCTAssertEqual(Clusters.build(items).count, 2)
    }

    func testDiagonalNeighboursAreLinked() {
        // A checkerboard: no two icons share a row or a column edge, every neighbour is diagonal.
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 216, y: 216, axOrder: 1),
                     Layouts.item(x: 332, y: 100, axOrder: 2), Layouts.item(x: 448, y: 216, axOrder: 3)]
        XCTAssertEqual(Clusters.build(items).count, 1)
    }

    func testAWobblyGridIsStillOneClusterNearItsPitch() {
        var generator = SeededGenerator(seed: 7)
        let items = Layouts.filled(rows: 4, columns: 5, pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
            .enumerated().map { order, item in
                let dx = CGFloat(Int.random(in: -20...20, using: &generator))
                let dy = CGFloat(Int.random(in: -20...20, using: &generator))
                return LayoutItem(frame: item.frame.offsetBy(dx: dx, dy: dy), axOrder: order)
            }
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.pitch, Layouts.desktopPitch.width, accuracy: 25)
    }

    func testIconsFarFromEveryoneAreClustersOfOne() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 900, y: 700, axOrder: 1)]
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 2)
        // Nobody within reach: the pitch falls back to one and a half icon sides.
        XCTAssertEqual(clusters.pitch, Layouts.windowSide * 1.5, accuracy: 0.5)
    }

    func testNothingClustersToNothing() {
        let clusters = Clusters.build([])
        XCTAssertEqual(clusters.count, 0)
        XCTAssertTrue(clusters.index.isEmpty)
    }

    // MARK: - What a real hand-placed view does to the rules

    /// A Desktop tidied by hand without snapping: every icon up to twenty points off its cell, a quarter
    /// of a 72-point icon. Whatever the wobble falls out as, the grid is one cluster and the pitch is the
    /// real one: the nearest icon in each of the four directions is a sample, so an icon wobbled towards
    /// this one and an icon wobbled away cancel out instead of the nearer of the four always winning. (The
    /// median of the plain nearest-neighbour distance read 108 for 122 on average and 96 for one seed in
    /// forty, and that seed's grid split in two; this one reads 120 on average, 113 to 128 over the same
    /// forty seeds, and none of them splits.)
    func testAWobblyGridHoldsTogetherAtItsRealPitchWhateverTheWobble() {
        for seed in 1...40 {
            let items = Layouts.wobbled(rows: 4, columns: 5, amplitude: 20, seed: UInt64(seed))
            let clusters = Clusters.build(items)
            XCTAssertEqual(clusters.count, 1, "seed \(seed)")
            XCTAssertEqual(clusters.pitch, Layouts.desktopPitch.width, accuracy: 10, "seed \(seed)")
        }
    }

    /// Two ragged columns of icons, one down each edge of the Desktop, as many people keep them. The
    /// screen between them is not a pitch: the pitch is what neighbours on one grid sit at, and each
    /// column is its own cluster, so a range down one never takes the other with it.
    func testTwoColumnsAtOppositeEdgesOfTheScreenAreTwoClusters() {
        var items = Layouts.filled(rows: 5, columns: 1, count: 4, origin: CGPoint(x: 20, y: 42),
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items += Layouts.filled(rows: 5, columns: 1, count: 5, origin: CGPoint(x: 1_400, y: 42),
                                pitch: Layouts.desktopPitch, side: Layouts.desktopSide, firstAXOrder: 4)
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.pitch, Layouts.desktopPitch.height, accuracy: 0.5)
    }

    /// Two groups with one empty column between them, both tidied by hand: still two groups, whatever
    /// the wobble. The gap is two pitches less two wobbles, the link one and a half pitches.
    func testAnEmptyColumnSeparatesTwoWobblyGroups() {
        for seed in 1...40 {
            var items = Layouts.wobbled(rows: 3, columns: 3, amplitude: 20, seed: UInt64(seed),
                                        origin: CGPoint(x: 100, y: 100))
            items += Layouts.wobbled(rows: 3, columns: 3, amplitude: 20, seed: UInt64(seed) + 1_000,
                                     origin: CGPoint(x: 100 + 4 * Layouts.desktopPitch.width, y: 100),
                                     firstAXOrder: 9)
            XCTAssertEqual(Clusters.build(items).count, 2, "seed \(seed)")
        }
    }

    /// A group and three strays dropped well away from it: the group is one cluster and each stray its
    /// own, so that a range inside the group reads along its rows and a range to a stray is the band.
    func testStraysBesideAGroupAreClustersOfOne() {
        var items = Layouts.filled(rows: 3, columns: 4, origin: CGPoint(x: 100, y: 100))
        items += [Layouts.item(x: 100 + 6 * 116, y: 100, axOrder: 12),     // two empty columns to the right
                  Layouts.item(x: 100 + 7 * 116, y: 700, axOrder: 13),     // far down and to the right
                  Layouts.item(x: 100, y: 100 + 5 * 116, axOrder: 14)]     // two empty rows below
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 4)
        XCTAssertEqual(Set(clusters.index[0..<12]).count, 1)
        XCTAssertEqual(Set(clusters.index[12...]).count, 3)
        XCTAssertFalse(Set(clusters.index[12...]).contains(clusters.index[0]))
    }

    /// Six icons dropped on top of one another in the corner of a grid. Their centres are a few points
    /// apart, which is not a pitch: an icon closer than one side overlaps, and the pitch is measured to the
    /// nearest icon that does not, so the grid's own pitch stands and the pile sits in its cell.
    func testAPileOnAGridLeavesThePitchAlone() {
        var items = Layouts.filled(rows: 3, columns: 4)
        for stacked in 0..<6 {
            items.append(Layouts.item(x: 540 + CGFloat(stacked) * 3, y: 250 - CGFloat(stacked) * 2,
                                      axOrder: 12 + stacked))
        }
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.pitch, Layouts.windowPitch.width, accuracy: 0.5)
    }

    /// A pile and nothing else: nobody has a neighbour that is not on top of them, so the pitch is the
    /// fallback, and the pile is one cluster in one cell rather than six rows three points apart.
    func testAPileAloneIsOneClusterAtTheFallbackPitch() {
        let pile = (0..<6).map {
            Layouts.item(x: 540 + CGFloat($0) * 3, y: 250 - CGFloat($0) * 2, axOrder: $0)
        }
        let clusters = Clusters.build(pile)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.pitch, Layouts.windowSide * K.lonePitchSides, accuracy: 0.5)
        let stacked = (0..<6).map { Layouts.item(x: 540, y: 250, axOrder: $0) }
        XCTAssertEqual(Clusters.build(stacked).count, 1)
    }

    /// Accessibility lists the icons in whatever order it likes. The partition never depends on it.
    func testThePartitionIsTheSameWhateverOrderTheItemsArriveIn() {
        var items = Layouts.wobbled(rows: 3, columns: 4, amplitude: 15, seed: 11,
                                    origin: CGPoint(x: 100, y: 100))
        items += Layouts.wobbled(rows: 2, columns: 2, amplitude: 15, seed: 12,
                                 origin: CGPoint(x: 900, y: 500), firstAXOrder: 12)
        items += [Layouts.item(x: 100, y: 900, axOrder: 16, side: Layouts.desktopSide)]
        let straight = Clusters.build(items)
        var generator = SeededGenerator(seed: 5)
        let shuffledOrder = items.indices.shuffled(using: &generator)
        let shuffled = Clusters.build(shuffledOrder.map { items[$0] })
        XCTAssertEqual(shuffled.count, straight.count)
        XCTAssertEqual(shuffled.pitch, straight.pitch)
        // Two items share a cluster in one build exactly when they do in the other.
        for a in items.indices {
            for b in items.indices {
                let together = straight.index[a] == straight.index[b]
                let positionA = shuffledOrder.firstIndex(of: a)!, positionB = shuffledOrder.firstIndex(of: b)!
                XCTAssertEqual(shuffled.index[positionA] == shuffled.index[positionB], together, "\(a), \(b)")
            }
        }
    }

    // MARK: - Small icons

    /// The label under a 16-point icon is the label under a 64-point one, so the cell does not shrink with
    /// the icon: at 16 points a pitch of 96 is six sides, and at 32 points the window's 116 is three and a
    /// half. Three of either icon's own sides finds nobody; three sides of `K.cellSideFloor`, which is what
    /// a small icon is measured in, finds every neighbour, and the grid is one cluster at its own pitch.
    func testSmallIconsOnALabelDrivenPitchAreOneClusterAtThatPitch() {
        for (side, pitch) in [(CGFloat(16), CGFloat(96)), (32, 116)] {
            let items = Layouts.filled(rows: 4, columns: 5, pitch: CGSize(width: pitch, height: pitch), side: side)
            let clusters = Clusters.build(items)
            XCTAssertEqual(clusters.count, 1, "side \(side)")
            XCTAssertEqual(clusters.pitch, pitch, accuracy: 0.5, "side \(side)")
        }
    }

    /// The same two views tidied by hand, every icon up to a sixth of its pitch off its cell, for each of
    /// forty wobbles: still one cluster, near its real pitch, exactly as the Desktop's 72-point icons are.
    func testSmallIconsTidiedByHandStillHoldTogetherAtTheirPitch() {
        for (side, pitch, amplitude) in [(CGFloat(16), CGFloat(96), 16), (32, 116, 20)] {
            for seed in 1...40 {
                let items = Layouts.wobbled(rows: 4, columns: 5, amplitude: amplitude, seed: UInt64(seed),
                                            pitch: CGSize(width: pitch, height: pitch), side: side)
                let clusters = Clusters.build(items)
                XCTAssertEqual(clusters.count, 1, "side \(side), seed \(seed)")
                XCTAssertEqual(clusters.pitch, pitch, accuracy: 10, "side \(side), seed \(seed)")
            }
        }
    }

    /// The reach a small icon is given is a 64-point icon's, not the whole screen: two 16-point icons at
    /// opposite corners of a window are still two clusters of one, at the pitch an icon with nobody near
    /// has, which for a small icon is a 64-point icon's too.
    func testSmallIconsFarFromEveryoneAreStillClustersOfOne() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0, side: 16), Layouts.item(x: 600, y: 500, axOrder: 1, side: 16)]
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.pitch, K.cellSideFloor * K.lonePitchSides, accuracy: 0.5)
    }

    /// Two 16-point icons dropped almost on top of each other in the corner of a hand-placed grid, thirty
    /// points apart: within a label's width of each other they share a cell, a pile, exactly as two 64-point
    /// icons that close would, and the pitch is the grid's, not the pair's.
    func testALoosePairInASmallIconGridDoesNotHideTheGrid() {
        var items = Layouts.filled(rows: 4, columns: 5, pitch: CGSize(width: 96, height: 96), side: 16)
        items.append(Layouts.item(x: items[0].frame.minX + 30, y: items[0].frame.minY, axOrder: 20, side: 16))
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.pitch, 96, accuracy: 1)
    }

    /// The size the specification names, in the shape that is hardest for a spatial hash: nothing on a
    /// lattice, so nothing to share a cell with. Debug build; the point is that nothing is quadratic.
    func testFiveThousandScatteredIconsClusterInWellUnderASecond() {
        var generator = SeededGenerator(seed: 3)
        let items = (0..<5_000).map { order in
            Layouts.item(x: CGFloat(Int.random(in: 0...3_000, using: &generator)),
                         y: CGFloat(Int.random(in: 0...2_000, using: &generator)), axOrder: order)
        }
        let started = Date()
        let clusters = Clusters.build(items)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 1, "5,000 scattered icons took \(elapsed) s")
        XCTAssertEqual(clusters.index.count, 5_000)
        XCTAssertEqual(Set(clusters.index), Set(0..<clusters.count))
    }

    func testFiveThousandIconsOnOneGridAreOneCluster() {
        let started = Date()
        let clusters = Clusters.build(Layouts.filled(rows: 500, columns: 10))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.pitch, Layouts.windowPitch.width, accuracy: 0.5)
    }

    /// Accessibility has never answered a frame that is not a number, one that is infinite or one with no
    /// size, and the maths does not stake the process on that: one of each dropped beside a small grid gets
    /// a cluster and a place like any other icon, the grid stays one cluster, nothing traps, and every icon
    /// is ordered exactly once, through the clusters, the grids and the whole model.
    func testFramesThatAreNotNumbersInfiniteOrEmptyStillGetAClusterAndAPlace() {
        var items = Layouts.filled(rows: 2, columns: 3)
        let nan = CGFloat.nan
        items.append(LayoutItem(frame: CGRect(x: nan, y: nan, width: nan, height: nan), axOrder: 6))
        items.append(LayoutItem(frame: CGRect(x: CGFloat.infinity, y: 250, width: 64, height: 64), axOrder: 7))
        items.append(LayoutItem(frame: CGRect(x: 540, y: 250 + 2 * 116, width: 0, height: 0), axOrder: 8))
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.index.count, 9)
        XCTAssertEqual(Set(clusters.index), Set(0..<clusters.count))
        XCTAssertEqual(Set(clusters.index[0..<6]).count, 1, "the grid is still one cluster")
        XCTAssertGreaterThan(clusters.pitch, 0)
        for number in 0..<clusters.count {
            let members = items.indices.filter { clusters.index[$0] == number }
            let grid = Grid.fit(members: members, items: items, pitch: clusters.pitch, leadingIsLeft: true)
            XCTAssertEqual(grid.order.count, members.count, "cluster \(number)")
            XCTAssertEqual(Set(grid.order), Set(members), "cluster \(number)")
        }
        let model = LayoutModel(items: items, fallbackFlow: .rowsFromLeft)
        XCTAssertEqual(Set(items.indices.compactMap { model.readingPosition(of: $0) }), Set(0..<9))
        XCTAssertEqual(model.range(from: 0, to: 5)?.items.count, 6)
    }

    func testClusterNumbersAreDenseFromZero() {
        var items = Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 1000, y: 100), firstAXOrder: 2)
        items += Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 900), firstAXOrder: 4)
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertEqual(Set(clusters.index), [0, 1, 2])
    }
}
