import CoreGraphics
import Foundation

/// One cluster of a hand-placed view, fitted with rows and columns and read along its rows: rows top to
/// bottom, each row from the leading edge. A cluster whose rows are too wide to be lines, or whose icons
/// share no line with one another, is a scatter: it keeps an order (top edge, then leading edge) so that a
/// stand-in can be named across it, and every range to or from it is the rubber band
/// (`docs/functional.md` §3).
struct Grid {
    /// The cluster's items in reading order.
    let order: [Int]
    /// False for a scatter.
    let isGrid: Bool
    /// The cluster's top edge, and its leading edge as a sort key (the left edge, or the right edge negated
    /// for a right-to-left layout): clusters are ordered by these two, smaller first.
    let top: CGFloat
    let leading: CGFloat

    /// The rows are the centres' y values cut at every gap wider than `K.gridLineTolerancePitches` of the
    /// pitch, the columns the x values cut the same way (`Lattice.cluster`). The cluster is a grid when
    /// **no row is wider than that tolerance** — an icon a quarter pitch off its row is on it, a row that
    /// only exists because a scatter chained together is wider — and, past `K.gridAlwaysCount` icons, **some
    /// row or some column holds two icons**: icons that share no line with anyone, a staircase however even
    /// its steps, give nothing to read along. A column's width is no verdict: reading runs along rows, and
    /// an icon dropped between two columns, or a row packed tighter than the pitch, changes nothing about
    /// which icon follows which.
    ///
    /// Along a row the icons read by position. A column no wider than the tolerance is one cell, and the
    /// icons in it read in the order Accessibility listed them; a column wider than that is two columns an
    /// icon between them chained together, and its icons read by their own centres.
    static func fit(members: [Int], items: [LayoutItem], pitch: CGFloat, leadingIsLeft: Bool) -> Grid {
        let tolerance = max(K.gridLineTolerancePitches * pitch, 1)
        let ys = members.map { items[$0].reference.y }
        let xs = members.map { items[$0].reference.x }
        let rows = Lattice.cluster(ys, tolerance: tolerance)
        let columns = Lattice.cluster(xs, tolerance: tolerance)
        let sharesALine = members.count <= K.gridAlwaysCount
            || rows.count < members.count || columns.count < members.count
        let isGrid = sharesALine && Lattice.isTight(ys, rows.index, limit: tolerance)

        let top = members.map { items[$0].frame.minY }.min() ?? 0
        let leading = leadingIsLeft
            ? (members.map { items[$0].frame.minX }.min() ?? 0)
            : -(members.map { items[$0].frame.maxX }.max() ?? 0)

        let order: [Int]
        if isGrid {
            let position = cellPositions(xs, columns, tolerance: tolerance)
            order = members.indices.sorted { a, b in
                if rows.index[a] != rows.index[b] { return rows.index[a] < rows.index[b] }
                let leadA = leadingIsLeft ? position[a] : -position[a]
                let leadB = leadingIsLeft ? position[b] : -position[b]
                if leadA != leadB { return leadA < leadB }
                if items[members[a]].axOrder != items[members[b]].axOrder {
                    return items[members[a]].axOrder < items[members[b]].axOrder
                }
                return members[a] < members[b]
            }.map { members[$0] }
        } else {
            order = members.sorted { a, b in
                let frameA = items[a].frame, frameB = items[b].frame
                if frameA.minY != frameB.minY { return frameA.minY < frameB.minY }
                let leadA = leadingIsLeft ? frameA.minX : -frameA.maxX
                let leadB = leadingIsLeft ? frameB.minX : -frameB.maxX
                if leadA != leadB { return leadA < leadB }
                if items[a].axOrder != items[b].axOrder { return items[a].axOrder < items[b].axOrder }
                return a < b
            }
        }
        return Grid(order: order, isGrid: isGrid, top: top, leading: leading)
    }

    /// Per value, where its column sits for reading: the column's smallest value when the column is no
    /// wider than `tolerance`, so that every icon of one cell shares a position, and the value itself when
    /// the column is wider.
    private static func cellPositions(_ values: [CGFloat], _ columns: (index: [Int], count: Int),
                                      tolerance: CGFloat) -> [CGFloat] {
        var low = [CGFloat](repeating: .greatestFiniteMagnitude, count: columns.count)
        var high = [CGFloat](repeating: -.greatestFiniteMagnitude, count: columns.count)
        for (position, column) in columns.index.enumerated() {
            low[column] = min(low[column], values[position])
            high[column] = max(high[column], values[position])
        }
        return values.indices.map { position in
            let column = columns.index[position]
            return high[column] - low[column] <= tolerance ? low[column] : values[position]
        }
    }
}
