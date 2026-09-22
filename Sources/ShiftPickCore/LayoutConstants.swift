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
    /// row or a column may be before the cluster is a scatter with no grid. An icon a quarter pitch off its
    /// line is on it, so a line of hand-placed icons is up to half a pitch wide; a line that only exists
    /// because a scatter chained together is wider.
    public static let gridLineTolerancePitches: CGFloat = 0.5

    /// How far an icon looks for its nearest neighbour when the pitch is measured, in icon sides. A window's
    /// pitch is under two sides and the Desktop's under two as well; an icon with nothing within three is
    /// not evidence about the pitch.
    public static let neighbourReachSides: CGFloat = 3

    /// How close two centres are, in icon sides, for the icons to overlap rather than neighbour each other:
    /// one side, on both axes. Finder never draws two cells closer than an icon's side, so a centre that
    /// close is an icon somebody dropped on another, a pile, and says nothing about the pitch.
    public static let overlapSides: CGFloat = 1

    /// The pitch assumed when no icon has a neighbour within reach, in icon sides: one and a half, under
    /// where Finder's own pitches sit (116 points for 64-point icons, 122 for 72, both about 1.75). It only
    /// ever governs icons with nothing near them, each a cluster of one, and a pile with nothing else.
    public static let lonePitchSides: CGFloat = 1.5
}
