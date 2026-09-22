import CoreGraphics
import Foundation
import ShiftPickCore

/// Synthetic layouts, built the way Finder builds real ones, so a test can say what a range should be
/// without a Mac, a Finder or a click.
///
/// The numbers are the ones measured on macOS 27: a window's icons are 64 points square on a 116 point
/// pitch, the Desktop's are 72 on a 122 point pitch. **An item's frame is the icon's box**, so every frame
/// here is the same size whatever the name under it would be; `mixedLabelHeights` is the one that asks what
/// happens when they are not.
enum Layouts {
    static let windowSide: CGFloat = 64
    static let windowPitch = CGSize(width: 116, height: 116)
    static let desktopSide: CGFloat = 72
    static let desktopPitch = CGSize(width: 122, height: 122)

    /// The cells of a `rows` by `columns` lattice, in the order `flow` fills them. The same order
    /// `LayoutModel` has to work back out from the frames alone.
    static func cells(rows: Int, columns: Int, flow: Flow) -> [(row: Int, column: Int)] {
        var result: [(row: Int, column: Int)] = []
        switch flow {
        case .rowsFromLeft:
            for row in 0..<rows { for column in 0..<columns { result.append((row, column)) } }
        case .rowsFromRight:
            for row in 0..<rows { for column in stride(from: columns - 1, through: 0, by: -1) {
                result.append((row, column))
            } }
        case .columnsFromLeft:
            for column in 0..<columns { for row in 0..<rows { result.append((row, column)) } }
        case .columnsFromRight:
            for column in stride(from: columns - 1, through: 0, by: -1) { for row in 0..<rows {
                result.append((row, column))
            } }
        }
        return result
    }

    /// A lattice filled in flow order, stopping after `count` items so that the last line may be partial.
    /// `axOrder` is the flow order, which is what Finder reports.
    static func filled(rows: Int, columns: Int, count: Int? = nil, flow: Flow = .rowsFromLeft,
                       origin: CGPoint = CGPoint(x: 540, y: 250),
                       pitch: CGSize? = nil, side: CGFloat? = nil,
                       section: Int = 0, firstAXOrder: Int = 0) -> [LayoutItem] {
        let pitch = pitch ?? windowPitch
        let side = side ?? windowSide
        let wanted = count ?? rows * columns
        return cells(rows: rows, columns: columns, flow: flow).prefix(wanted).enumerated().map { order, cell in
            LayoutItem(frame: CGRect(x: origin.x + CGFloat(cell.column) * pitch.width,
                                     y: origin.y + CGFloat(cell.row) * pitch.height,
                                     width: side, height: side),
                       section: section, axOrder: firstAXOrder + order)
        }
    }

    /// A lattice tidied by hand: every icon of `filled` moved up to `amplitude` points off its cell on each
    /// axis, the same way every run for the same `seed`. `axOrder` stays the cell order, so a test can say
    /// which cell an icon came from.
    static func wobbled(rows: Int, columns: Int, amplitude: Int, seed: UInt64,
                        origin: CGPoint = CGPoint(x: 540, y: 250),
                        pitch: CGSize = desktopPitch, side: CGFloat = desktopSide,
                        firstAXOrder: Int = 0) -> [LayoutItem] {
        var generator = SeededGenerator(seed: seed)
        return filled(rows: rows, columns: columns, origin: origin, pitch: pitch, side: side,
                      firstAXOrder: firstAXOrder).map { item in
            let dx = CGFloat(Int.random(in: -amplitude...amplitude, using: &generator))
            let dy = CGFloat(Int.random(in: -amplitude...amplitude, using: &generator))
            return LayoutItem(frame: item.frame.offsetBy(dx: dx, dy: dy), axOrder: item.axOrder)
        }
    }

    /// One item at an arbitrary place, for the layouts nobody arranged.
    static func item(x: CGFloat, y: CGFloat, axOrder: Int = 0, section: Int = 0, isFile: Bool = true,
                     side: CGFloat? = nil) -> LayoutItem {
        let side = side ?? windowSide
        return LayoutItem(frame: CGRect(x: x, y: y, width: side, height: side),
                          section: section, axOrder: axOrder, isFile: isFile)
    }
}

/// A generator a test can seed, so a wobble is the same wobble every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
