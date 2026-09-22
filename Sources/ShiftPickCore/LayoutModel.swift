import CoreGraphics
import Foundation

/// What a range is: the slice of one reading order between two icons, or the icons inside the rectangle
/// the two span. `items` are indices into `LayoutModel.items`, ascending.
public enum RangeShape: Equatable, Sendable {
    /// Inside one order (an arranged view, or one grid of a hand-placed one). A ⇧ Shift click replaces every
    /// run of the selection it touches with it (`ShiftClick`).
    case ordered([Int])
    /// Between two grids, or to or from a scatter: the rubber band, the rectangle the two frames span. A
    /// ⇧ Shift click adds it.
    case band([Int])

    public var items: [Int] {
        switch self {
        case .ordered(let items), .band(let items): items
        }
    }
}

/// The whole of the selection maths: a set of icon frames in, a reading order, a range and the selection a
/// ⇧ Shift click leaves out.
///
/// It is pure and it is total. Building one never fails and never throws; asking for a range answers `nil`
/// for exactly two reasons, both of which mean *let the click through*: an index that is not an item, or an
/// end of the range that is not a file. Everything else — a grid with holes, a scatter, one row, one
/// column, five thousand icons — has an answer.
///
/// Every item has one place in **the view's reading order**: flow order for an arranged view; for a
/// hand-placed one, cluster by cluster (top edge, then leading edge), each grid along its rows from the
/// leading edge, each scatter by top edge then leading edge. The order is what `ShiftClick`'s rule runs
/// over, and what names a stand-in for a deselected anchor.
///
/// The three properties a range is held to, which `RangeSelectionTests` pins:
///
/// - **Total.** It always contains the anchor and the target.
/// - **Symmetric.** `range(from: a, to: b)` is `range(from: b, to: a)`.
/// - **Deterministic**, and `O(n log n)`: the clustering sorts, the contiguity check sorts, the spatial hash
///   is linear, nothing walks the lattice cell by cell.
public struct LayoutModel {
    public let items: [LayoutItem]
    public let kind: LayoutKind

    /// The selection a ⇧ Shift click leaves, the icon it was measured from (the anchor from now on), and the
    /// shape of its range.
    public struct Outcome: Equatable, Sendable {
        public let selection: [Int]
        public let anchor: Int
        public let shape: RangeShape
    }

    /// Per item, its place in the reading order; per place, the item.
    private let position: [Int]
    private let itemAt: [Int]
    /// Per item, its cluster. Clusters are numbered in reading order and each holds one contiguous run of
    /// places, `clusterStart[c] ..< clusterStart[c] + clusterCount[c]`. An arranged view is one cluster.
    private let cluster: [Int]
    private let clusterStart: [Int]
    private let clusterCount: [Int]
    private let clusterIsGrid: [Bool]
    private let lattice: Lattice

    /// `fallbackFlow` is what the caller knows about the container and the geometry cannot: a window fills
    /// rows from its leading edge, the Desktop fills columns from its trailing one. It breaks the tie when
    /// the geometry accepts several flows, and it says which edge is the leading one for a hand-placed grid.
    public init(items: [LayoutItem], fallbackFlow: Flow) {
        self.items = items
        lattice = Lattice.build(items)
        guard !items.isEmpty else {
            kind = .handPlaced(grids: 0, scatters: 0)
            position = []
            itemAt = []
            cluster = []
            clusterStart = []
            clusterCount = []
            clusterIsGrid = []
            return
        }
        if let (flow, order) = Self.arrangement(items, lattice, fallbackFlow: fallbackFlow) {
            kind = .arranged(flow)
            position = order
            var inverse = [Int](repeating: 0, count: items.count)
            for (item, place) in order.enumerated() { inverse[place] = item }
            itemAt = inverse
            cluster = [Int](repeating: 0, count: items.count)
            clusterStart = [0]
            clusterCount = [items.count]
            clusterIsGrid = [true]
            return
        }

        let clusters = Clusters.build(items)
        let leadingIsLeft = fallbackFlow == .rowsFromLeft || fallbackFlow == .columnsFromRight
        var members = [[Int]](repeating: [], count: clusters.count)
        for index in items.indices { members[clusters.index[index]].append(index) }
        let grids = members.map {
            Grid.fit(members: $0, items: items, pitch: clusters.pitch, leadingIsLeft: leadingIsLeft)
        }
        let inOrder = grids.indices.sorted { a, b in
            if grids[a].top != grids[b].top { return grids[a].top < grids[b].top }
            if grids[a].leading != grids[b].leading { return grids[a].leading < grids[b].leading }
            return a < b
        }
        var position = [Int](repeating: 0, count: items.count)
        var itemAt: [Int] = []
        var cluster = [Int](repeating: 0, count: items.count)
        var starts: [Int] = []
        var counts: [Int] = []
        var isGrid: [Bool] = []
        for (number, gridIndex) in inOrder.enumerated() {
            let grid = grids[gridIndex]
            starts.append(itemAt.count)
            counts.append(grid.order.count)
            isGrid.append(grid.isGrid)
            for item in grid.order {
                position[item] = itemAt.count
                itemAt.append(item)
                cluster[item] = number
            }
        }
        self.position = position
        self.itemAt = itemAt
        self.cluster = cluster
        clusterStart = starts
        clusterCount = counts
        clusterIsGrid = isGrid
        kind = .handPlaced(grids: isGrid.filter { $0 }.count, scatters: isGrid.filter { !$0 }.count)
    }

    /// Where the item sits in flow order, or nil when the layout is hand-placed.
    public func flowPosition(of index: Int) -> Int? {
        guard case .arranged = kind, items.indices.contains(index) else { return nil }
        return position[index]
    }

    /// Where the item sits in the view's reading order, whatever the layout.
    public func readingPosition(of index: Int) -> Int? {
        items.indices.contains(index) ? position[index] : nil
    }

    /// The first file in reading order: what a ⇧ Shift click measures from when nothing is selected and the
    /// caller knows the first icon is on screen.
    public var firstItem: Int? { itemAt.first { items[$0].isFile } }

    // MARK: - The anchor

    /// The icon a ⇧ Shift click is measured from: the stored anchor while it is a selected file on screen;
    /// else the first selected file after it in reading order; else the last selected file before it. A
    /// stored anchor that is gone, stale or not a file counts as one before everything. nil when nothing
    /// usable is selected.
    public func effectiveAnchor(stored: Int?, selection: [Int]) -> Int? {
        let candidates = Set(selection.filter { items.indices.contains($0) && items[$0].isFile }
            .map { position[$0] })
        let pivot = stored.flatMap { items.indices.contains($0) && items[$0].isFile ? position[$0] : nil }
        return ShiftClick.standIn(anchor: pivot, selection: candidates).map { itemAt[$0] }
    }

    // MARK: - The range

    /// Every file between the anchor and the target, inclusive, as indices into `items`, ascending, and
    /// how they were found: the slice of the reading order when both are in one grid (or the view is
    /// arranged), and otherwise the rubber band: the anchor, the target, and every file whose centre falls
    /// inside the rectangle their two frames span.
    ///
    /// nil when either end is not an item or is not a file. A collapsed Desktop stack is not a file: it is
    /// never returned inside a range either, although it does hold its place in the order, because that is
    /// where it is drawn.
    public func range(from anchor: Int, to target: Int) -> RangeShape? {
        guard items.indices.contains(anchor), items.indices.contains(target),
              items[anchor].isFile, items[target].isFile else { return nil }
        let own = cluster[anchor]
        if own == cluster[target], clusterIsGrid[own] {
            let low = min(position[anchor], position[target])
            let high = max(position[anchor], position[target])
            return .ordered(items.indices.filter { items[$0].isFile && (low...high).contains(position[$0]) })
        }
        let rectangle = items[anchor].frame.union(items[target].frame)
        return .band(items.indices.filter {
            items[$0].isFile && ($0 == anchor || $0 == target || rectangle.contains(items[$0].reference))
        })
    }

    // MARK: - The click

    /// What one ⇧ Shift click leaves selected, measured from `anchor` (already the effective one) with
    /// `selection` what Finder has selected now. An ordered range replaces every run of selected files it
    /// touches inside its own cluster and leaves every other cluster's selection alone; a band is added.
    /// Selected indices that are not items are dropped. A selected item that is not a file (a collapsed
    /// stack) is never touched: it stays selected wherever it is, a range never selects one, and its place
    /// is not a selected position, so two selected files on either side of it are two runs and not one.
    public func shiftClick(from anchor: Int, selection: [Int], target: Int) -> Outcome? {
        guard let shape = range(from: anchor, to: target) else { return nil }
        let valid = Set(selection.filter { items.indices.contains($0) })
        switch shape {
        case .ordered:
            let own = cluster[anchor]
            let start = clusterStart[own]
            let inside = Set(valid.filter { cluster[$0] == own && items[$0].isFile }
                .map { position[$0] - start })
            guard let ranks = ShiftClick.resolve(anchor: position[anchor] - start, selection: inside,
                                                 target: position[target] - start, count: clusterCount[own])
            else { return nil }
            let chosen = ranks.map { itemAt[start + $0] }.filter { items[$0].isFile }
            let kept = valid.filter { cluster[$0] != own || !items[$0].isFile }
            return Outcome(selection: (chosen + kept).sorted(), anchor: anchor, shape: shape)
        case .band(let inside):
            return Outcome(selection: valid.union(inside).sorted(), anchor: anchor, shape: shape)
        }
    }

    // MARK: - Classification

    /// One group's items, with the two numbers every rank below is counted from. They are worked out once:
    /// computing them inside a comparator turns the sort that orders five thousand icons into an O(n² log n)
    /// walk, which was measured at 47 seconds before it was moved out here.
    private struct Section {
        let items: [Int]
        let firstRow: Int
        let rows: Int
    }

    /// The flow the items fill their lattice along, and every item's place in that order; nil when no flow
    /// fits, which is what *hand-placed* means.
    ///
    /// A layout is arranged when, **inside every section**, the occupied cells are the first `n` cells of
    /// some flow's ordering: no hole, nothing off the lattice, a partial last line allowed. Sections are
    /// independent, because *Use Groups* restarts the fill at each of them; they are ordered by their
    /// topmost row.
    private static func arrangement(_ items: [LayoutItem], _ lattice: Lattice,
                                    fallbackFlow: Flow) -> (Flow, [Int])? {
        guard lattice.isTight else { return nil }
        let sections = sectionsInOrder(items, lattice)

        var accepted: [Flow] = []
        for flow in Flow.allCases where sections.allSatisfy({ fills(flow, $0, lattice) }) {
            accepted.append(flow)
        }
        guard !accepted.isEmpty else { return nil }

        // Several flows fit whenever the layout is too small to tell them apart: one row, one column, one
        // item. The order Accessibility listed the items in breaks the tie where it is informative, and the
        // caller's fallback breaks it where it is not.
        let flow = accepted.count == 1 ? accepted[0]
            : pick(accepted, sections, items, lattice, fallbackFlow: fallbackFlow)

        var position = [Int](repeating: 0, count: items.count)
        var next = 0
        for section in sections {
            let ranked = section.items
                .map { (index: $0, rank: rank(flow, $0, lattice, section)) }
                .sorted { $0.rank < $1.rank }
            for entry in ranked {
                position[entry.index] = next
                next += 1
            }
        }
        return (flow, position)
    }

    /// The items of each section, the sections ordered by the topmost row any of their items is in.
    private static func sectionsInOrder(_ items: [LayoutItem], _ lattice: Lattice) -> [Section] {
        var grouped: [Int: [Int]] = [:]
        for index in items.indices { grouped[items[index].section, default: []].append(index) }
        var described: [(key: Int, section: Section)] = []
        described.reserveCapacity(grouped.count)
        for (key, members) in grouped {
            var first = Int.max
            var last = Int.min
            for index in members {
                let row = lattice.row[index]
                if row < first { first = row }
                if row > last { last = row }
            }
            described.append((key, Section(items: members, firstRow: first, rows: last - first + 1)))
        }
        // By the topmost row a section reaches, and by the number Accessibility gave it only to break a
        // tie: the order sections are listed in is not promised to be the order they are drawn in.
        described.sort { left, right in
            if left.section.firstRow != right.section.firstRow {
                return left.section.firstRow < right.section.firstRow
            }
            return left.key < right.key
        }
        return described.map(\.section)
    }

    /// Whether one section's cells are the first `n` of this flow's ordering. Duplicates — two icons in one
    /// cell — fail it too, because the sorted ranks then cannot be `0 ..< n`.
    private static func fills(_ flow: Flow, _ section: Section, _ lattice: Lattice) -> Bool {
        let ranks = section.items.map { rank(flow, $0, lattice, section) }.sorted()
        return ranks == Array(0..<section.items.count)
    }

    /// Where a cell falls in this flow's ordering, counted from the section's own first line. Columns are
    /// counted across the whole view, not the section: Finder gives every group the full width and starts
    /// each of them at the leading column.
    private static func rank(_ flow: Flow, _ index: Int, _ lattice: Lattice, _ section: Section) -> Int {
        let columns = lattice.columnCount
        let row = lattice.row[index] - section.firstRow
        let column = lattice.column[index]
        switch flow {
        case .rowsFromLeft: return row * columns + column
        case .rowsFromRight: return row * columns + (columns - 1 - column)
        case .columnsFromLeft: return column * section.rows + row
        case .columnsFromRight: return (columns - 1 - column) * section.rows + row
        }
    }

    /// Of the flows the geometry accepts, the one the Accessibility order agrees with most often; the
    /// caller's fallback when none of them does better than the others.
    ///
    /// "Agrees" is counted pair by pair: walking a section in the order Accessibility listed it, how often
    /// does the next item come later in this flow than the one before it. A view whose Accessibility order
    /// says nothing scores every candidate the same, and then the fallback decides.
    private static func pick(_ accepted: [Flow], _ sections: [Section], _ items: [LayoutItem],
                             _ lattice: Lattice, fallbackFlow: Flow) -> Flow {
        let listed = sections.map { section in
            section.items.sorted { items[$0].axOrder < items[$1].axOrder }
        }
        var best = accepted.contains(fallbackFlow) ? fallbackFlow : accepted[0]
        var bestScore = -1
        for flow in accepted.sorted(by: { order(of: $0, fallbackFlow) < order(of: $1, fallbackFlow) }) {
            var score = 0
            for (section, members) in zip(sections, listed) {
                for pair in zip(members, members.dropFirst())
                where rank(flow, pair.0, lattice, section) < rank(flow, pair.1, lattice, section) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                best = flow
            }
        }
        return best
    }

    /// The order candidates are tried in, so that an exact tie keeps the caller's fallback.
    private static func order(of flow: Flow, _ fallbackFlow: Flow) -> Int {
        flow == fallbackFlow ? -1 : (Flow.allCases.firstIndex(of: flow) ?? 0)
    }
}
