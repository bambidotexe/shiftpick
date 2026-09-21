import CoreGraphics
import Foundation

/// The whole of the selection maths: a set of icon frames in, a classified layout and a range out.
///
/// It is pure and it is total. Building one never fails and never throws; asking for a range answers `nil`
/// for exactly two reasons, both of which mean *let the click through*: an index that is not an item, or an
/// end of the range that is not a file. Everything else — a grid with holes, a scatter, one row, one
/// column, five thousand icons — has an answer.
///
/// The three properties the range is held to, and which `RangeSelectionTests` pins:
///
/// - **Total.** It always contains the anchor and the target.
/// - **Symmetric.** `range(from: a, to: b)` is `range(from: b, to: a)`.
/// - **Deterministic**, and `O(n log n)`: the clustering sorts, the contiguity check sorts, nothing walks
///   the lattice cell by cell.
public struct LayoutModel {
    public let items: [LayoutItem]
    public let kind: LayoutKind

    /// For an arranged layout, where each item sits in flow order, sections top to bottom and flow inside
    /// each of them. Empty when the layout is hand-placed, which is the only thing that distinguishes the
    /// two paths below.
    private let position: [Int]
    private let lattice: Lattice

    /// `fallbackFlow` is what the caller knows about the container and the geometry cannot: a window fills
    /// rows from its leading edge, the Desktop fills columns from its trailing one. It is used when the
    /// geometry accepts several flows, which one row, one column and a single item always do.
    public init(items: [LayoutItem], fallbackFlow: Flow) {
        self.items = items
        lattice = Lattice.build(items)
        guard !items.isEmpty else {
            kind = .handPlaced
            position = []
            return
        }
        if let (flow, order) = Self.arrangement(items, lattice, fallbackFlow: fallbackFlow) {
            kind = .arranged(flow)
            position = order
        } else {
            kind = .handPlaced
            position = []
        }
    }

    /// Where the item sits in flow order, or nil when the layout is hand-placed.
    public func flowPosition(of index: Int) -> Int? {
        guard case .arranged = kind, items.indices.contains(index) else { return nil }
        return position[index]
    }

    // MARK: - The range

    /// Every item between the anchor and the target, inclusive, as indices into `items`, ascending.
    ///
    /// Arranged: the slice of flow order between the two. Hand-placed: the anchor, the target, and every
    /// item whose reference point falls inside the rectangle their two frames span — a rubber band drawn
    /// between the two icons.
    ///
    /// nil when either end is not an item or is not a file. A collapsed Desktop stack is not a file: it is
    /// never returned inside a range either, although it does hold its place in the lattice, because that
    /// is where it is drawn.
    public func range(from anchor: Int, to target: Int) -> [Int]? {
        guard items.indices.contains(anchor), items.indices.contains(target),
              items[anchor].isFile, items[target].isFile else { return nil }
        switch kind {
        case .arranged:
            let low = min(position[anchor], position[target])
            let high = max(position[anchor], position[target])
            return items.indices.filter { items[$0].isFile && (low...high).contains(position[$0]) }
        case .handPlaced:
            let band = items[anchor].frame.union(items[target].frame)
            return items.indices.filter {
                guard items[$0].isFile else { return false }
                if $0 == anchor || $0 == target { return true }
                return band.contains(items[$0].reference)
            }
        }
    }

    // MARK: - The anchor

    /// The anchor to use when the stored one is gone, stale, or belongs to another container: the selected
    /// item **farthest from the target**, which is the rule the two cases in the specification describe.
    /// The target after the selection gives the selected item nearest the start of the range; the target
    /// before it gives the one nearest the end; and a target inside the selection, which neither case
    /// covers, gives the widest range the selection can justify.
    ///
    /// Distance is measured in flow order when there is one, and across the screen when there is not. nil
    /// when nothing usable is selected, which means the click is let through.
    public func derivedAnchor(target: Int, selection: [Int]) -> Int? {
        guard items.indices.contains(target) else { return nil }
        let candidates = selection.filter { items.indices.contains($0) && items[$0].isFile }
        guard !candidates.isEmpty else { return nil }
        var best = candidates[0]
        var bestDistance = -CGFloat.greatestFiniteMagnitude
        for candidate in candidates {
            let distance = self.distance(from: candidate, to: target)
            // `>` and not `>=`: a tie keeps the first, and `candidates` is the caller's order, so the
            // answer does not depend on how the selection was read back.
            if distance > bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func distance(from index: Int, to target: Int) -> CGFloat {
        switch kind {
        case .arranged:
            return CGFloat(abs(position[index] - position[target]))
        case .handPlaced:
            let a = items[index].reference, b = items[target].reference
            return hypot(a.x - b.x, a.y - b.y)
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
