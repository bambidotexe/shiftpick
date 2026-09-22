import Foundation

/// AppKit's selection model over one reading order, as a value. Measured on `NSTableView` and held
/// against Finder's list view (the spec's Appendix A): the state is the set of selected positions and one
/// anchor, which may be deselected or absent, and nothing else is remembered.
///
/// Positions are dense, `0..<count`, in reading order. Nothing here knows what a position is on screen.
public enum ShiftClick {
    /// The position a ⇧ Shift click measures from: the anchor while it is selected; else the first selected
    /// position after it, however far; else the last selected position before it. An absent anchor counts
    /// as one before every position, so the first selected position stands in. nil when nothing is
    /// selected, which the caller decides about (`docs/functional.md` §2.1).
    public static func standIn(anchor: Int?, selection: Set<Int>) -> Int? {
        guard !selection.isEmpty else { return nil }
        if let anchor, selection.contains(anchor) { return anchor }
        let pivot = anchor ?? -1
        if let after = selection.filter({ $0 > pivot }).min() { return after }
        return selection.filter { $0 < pivot }.max()
    }

    /// The selection after a ⇧ Shift click on `target` measured from `anchor`, ascending: the old selection
    /// minus every maximal run of consecutive selected positions the range `anchor...target` intersects,
    /// plus the range. A run that intersects the range and reaches outside it contains the range's end on
    /// that side, so when that end is selected, walking outwards from it while positions stay selected
    /// removes exactly the part of the touched run that the range would not replace anyway. An end that is
    /// not selected has no run to remove on its side: a selected run next to the range, but not in it,
    /// stays (measured: {2,5,8} with anchor 8, click 6, leaves 5 selected).
    ///
    /// nil when either end is not a position. Selected positions outside the order are dropped.
    public static func resolve(anchor: Int, selection: Set<Int>, target: Int, count: Int) -> [Int]? {
        let order = 0..<count
        guard order.contains(anchor), order.contains(target) else { return nil }
        let range = min(anchor, target)...max(anchor, target)
        var kept = selection.filter { order.contains($0) }
        if kept.contains(range.lowerBound) {
            var below = range.lowerBound - 1
            while below >= 0, kept.contains(below) {
                kept.remove(below)
                below -= 1
            }
        }
        if kept.contains(range.upperBound) {
            var above = range.upperBound + 1
            while above < count, kept.contains(above) {
                kept.remove(above)
                above += 1
            }
        }
        kept.formUnion(range)
        return kept.sorted()
    }
}
