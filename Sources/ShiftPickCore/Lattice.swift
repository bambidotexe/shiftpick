import CoreGraphics
import Foundation

/// The rows and columns a set of icons sits in, and how far apart they are.
///
/// Built in two passes, because the tolerance the rule asks for — half the median cell size — is not known
/// until the cells are. The first pass only has to tell two neighbouring lines apart, so it uses a quarter
/// of an icon's own side, which is far smaller than any pitch Finder lays out; the gaps between what that
/// finds give the pitch, and the second pass clusters again at half of it.
struct Lattice {
    /// Per item, the row and the column it landed in. Both count from 0 at the top and at the left.
    let row: [Int]
    let column: [Int]
    let rowCount: Int
    let columnCount: Int
    let rowPitch: CGFloat
    let columnPitch: CGFloat
    /// True when every cluster is tight: no item sits far enough from its line for the line to be a
    /// coincidence. A smeared cluster is what a hand-placed folder looks like after single-linkage
    /// clustering has chained its icons together.
    let isTight: Bool

    static func build(_ items: [LayoutItem]) -> Lattice {
        let ys = items.map(\.reference.y)
        let xs = items.map(\.reference.x)
        let medianHeight = median(items.map(\.frame.height)) ?? 1
        let medianWidth = median(items.map(\.frame.width)) ?? 1

        let rowPitch = pitch(of: ys, snap: max(2, medianHeight / 4), fallback: medianHeight * 1.5)
        let columnPitch = pitch(of: xs, snap: max(2, medianWidth / 4), fallback: medianWidth * 1.5)
        let rows = cluster(ys, tolerance: rowPitch / 2)
        let columns = cluster(xs, tolerance: columnPitch / 2)

        let tight = isTight(ys, rows.index, limit: rowPitch / 4)
            && isTight(xs, columns.index, limit: columnPitch / 4)
        return Lattice(row: rows.index, column: columns.index,
                       rowCount: rows.count, columnCount: columns.count,
                       rowPitch: rowPitch, columnPitch: columnPitch, isTight: tight)
    }

    // MARK: - The pieces

    /// Single-linkage clustering along one axis: a value opens a new cluster when it is more than
    /// `tolerance` past the value before it. Deterministic whatever order equal values arrive in, because
    /// equal values always land in the same cluster.
    static func cluster(_ values: [CGFloat], tolerance: CGFloat) -> (index: [Int], count: Int) {
        guard !values.isEmpty else { return ([], 0) }
        let order = values.indices.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0] < values[$1] }
        var index = [Int](repeating: 0, count: values.count)
        var current = 0
        var previous = values[order[0]]
        for (rank, position) in order.enumerated() {
            if rank > 0, values[position] - previous > tolerance { current += 1 }
            index[position] = current
            previous = values[position]
        }
        return (index, current + 1)
    }

    /// The distance between two neighbouring lines. The coarse pass groups what is plainly on one line;
    /// the median gap between those groups is the pitch. One group means one line, and then nothing has
    /// been measured, so the caller's fallback stands.
    private static func pitch(of values: [CGFloat], snap: CGFloat, fallback: CGFloat) -> CGFloat {
        let coarse = cluster(values, tolerance: snap)
        guard coarse.count > 1 else { return max(fallback, 1) }
        var sums = [CGFloat](repeating: 0, count: coarse.count)
        var counts = [CGFloat](repeating: 0, count: coarse.count)
        for (position, group) in coarse.index.enumerated() {
            sums[group] += values[position]
            counts[group] += 1
        }
        let centres = (0..<coarse.count).map { sums[$0] / counts[$0] }.sorted()
        let gaps = zip(centres.dropFirst(), centres).map { $0 - $1 }
        return max(median(gaps) ?? fallback, 1)
    }

    /// Whether no cluster is wider than `limit`. A line of icons Finder placed is exact; a line that only
    /// exists because single linkage walked from one hand-placed icon to the next is not.
    static func isTight(_ values: [CGFloat], _ index: [Int], limit: CGFloat) -> Bool {
        guard let groups = index.max() else { return true }
        var low = [CGFloat](repeating: .greatestFiniteMagnitude, count: groups + 1)
        var high = [CGFloat](repeating: -.greatestFiniteMagnitude, count: groups + 1)
        for (position, group) in index.enumerated() {
            low[group] = min(low[group], values[position])
            high[group] = max(high[group], values[position])
        }
        for group in 0...groups where high[group] - low[group] > max(limit, 1) { return false }
        return true
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
