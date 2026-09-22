import CoreGraphics
import Foundation

/// The groups of icons that could each be one grid: icons chained together by neighbours within
/// `K.gridLinkPitches` of each other on both axes. Built only for a view Finder is not laying out.
struct Clusters {
    /// Per item, its cluster, numbered densely from 0 in no particular order; `LayoutModel` orders them.
    let index: [Int]
    let count: Int
    /// The distance between two neighbouring icons of one grid, `measurePitch`. It survives a hand-placed
    /// wobble that the lattice's coarse pitch does not.
    let pitch: CGFloat

    static func build(_ items: [LayoutItem]) -> Clusters {
        guard !items.isEmpty else { return Clusters(index: [], count: 0, pitch: 1) }
        let side = max(Lattice.median(items.map(\.frame.height)) ?? 1, 1)
        let pitch = measurePitch(items, side: side)
        let link = K.gridLinkPitches * pitch
        let hash = SpatialHash(items, cell: link)
        var forest = Forest(count: items.count)
        for index in items.indices {
            let point = items[index].reference
            hash.forEachNeighbour(of: point) { other in
                guard other > index else { return }
                let candidate = items[other].reference
                if abs(candidate.x - point.x) <= link, abs(candidate.y - point.y) <= link {
                    forest.union(index, other)
                }
            }
        }
        var numbered: [Int: Int] = [:]
        var index: [Int] = []
        index.reserveCapacity(items.count)
        for item in items.indices {
            let root = forest.find(item)
            if numbered[root] == nil { numbered[root] = numbered.count }
            index.append(numbered[root]!)
        }
        return Clusters(index: index, count: numbered.count, pitch: pitch)
    }

    /// The pitch, in two readings of one pass over the neighbours within `K.neighbourReachSides`.
    ///
    /// The coarse one is the median, over the icons, of the distance to the nearest other icon. It leans
    /// low under a wobble, because the nearest of an icon's four neighbours is the one that wobbled
    /// towards it: 108 for a 122-point Desktop pitch under a twenty-point wobble, and as low as 96. So
    /// the pitch itself is the median of a sample per icon **and per direction** — left, right, above and
    /// below, each a quarter of the plane — of the nearest icon in that direction, measured along the
    /// direction's axis: an icon wobbled towards this one and an icon wobbled away cancel. A sample farther
    /// than the link of the coarse pitch is the icon across a hole, or the far side of a gap, and not a
    /// neighbour on this grid: it is left out.
    ///
    /// An icon whose frame overlaps this one's (centres closer than `K.overlapSides` on both axes) is one
    /// dropped on top of it, a pile, and not a neighbour on any grid Finder draws: it is passed over, and
    /// the nearest icon that does not overlap is measured instead. With no neighbour within reach anywhere
    /// the pitch is `K.lonePitchSides`. Never below one point.
    static func measurePitch(_ items: [LayoutItem], side: CGFloat) -> CGFloat {
        let reach = K.neighbourReachSides * side
        let overlap = K.overlapSides * side
        let hash = SpatialHash(items, cell: reach)
        var nearest: [CGFloat] = []
        var samples: [CGFloat] = []
        for index in items.indices {
            let point = items[index].reference
            var directions = Directions()
            hash.forEachNeighbour(of: point) { other in
                guard other != index else { return }
                let candidate = items[other].reference
                let dx = candidate.x - point.x, dy = candidate.y - point.y
                let across = abs(dx), down = abs(dy)
                guard max(across, down) >= overlap else { return }
                let distance = hypot(dx, dy)
                guard distance <= reach else { return }
                // A neighbour exactly on the diagonal is as much beside this icon as below it.
                if across >= down {
                    directions.offer(dx < 0 ? .left : .right, distance: distance, along: across)
                }
                if down >= across {
                    directions.offer(dy < 0 ? .above : .below, distance: distance, along: down)
                }
            }
            if let best = directions.nearest { nearest.append(best) }
            samples += directions.samples
        }
        guard let coarse = Lattice.median(nearest) else { return max(side * K.lonePitchSides, 1) }
        let link = K.gridLinkPitches * coarse
        return max(Lattice.median(samples.filter { $0 <= link }) ?? coarse, 1)
    }

    /// The nearest icon seen so far in each of the four directions: its distance, and that distance
    /// measured along the direction's axis. A tie in distance keeps the smaller axis distance, so the
    /// sample does not depend on the order the icons were listed in.
    private struct Directions {
        enum Direction: Int { case left, right, above, below }
        private var distance = [CGFloat](repeating: .greatestFiniteMagnitude, count: 4)
        private var along = [CGFloat](repeating: .greatestFiniteMagnitude, count: 4)

        mutating func offer(_ direction: Direction, distance offered: CGFloat, along axis: CGFloat) {
            let slot = direction.rawValue
            if offered < distance[slot] || (offered == distance[slot] && axis < along[slot]) {
                distance[slot] = offered
                along[slot] = axis
            }
        }

        /// The distance to the nearest icon in any direction, or nil when none was offered.
        var nearest: CGFloat? {
            let best = distance.min() ?? .greatestFiniteMagnitude
            return best < .greatestFiniteMagnitude ? best : nil
        }

        /// One sample per direction that has an icon: its distance along that direction's axis.
        var samples: [CGFloat] { along.filter { $0 < .greatestFiniteMagnitude } }
    }
}

/// Items bucketed by a square cell, so that every item within one cell's side of a point is in the nine
/// cells around it. `O(n)` to build, `O(k)` per look-up with k the items in those cells.
struct SpatialHash {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private let cell: CGFloat
    private var buckets: [Cell: [Int]] = [:]

    init(_ items: [LayoutItem], cell: CGFloat) {
        self.cell = max(cell, 1)
        for (index, item) in items.enumerated() {
            buckets[key(item.reference), default: []].append(index)
        }
    }

    private func key(_ point: CGPoint) -> Cell {
        Cell(x: Self.coordinate(point.x / cell), y: Self.coordinate(point.y / cell))
    }

    /// A cell coordinate that cannot trap. Accessibility has never answered a frame that is not finite or
    /// is astronomically far, and a total function does not stake the process on that.
    private static func coordinate(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value.rounded(.down), -1e9), 1e9))
    }

    /// Every item in the cell of `point` and the eight around it, the point's own item included.
    func forEachNeighbour(of point: CGPoint, _ body: (Int) -> Void) {
        let centre = key(point)
        for dx in -1...1 {
            for dy in -1...1 {
                for index in buckets[Cell(x: centre.x + dx, y: centre.y + dy)] ?? [] { body(index) }
            }
        }
    }
}

/// Union-find with path halving.
struct Forest {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ item: Int) -> Int {
        var current = item
        while parent[current] != current {
            parent[current] = parent[parent[current]]
            current = parent[current]
        }
        return current
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        if rootA != rootB { parent[max(rootA, rootB)] = min(rootA, rootB) }
    }
}
