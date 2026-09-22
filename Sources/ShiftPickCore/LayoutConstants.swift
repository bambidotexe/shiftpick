import CoreGraphics

/// The numbers the inferred grids are built on. They are best-effort tolerances for a view somebody laid
/// out by hand, not guarantees, and they live here rather than in `Constants.swift` so that changing one
/// is not a change to the safety layer (`scripts/safety-gates.sh`).
extension K {
    /// How far apart two icons may be on each axis, in pitches, and still belong to one grid; and how far
    /// a neighbour may sit and still be a sample of the pitch. A grid's orthogonal and diagonal neighbours
    /// are one pitch apart and a wobble; an empty row or column between two groups is two pitches less a
    /// wobble. One and a half sits in the middle: a twenty-point wobble on a 122-point Desktop pitch leaves
    /// neighbours at most 162 apart and two groups at least 204, with the link at 183. Both cliffs meet at
    /// a wobble of a quarter pitch.
    public static let gridLinkPitches: CGFloat = 1.5

    /// The gap, in pitches, that separates two rows or two columns of an inferred grid, and the widest a
    /// row may be before the cluster is a scatter with no grid. An icon a quarter pitch off its row is on
    /// it, so a row of hand-placed icons is up to half a pitch wide; a row that only exists because a
    /// scatter chained together is wider.
    public static let gridLineTolerancePitches: CGFloat = 0.5

    /// The most icons a cluster may hold and be a grid whatever its shape. One icon is a grid of one; two
    /// are a row, a column or a diagonal, and all three read the same way. From three on, a grid needs a
    /// row or a column that two icons share: icons that share no line with anyone, a staircase however
    /// even its steps, give nothing to read along, and are a scatter.
    public static let gridAlwaysCount = 2

    /// How far an icon looks for its nearest neighbour when the pitch is measured, in icon sides. A window's
    /// pitch is under two sides of a 64-point icon and the Desktop's under two of a 72-point one; an icon
    /// with nothing within three is not evidence about the pitch. The side is never taken under
    /// `cellSideFloor`.
    public static let neighbourReachSides: CGFloat = 3

    /// The least an icon's side counts as wherever the pitch is measured in sides, in points. Finder's cell
    /// is the label's below about 64 points, not the icon's: a 16-point icon sits under the same label as a
    /// 64-point one, on a pitch that does not shrink with it, so three of its own sides find nobody where
    /// three of a 64-point icon's find every neighbour; and two small icons dropped within a label's width
    /// of each other share a cell, as two 64-point icons that close do. So the reach, the overlap and the
    /// pitch of an icon with nobody near are taken in sides of an icon at least this big, and a small icon's
    /// grid is read exactly as the 64-point window's was measured to be. A larger icon is its own measure.
    public static let cellSideFloor: CGFloat = 64

    /// How close two centres are, in icon sides, for the icons to overlap rather than neighbour each other:
    /// one side, on both axes. Finder never draws two cells closer than an icon's side, so a centre that
    /// close is an icon somebody dropped on another, a pile, and says nothing about the pitch.
    public static let overlapSides: CGFloat = 1

    /// The pitch assumed when no icon has a neighbour within reach, in icon sides: one and a half, under
    /// where Finder's own pitches sit (116 points for 64-point icons, 122 for 72, both about 1.75). It only
    /// ever governs icons with nothing near them, each a cluster of one, and a pile with nothing else.
    public static let lonePitchSides: CGFloat = 1.5
}
