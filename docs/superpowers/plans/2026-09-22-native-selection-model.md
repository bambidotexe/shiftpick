# Native Selection Model, Grid Inference and No Settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ⇧ Shift click in a Finder icon view leaves exactly the selection the same clicks leave in a list view, hand-placed views get inferred grids with a line fallback, and the Selection page with its two switches is gone.

**Architecture:** AppKit's measured model (selection + anchor, runs replaced, stand-in for a deselected anchor) becomes a pure value in Core (`ShiftClick`) over one reading order; `LayoutModel` supplies that order (flow order for arranged views, clusters fitted with grids for hand-placed ones) and answers a range as an ordered slice or a line. `ShiftClickResolver` reads Finder's selection live, asks Core, and sets the result in the one call it already makes. The kill switch leaves `TapLifecycle`; the breaker's retry moves to a button on the System page.

**Tech Stack:** Swift 5.10 SwiftPM, macOS 26+, XCTest, no dependencies. Core imports Foundation and CoreGraphics only.

**Spec:** `docs/superpowers/specs/2026-09-22-native-selection-model-design.md` (read it first; §2 is the model, §5 the grid algorithm, §10 the rules of `functional.md` it overrules).

## Global Constraints

- **Invoke the `shiftpick-safety-nets` skill before Tasks 7, 9 and 10** (they touch `ShiftClickResolver.swift`, `ClickGuard.swift`, `TapLifecycle.swift`, `ShiftPickEngine.swift`, all in `SAFETY_FILES`). No net is loosened; `SafetyNetTests` checks that fail because code moved are moved with the code, keeping what they assert.
- **Invoke `macos-building-settings-pages` before Task 10** (pages, rows, words).
- `ShiftPickCore` imports Foundation and CoreGraphics only and never reads a clock (`PurityTests`).
- Every user-facing string is an accessor in `Core/Strings*.swift` switching over `Language`, English and French together; keys are written *symbol then name*: ⇧ Shift, ⌘ Command. No dash longer than `-` anywhere (`LocalizationTests`).
- Numbers for the geometry go in `Core/LayoutConstants.swift`, never `Core/Constants.swift`.
- Comments state the present rule, never the history. `docs/functional.md` is updated in the same commit as the behaviour it describes (Task 12 does the documents; each earlier task's commit message names the section it owes).
- `swift build` is the truth; `swift test` prints **two** summary lines: count both. `swift test --filter <Suite>` runs one suite.
- Commit per task, conventional commits, files staged by path (never `git add -A`), with the trailers:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR
  ```
- Never install, build ad hoc, run `tccutil`, create a tap or post an event. Hand over with: *§9 of `docs/manual-test-checklist.md` is owed on an installed build before the next release.*

## File structure

| File | Responsibility |
|---|---|
| **Create** `Sources/ShiftPickCore/ShiftClick.swift` | AppKit's rule over positions `0..<count`: stand-in and run replacement. No geometry. |
| **Create** `Sources/ShiftPickCore/LayoutConstants.swift` | The four geometry numbers, as `extension K`. |
| **Create** `Sources/ShiftPickCore/Clusters.swift` | Pitch (median nearest-neighbour distance) and connected components under the link rule, via a spatial hash and union-find. |
| **Create** `Sources/ShiftPickCore/Grid.swift` | One cluster's rows and columns, whether they make a grid, and its reading order. |
| **Create** `Sources/ShiftPickCore/LineBand.swift` | The one-icon-thick band between two centres and the exact rectangle test. |
| **Modify** `Sources/ShiftPickCore/LayoutModel.swift` | Positions for every item, `effectiveAnchor`, `range` as a shape, `shiftClick`, `firstItem`. Keeps the arranged path. |
| **Modify** `Sources/ShiftPickCore/Lattice.swift` | `isTight` becomes internal (Grid uses it). |
| **Modify** `Sources/ShiftPickCore/Settings.swift`, `TapLifecycle.swift`, `HealthReport.swift`, `HealthRules.swift`, `StringsSettings.swift`, `StringsMenu.swift`, `StringsHealthPage.swift`, `StringsSystemPage.swift`; **delete** `StringsSelectionPage.swift` | The two switches gone; the retry button's words. |
| **Modify** `Sources/ShiftPickPlatform/FinderAX.swift` | `selection` keeps unmapped elements; `isScrolled`. |
| **Modify** `Sources/ShiftPickPlatform/ClickGuard.swift` | `init(hooks:)`; the sentinel notes the anchor for a press with ⌘ Command or without ⇧ Shift. |
| **Modify** `Sources/ShiftPickApp/ShiftClickResolver.swift`, `ShiftPickEngine.swift`, `MenuBarController.swift`, `SettingsView.swift`, `SettingsSystemPage.swift`, `SettingsHealthPage.swift`, `HealthCheck.swift`; **delete** `SettingsSelectionPage.swift` | The click, the wiring, four pages, the retry button. |
| **Modify** `Tools/axdump/main.swift` | `range` prints shape, stand-in and the selection the click would leave. |
| **Tests** create `ShiftClickTests`, `ClustersTests`, `GridTests`, `LineBandTests`, `StandInTests`; modify `RangeSelectionTests`, `LatticeTests`, `SettingsTests`, `HealthTests`, `LocalizationTests`, `TapLifecycleTests`, `TapLifecycleInvariantTests`, `SafetyNetTests`; delete `AnchorTests`. |

---

### Task 0: The owner's measurements (no code)

**Files:** none. Output: the owner's answers, written into the spec's §11 table as a third column.

The owner performs protocol **P** of the spec (§11) in a Finder list view of twelve files, and **M2**, **M3** and one more, **M4**, with `swift run axdump`:

- **M2**: in icon view select three icons, scroll them off screen, run `swift run axdump views` and note whether the container's selected children still name them (the probe prints the selection count in `range`; add a temporary `print` if needed, not committed).
- **M3**: in icon view, with two icons selected, ⌘ Command ⇧ Shift click a third: note whether Finder toggled it.
- **M4**: open a folder of 200 files in icon view, run `swift run axdump tree 6`, note the `AXScrollArea`'s frame and its `AXCollectionList` child's frame; scroll down; run it again. The container's `minY` should drop below the area's `minY` when scrolled. This is what Task 6's `isScrolled` reads.

- [ ] **Step 1: Hand the protocol to the owner** (the table in spec §11), and record every answer beside the expected column.
- [ ] **Step 2: If any P row differs from AppKit**, stop and update spec §2 before Task 1; the test vectors in Task 1 are then corrected to Finder's answers.
- [ ] **Step 3: If M3 says Finder's icon view does not toggle on ⌘ Command ⇧ Shift**, Task 7 keeps the pass-through anyway (the click is Finder's own) and the spec's §2.4 notes what Finder does.
- [ ] **Step 4: If M4 shows the container does not move**, Task 6 reads the scroll area's vertical `AXScrollBar`'s `AXValue` (0 means top) instead; note it in `docs/macOS.md` in Task 12.

Tasks 1 to 5 do not depend on these answers and may start at once.

---

### Task 1: `ShiftClick`, the measured rule over positions

**Files:**
- Create: `Sources/ShiftPickCore/ShiftClick.swift`
- Test: `Tests/ShiftPickCoreTests/ShiftClickTests.swift`

**Interfaces:**
- Produces: `ShiftClick.standIn(anchor: Int?, selection: Set<Int>) -> Int?` and `ShiftClick.resolve(anchor: Int, selection: Set<Int>, target: Int, count: Int) -> [Int]?` (ascending positions). Task 5 calls both.

- [ ] **Step 1: Write the failing tests** (the spec's Appendix A, 1-based there, 0-based here)

```swift
import XCTest
import ShiftPickCore

/// AppKit's selection model, replayed from the measurements in the spec's Appendix A. Rows are 1-based in
/// the spec and 0-based here; `r(a, b)` is the closed range a...b as an array.
final class ShiftClickTests: XCTestCase {
    private func r(_ a: Int, _ b: Int) -> [Int] { Array(a...b) }

    /// One measured state: the selection and the anchor before, and the selection after a ⇧ Shift click on
    /// each of the twelve rows.
    private struct Measured {
        let name: String
        let selection: [Int]
        let anchor: Int?
        let after: [[Int]]   // index t-1 holds the result of a click on row t
    }

    private lazy var measured: [Measured] = [
        Measured(name: "A", selection: r(1, 5), anchor: 1,
                 after: (1...12).map { r(1, $0) }),
        Measured(name: "B", selection: [2, 5, 8], anchor: 8,
                 after: [r(1, 8), r(2, 8), r(2, 8), [2] + r(4, 8), [2] + r(5, 8), [2] + r(5, 8), [2, 5, 7, 8],
                         [2, 5, 8], [2, 5, 8, 9], [2, 5] + r(8, 10), [2, 5] + r(8, 11), [2, 5] + r(8, 12)]),
        Measured(name: "C", selection: [1, 2, 4, 5], anchor: 3,
                 after: [r(1, 4), [2, 3, 4], r(1, 4), [1, 2, 4], [1, 2, 4, 5], [1, 2] + r(4, 6), [1, 2] + r(4, 7),
                         [1, 2] + r(4, 8), [1, 2] + r(4, 9), [1, 2] + r(4, 10), [1, 2] + r(4, 11), [1, 2] + r(4, 12)]),
        Measured(name: "E", selection: [3, 7, 8, 9], anchor: 9,
                 after: [r(1, 9), r(2, 9), r(3, 9), r(3, 9), [3] + r(5, 9), [3] + r(6, 9), [3, 7, 8, 9], [3, 8, 9],
                         [3, 9], [3, 9, 10], [3, 9, 10, 11], [3] + r(9, 12)]),
        Measured(name: "F", selection: [3, 7], anchor: 3,
                 after: [[1, 2, 3, 7], [2, 3, 7], [3, 7], [3, 4, 7], [3, 4, 5, 7], r(3, 7), r(3, 7), r(3, 8),
                         r(3, 9), r(3, 10), r(3, 11), r(3, 12)]),
        Measured(name: "G", selection: [6, 7, 8], anchor: 5,
                 after: [r(1, 6), r(2, 6), r(3, 6), r(4, 6), [5, 6], [6], [6, 7], [6, 7, 8], r(6, 9), r(6, 10),
                         r(6, 11), r(6, 12)]),
        Measured(name: "H", selection: [5, 6, 8], anchor: 7,
                 after: [r(1, 8), r(2, 8), r(3, 8), r(4, 8), r(5, 8), [6, 7, 8], r(5, 8), [5, 6, 8], [5, 6, 8, 9],
                         [5, 6] + r(8, 10), [5, 6] + r(8, 11), [5, 6] + r(8, 12)]),
        Measured(name: "I", selection: r(6, 10), anchor: 10,
                 after: [r(1, 10), r(2, 10), r(3, 10), r(4, 10), r(5, 10), r(6, 10), r(7, 10), r(8, 10), [9, 10],
                         [10], [10, 11], [10, 11, 12]]),
        Measured(name: "K", selection: [9], anchor: 4,
                 after: [r(1, 9), r(2, 9), r(3, 9), r(4, 9), r(5, 9), r(6, 9), r(7, 9), [8, 9], [9], [9, 10],
                         [9, 10, 11], r(9, 12)]),
        Measured(name: "L", selection: [2], anchor: 9,
                 after: [[1, 2], [2], [2, 3], r(2, 4), r(2, 5), r(2, 6), r(2, 7), r(2, 8), r(2, 9), r(2, 10),
                         r(2, 11), r(2, 12)]),
        Measured(name: "M", selection: [4, 5, 6, 9, 11], anchor: 10,
                 after: [r(1, 11), r(2, 11), r(3, 11), r(4, 11), r(5, 11), r(6, 11), r(4, 11), [4, 5, 6] + r(8, 11),
                         [4, 5, 6, 9, 10, 11], [4, 5, 6, 9, 10, 11], [4, 5, 6, 9, 11], [4, 5, 6, 9, 11, 12]]),
        Measured(name: "N", selection: [1, 2, 3, 6, 8], anchor: 8,
                 after: [r(1, 8), r(2, 8), r(3, 8), r(1, 8), [1, 2, 3] + r(5, 8), [1, 2, 3, 6, 7, 8], [1, 2, 3, 6, 7, 8],
                         [1, 2, 3, 6, 8], [1, 2, 3, 6, 8, 9], [1, 2, 3, 6] + r(8, 10), [1, 2, 3, 6] + r(8, 11),
                         [1, 2, 3, 6] + r(8, 12)]),
        Measured(name: "P", selection: [2, 5], anchor: 9,
                 after: [r(1, 5), r(2, 5), r(2, 5), [2, 4, 5], [2, 5], [2, 5, 6], [2] + r(5, 7), [2] + r(5, 8),
                         [2] + r(5, 9), [2] + r(5, 10), [2] + r(5, 11), [2] + r(5, 12)]),
        Measured(name: "Q", selection: [2, 7], anchor: 4,
                 after: [r(1, 7), r(2, 7), r(2, 7), [2] + r(4, 7), [2] + r(5, 7), [2, 6, 7], [2, 7], [2, 7, 8],
                         [2] + r(7, 9), [2] + r(7, 10), [2] + r(7, 11), [2] + r(7, 12)]),
        Measured(name: "U", selection: [1, 3], anchor: 11,
                 after: [[1, 2, 3], [1, 2, 3], [1, 3], [1, 3, 4], [1] + r(3, 5), [1] + r(3, 6), [1] + r(3, 7),
                         [1] + r(3, 8), [1] + r(3, 9), [1] + r(3, 10), [1] + r(3, 11), [1] + r(3, 12)]),
        Measured(name: "V", selection: [10, 12], anchor: 2,
                 after: [r(1, 10) + [12], r(2, 10) + [12], r(3, 10) + [12], r(4, 10) + [12], r(5, 10) + [12],
                         r(6, 10) + [12], r(7, 10) + [12], r(8, 10) + [12], [9, 10, 12], [10, 12], [10, 11, 12],
                         [10, 11, 12]]),
    ]

    private func zeroBased(_ rows: [Int]) -> [Int] { rows.map { $0 - 1 } }

    func testEveryMeasuredStateIsReproduced() {
        for state in measured {
            let selection = Set(zeroBased(state.selection))
            let anchor = state.anchor.map { $0 - 1 }
            let from = ShiftClick.standIn(anchor: anchor, selection: selection)
            XCTAssertNotNil(from, state.name)
            for target in 0..<12 {
                let result = ShiftClick.resolve(anchor: from!, selection: selection, target: target, count: 12)
                XCTAssertEqual(result, zeroBased(state.after[target]), "\(state.name), click on row \(target + 1)")
            }
        }
    }

    // MARK: - The stand-in

    func testASelectedAnchorStandsForItself() {
        XCTAssertEqual(ShiftClick.standIn(anchor: 4, selection: [1, 4, 7]), 4)
    }

    func testADeselectedAnchorIsStoodInByTheFirstSelectedPositionAfterIt() {
        // {2,7} with anchor 4: 2 is nearer, 7 is after. Measured: 7.
        XCTAssertEqual(ShiftClick.standIn(anchor: 3, selection: [1, 6]), 6)
        XCTAssertEqual(ShiftClick.standIn(anchor: 2, selection: [0, 1, 3, 4]), 3)
    }

    func testElseByTheLastSelectedPositionBeforeIt() {
        XCTAssertEqual(ShiftClick.standIn(anchor: 8, selection: [1, 4]), 4)
    }

    func testNoAnchorCountsAsOneBeforeEverything() {
        XCTAssertEqual(ShiftClick.standIn(anchor: nil, selection: [2, 3, 4]), 2)
    }

    func testNothingSelectedHasNoStandIn() {
        XCTAssertNil(ShiftClick.standIn(anchor: 5, selection: []))
        XCTAssertNil(ShiftClick.standIn(anchor: nil, selection: []))
    }

    // MARK: - The run rule, in words

    func testARunTheRangeTouchesGoesWhole() {
        // {2,5,6,7,8} anchor 8, click 10: the run 5...8 goes, 5 to 7 with it; {2} stays.
        XCTAssertEqual(ShiftClick.resolve(anchor: 7, selection: [1, 4, 5, 6, 7], target: 9, count: 12), [1, 7, 8, 9])
    }

    func testARunTheRangeDoesNotTouchStays() {
        XCTAssertEqual(ShiftClick.resolve(anchor: 4, selection: [0, 1, 2, 4], target: 6, count: 12), [0, 1, 2, 4, 5, 6])
    }

    func testARunAdjacentToTheRangeButNotInsideItStays() {
        // {2,5,8} anchor 8, click 6: 5 is next to 6 and is not touched.
        XCTAssertEqual(ShiftClick.resolve(anchor: 7, selection: [1, 4, 7], target: 5, count: 12), [1, 4, 5, 6, 7])
    }

    func testTheRangeIsSymmetricAndTotal() {
        for anchor in 0..<12 {
            for target in 0..<12 {
                let one = ShiftClick.resolve(anchor: anchor, selection: [0, 3, 4, 9], target: target, count: 12)
                let other = ShiftClick.resolve(anchor: target, selection: [0, 3, 4, 9], target: anchor, count: 12)
                XCTAssertEqual(one, other)
                XCTAssertTrue(one?.contains(anchor) == true && one?.contains(target) == true)
                XCTAssertEqual(one, one?.sorted())
            }
        }
    }

    func testAPositionOutsideTheOrderIsRefused() {
        XCTAssertNil(ShiftClick.resolve(anchor: 12, selection: [], target: 3, count: 12))
        XCTAssertNil(ShiftClick.resolve(anchor: 0, selection: [], target: -1, count: 12))
        XCTAssertEqual(ShiftClick.resolve(anchor: 0, selection: [40], target: 2, count: 12), [0, 1, 2],
                       "a selected position outside the order is dropped, never kept")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ShiftClickTests`
Expected: compile error, `cannot find 'ShiftClick' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
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
    /// plus the range. A run that intersects the range and reaches outside it is contiguous with the
    /// position just outside the range, so walking outwards from each end while positions stay selected
    /// removes exactly the parts of touched runs that the range would not replace anyway.
    ///
    /// nil when either end is not a position. Selected positions outside the order are dropped.
    public static func resolve(anchor: Int, selection: Set<Int>, target: Int, count: Int) -> [Int]? {
        let order = 0..<count
        guard order.contains(anchor), order.contains(target) else { return nil }
        let range = min(anchor, target)...max(anchor, target)
        var kept = selection.filter { order.contains($0) }
        var below = range.lowerBound - 1
        while below >= 0, kept.contains(below) {
            kept.remove(below)
            below -= 1
        }
        var above = range.upperBound + 1
        while above < count, kept.contains(above) {
            kept.remove(above)
            above += 1
        }
        kept.formUnion(range)
        return kept.sorted()
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ShiftClickTests`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShiftPickCore/ShiftClick.swift Tests/ShiftPickCoreTests/ShiftClickTests.swift
git commit -m "feat(core): the measured selection rule over one reading order

A ⇧ Shift click keeps the selection and one anchor and nothing else: the
range replaces every run of selected positions it touches, a deselected
anchor is stood in by the first selected position after it, else the last
before it. Replayed from the AppKit measurements in the spec.

Owes docs/functional.md §2 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 2: `LayoutConstants` and `Clusters`

**Files:**
- Create: `Sources/ShiftPickCore/LayoutConstants.swift`
- Create: `Sources/ShiftPickCore/Clusters.swift`
- Test: `Tests/ShiftPickCoreTests/ClustersTests.swift`

**Interfaces:**
- Produces: `K.gridLinkPitches`, `K.gridLineTolerancePitches`, `K.lineThicknessSides`, `K.neighbourReachSides` (all `CGFloat`); `struct Clusters { let index: [Int]; let count: Int; let pitch: CGFloat; static func build(_ items: [LayoutItem]) -> Clusters }`. Tasks 3 and 5 use them.

- [ ] **Step 1: Write the failing tests**

```swift
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

    func testClusterNumbersAreDenseFromZero() {
        var items = Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 1000, y: 100), firstAXOrder: 2)
        items += Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 900), firstAXOrder: 4)
        let clusters = Clusters.build(items)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertEqual(Set(clusters.index), [0, 1, 2])
    }
}

/// A generator the test can seed, so a wobble is the same wobble every run.
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ClustersTests`
Expected: compile error, `cannot find 'Clusters' in scope`.

- [ ] **Step 3: Write the constants**

```swift
import CoreGraphics

/// The numbers the inferred grids are built on. They are best-effort tolerances for a view somebody laid
/// out by hand, not guarantees, and they live here rather than in `Constants.swift` so that changing one
/// is not a change to the safety layer (`scripts/safety-gates.sh`).
extension K {
    /// How far apart two icons may be on each axis, in pitches, and still belong to one grid. A grid's
    /// orthogonal and diagonal neighbours are within one pitch and a little wobble; an empty row or column
    /// between two groups is two pitches, and separates them.
    public static let gridLinkPitches: CGFloat = 1.5

    /// The gap, in pitches, that separates two rows or two columns of an inferred grid, and the widest a
    /// row or a column may be before the cluster is a scatter with no grid: a line that only exists because
    /// a scatter chained together is wider than half a pitch.
    public static let gridLineTolerancePitches: CGFloat = 0.5

    /// The thickness of the line drawn between two icons that share no grid, in icon sides.
    public static let lineThicknessSides: CGFloat = 1

    /// How far an icon looks for its nearest neighbour when the pitch is measured, in icon sides. A window's
    /// pitch is under two sides and the Desktop's under two as well; an icon with nothing within three is
    /// not evidence about the pitch.
    public static let neighbourReachSides: CGFloat = 3
}
```

- [ ] **Step 4: Write `Clusters`**

```swift
import CoreGraphics
import Foundation

/// The groups of icons that could each be one grid: icons chained together by neighbours within
/// `K.gridLinkPitches` of each other on both axes. Built only for a view Finder is not laying out.
struct Clusters {
    /// Per item, its cluster, numbered densely from 0 in no particular order; `LayoutModel` orders them.
    let index: [Int]
    let count: Int
    /// The distance between two neighbouring icons: the median, over the icons, of the distance to the
    /// nearest other icon within `K.neighbourReachSides`. It survives a hand-placed wobble that the
    /// lattice's coarse pitch does not.
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

    /// The median nearest-neighbour distance, or one and a half sides when no icon has a neighbour within
    /// reach. Never below one point.
    static func measurePitch(_ items: [LayoutItem], side: CGFloat) -> CGFloat {
        let reach = K.neighbourReachSides * side
        let hash = SpatialHash(items, cell: reach)
        var nearest: [CGFloat] = []
        for index in items.indices {
            let point = items[index].reference
            var best = CGFloat.greatestFiniteMagnitude
            hash.forEachNeighbour(of: point) { other in
                guard other != index else { return }
                let candidate = items[other].reference
                best = min(best, hypot(candidate.x - point.x, candidate.y - point.y))
            }
            if best <= reach { nearest.append(best) }
        }
        return max(Lattice.median(nearest) ?? side * 1.5, 1)
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
        Cell(x: Int((point.x / cell).rounded(.down)), y: Int((point.y / cell).rounded(.down)))
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
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter ClustersTests`
Expected: `Executed 8 tests, with 0 failures`. Then `swift test --filter PurityTests` still green (Foundation and CoreGraphics only).

- [ ] **Step 6: Commit**

```bash
git add Sources/ShiftPickCore/LayoutConstants.swift Sources/ShiftPickCore/Clusters.swift Tests/ShiftPickCoreTests/ClustersTests.swift
git commit -m "feat(core): clusters of icons under a link rule, and the pitch they sit at

Owes docs/functional.md §3 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 3: `Grid`, one cluster read along its rows

**Files:**
- Create: `Sources/ShiftPickCore/Grid.swift`
- Modify: `Sources/ShiftPickCore/Lattice.swift` (`isTight` from `private static` to `static`)
- Test: `Tests/ShiftPickCoreTests/GridTests.swift`

**Interfaces:**
- Consumes: `Lattice.cluster`, `Lattice.isTight`, `K.gridLineTolerancePitches`.
- Produces: `struct Grid { let order: [Int]; let isGrid: Bool; let top: CGFloat; let leading: CGFloat; static func fit(members: [Int], items: [LayoutItem], pitch: CGFloat, leadingIsLeft: Bool) -> Grid }`. Task 5 uses it.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import XCTest
@testable import ShiftPickCore

/// One cluster fitted with rows and columns and read along its rows, or refused as a scatter.
final class GridTests: XCTestCase {
    private let pitch = Layouts.windowPitch.width

    func testAnExactGridReadsAlongItsRowsFromTheLeft() {
        let items = Layouts.filled(rows: 2, columns: 3)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    func testARightToLeftLayoutReadsEachRowFromTheRight() {
        let items = Layouts.filled(rows: 2, columns: 3)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: false)
        XCTAssertEqual(grid.order, [2, 1, 0, 5, 4, 3])
    }

    func testAHoleIsSkippedInTheOrder() {
        var items = Layouts.filled(rows: 2, columns: 3)
        items.remove(at: 1)
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4])
    }

    /// Up to a quarter of a pitch off the line either way is a hand-placed row, not a scatter.
    func testAWobblyGridIsStillAGrid() {
        let jitter: [(CGFloat, CGFloat)] = [(-20, 15), (10, -25), (25, 20), (-15, -10), (0, 28), (18, -18)]
        let items = zip(Layouts.filled(rows: 2, columns: 3, pitch: Layouts.desktopPitch, side: Layouts.desktopSide), jitter)
            .enumerated().map { order, pair in
                LayoutItem(frame: pair.0.frame.offsetBy(dx: pair.1.0, dy: pair.1.1), axOrder: order)
            }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: Layouts.desktopPitch.width,
                            leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    /// A row wider than half a pitch is a scatter chained together, and its order is by top edge then left.
    func testASmearedClusterIsAScatterOrderedTopToBottom() {
        let items = (0..<6).map { Layouts.item(x: 100 + CGFloat($0) * 40, y: 100 + CGFloat($0) * 30, axOrder: 5 - $0) }
        let grid = Grid.fit(members: Array(items.indices), items: items, pitch: 120, leadingIsLeft: true)
        XCTAssertFalse(grid.isGrid)
        XCTAssertEqual(grid.order, [0, 1, 2, 3, 4, 5])
    }

    func testTwoIconsInOneCellKeepTheirAccessibilityOrder() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 3), Layouts.item(x: 104, y: 98, axOrder: 1),
                     Layouts.item(x: 216, y: 100, axOrder: 2)]
        let grid = Grid.fit(members: [0, 1, 2], items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [1, 0, 2])
    }

    func testOneIconIsAGridOfOne() {
        let items = [Layouts.item(x: 300, y: 200)]
        let grid = Grid.fit(members: [0], items: items, pitch: pitch, leadingIsLeft: true)
        XCTAssertTrue(grid.isGrid)
        XCTAssertEqual(grid.order, [0])
        XCTAssertEqual(grid.top, 200)
        XCTAssertEqual(grid.leading, 300)
    }

    func testTheLeadingEdgeOfARightToLeftClusterIsItsRightEdgeNegated() {
        let items = Layouts.filled(rows: 1, columns: 2, origin: CGPoint(x: 100, y: 50))
        let grid = Grid.fit(members: [0, 1], items: items, pitch: pitch, leadingIsLeft: false)
        // The right edge of the rightmost frame is 100 + 116 + 64; negated so that a smaller key sorts first.
        XCTAssertEqual(grid.leading, -(100 + 116 + 64))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GridTests`
Expected: compile error, `cannot find 'Grid' in scope`.

- [ ] **Step 3: Make `Lattice.isTight` internal**

In `Sources/ShiftPickCore/Lattice.swift` change `private static func isTight(` to `static func isTight(`. Nothing else in the file moves.

- [ ] **Step 4: Write `Grid`**

```swift
import CoreGraphics
import Foundation

/// One cluster of a hand-placed view, fitted with rows and columns and read along its rows: rows top to
/// bottom, each row from the leading edge. A cluster whose rows or columns are too wide to be one line is a
/// scatter: it keeps an order (top edge, then leading edge) so that a stand-in can be named across it, and
/// every range to or from it is a line (`docs/functional.md` §3).
struct Grid {
    /// The cluster's items in reading order.
    let order: [Int]
    /// False for a scatter.
    let isGrid: Bool
    /// The cluster's top edge, and its leading edge as a sort key (the left edge, or the right edge negated
    /// for a right-to-left layout): clusters are ordered by these two, smaller first.
    let top: CGFloat
    let leading: CGFloat

    static func fit(members: [Int], items: [LayoutItem], pitch: CGFloat, leadingIsLeft: Bool) -> Grid {
        let tolerance = max(K.gridLineTolerancePitches * pitch, 1)
        let ys = members.map { items[$0].reference.y }
        let xs = members.map { items[$0].reference.x }
        let rows = Lattice.cluster(ys, tolerance: tolerance)
        let columns = Lattice.cluster(xs, tolerance: tolerance)
        let tight = Lattice.isTight(ys, rows.index, limit: tolerance)
            && Lattice.isTight(xs, columns.index, limit: tolerance)

        let top = members.map { items[$0].frame.minY }.min() ?? 0
        let leading = leadingIsLeft
            ? (members.map { items[$0].frame.minX }.min() ?? 0)
            : -(members.map { items[$0].frame.maxX }.max() ?? 0)

        let order: [Int]
        if tight {
            // Column numbers count from the left; a right-to-left row reads them backwards.
            let width = columns.count
            order = members.indices.sorted { a, b in
                let columnA = leadingIsLeft ? columns.index[a] : width - 1 - columns.index[a]
                let columnB = leadingIsLeft ? columns.index[b] : width - 1 - columns.index[b]
                if rows.index[a] != rows.index[b] { return rows.index[a] < rows.index[b] }
                if columnA != columnB { return columnA < columnB }
                return items[members[a]].axOrder < items[members[b]].axOrder
            }.map { members[$0] }
        } else {
            order = members.sorted { a, b in
                let pointA = items[a].reference, pointB = items[b].reference
                if pointA.y != pointB.y { return pointA.y < pointB.y }
                let leadA = leadingIsLeft ? pointA.x : -pointA.x
                let leadB = leadingIsLeft ? pointB.x : -pointB.x
                if leadA != leadB { return leadA < leadB }
                return items[a].axOrder < items[b].axOrder
            }
        }
        return Grid(order: order, isGrid: tight, top: top, leading: leading)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter GridTests` then `swift test --filter LatticeTests`
Expected: 8 and 9 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShiftPickCore/Grid.swift Sources/ShiftPickCore/Lattice.swift Tests/ShiftPickCoreTests/GridTests.swift
git commit -m "feat(core): a cluster fitted with rows and columns, read along its rows

Owes docs/functional.md §3 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 4: `LineBand`

**Files:**
- Create: `Sources/ShiftPickCore/LineBand.swift`
- Test: `Tests/ShiftPickCoreTests/LineBandTests.swift`

**Interfaces:**
- Produces: `struct LineBand { init(from: CGPoint, to: CGPoint, thickness: CGFloat); func intersects(_ rect: CGRect) -> Bool }`. Task 5 uses it.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import XCTest
@testable import ShiftPickCore

/// The line one icon thick between two icons, and what touches it.
final class LineBandTests: XCTestCase {
    private func icon(_ x: CGFloat, _ y: CGFloat, side: CGFloat = 64) -> CGRect {
        CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    }

    func testBothEndsAlwaysTouch() {
        let band = LineBand(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 700, y: 500), thickness: 64)
        XCTAssertTrue(band.intersects(icon(100, 100)))
        XCTAssertTrue(band.intersects(icon(700, 500)))
    }

    func testAnIconOnTheSegmentTouches() {
        let band = LineBand(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 700, y: 500), thickness: 64)
        XCTAssertTrue(band.intersects(icon(400, 300)))
    }

    /// Half the thickness plus half the icon: an icon centred one side off a horizontal line just touches
    /// it, and one a little further does not.
    func testTheBandIsOneIconThick() {
        let band = LineBand(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 900, y: 300), thickness: 64)
        XCTAssertTrue(band.intersects(icon(500, 300 + 63)))
        XCTAssertFalse(band.intersects(icon(500, 300 + 66)))
    }

    func testAnIconBeyondAnEndDoesNotTouch() {
        let band = LineBand(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 900, y: 300), thickness: 64)
        XCTAssertFalse(band.intersects(icon(100 - 70, 300)))
        XCTAssertTrue(band.intersects(icon(100 - 60, 300)), "an icon overlapping the end's cap touches")
    }

    func testADiagonalBandIsExactAndNotItsBoundingBox() {
        let band = LineBand(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 900, y: 900), thickness: 64)
        // Inside the bounding box of the segment, far from the line itself.
        XCTAssertFalse(band.intersects(icon(800, 200)))
        XCTAssertTrue(band.intersects(icon(500, 540)))
    }

    func testTheBandIsTheSameEitherWayRound() {
        let there = LineBand(from: CGPoint(x: 132, y: 132), to: CGPoint(x: 732, y: 652), thickness: 64)
        let back = LineBand(from: CGPoint(x: 732, y: 652), to: CGPoint(x: 132, y: 132), thickness: 64)
        for point in [CGPoint(x: 332, y: 292), CGPoint(x: 932, y: 152), CGPoint(x: 400, y: 380), CGPoint(x: 600, y: 700)] {
            XCTAssertEqual(there.intersects(icon(point.x, point.y)), back.intersects(icon(point.x, point.y)), "\(point)")
        }
    }

    func testAZeroLengthBandIsASquareAroundThePoint() {
        let band = LineBand(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 300, y: 300), thickness: 64)
        XCTAssertTrue(band.intersects(icon(300, 300)))
        XCTAssertTrue(band.intersects(icon(300 + 60, 300)))
        XCTAssertFalse(band.intersects(icon(300 + 70, 300)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LineBandTests`
Expected: compile error, `cannot find 'LineBand' in scope`.

- [ ] **Step 3: Write `LineBand`**

```swift
import CoreGraphics
import Foundation

/// The line drawn between two icons that share no grid: the segment between their centres, thickened to
/// one icon. An icon is on the line when its frame intersects that rectangle, tested exactly with the
/// separating axis theorem over the band's two axes and the screen's two.
struct LineBand {
    private let start: CGPoint
    private let along: CGPoint      // unit vector from start to end
    private let across: CGPoint     // unit vector perpendicular to it
    private let length: CGFloat
    private let halfThickness: CGFloat

    init(from start: CGPoint, to end: CGPoint, thickness: CGFloat) {
        self.start = start
        halfThickness = thickness / 2
        let dx = end.x - start.x, dy = end.y - start.y
        length = hypot(dx, dy)
        // A zero-length band still has two axes: any pair will do, and the screen's are the obvious ones.
        along = length > 0 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 1, y: 0)
        across = CGPoint(x: -along.y, y: along.x)
    }

    func intersects(_ rect: CGRect) -> Bool {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        // The band's axes: the rectangle's corners projected onto them must overlap the band's own extent.
        let alongProjections = corners.map { ($0.x - start.x) * along.x + ($0.y - start.y) * along.y }
        guard alongProjections.max()! >= 0, alongProjections.min()! <= length else { return false }
        let acrossProjections = corners.map { ($0.x - start.x) * across.x + ($0.y - start.y) * across.y }
        guard acrossProjections.max()! >= -halfThickness, acrossProjections.min()! <= halfThickness else { return false }
        // The screen's axes: the band's corners projected onto x and y must overlap the rectangle.
        let bandCorners = [
            CGPoint(x: start.x + across.x * halfThickness, y: start.y + across.y * halfThickness),
            CGPoint(x: start.x - across.x * halfThickness, y: start.y - across.y * halfThickness),
            CGPoint(x: start.x + along.x * length + across.x * halfThickness, y: start.y + along.y * length + across.y * halfThickness),
            CGPoint(x: start.x + along.x * length - across.x * halfThickness, y: start.y + along.y * length - across.y * halfThickness),
        ]
        let xs = bandCorners.map(\.x), ys = bandCorners.map(\.y)
        guard xs.max()! >= rect.minX, xs.min()! <= rect.maxX else { return false }
        guard ys.max()! >= rect.minY, ys.min()! <= rect.maxY else { return false }
        return true
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter LineBandTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShiftPickCore/LineBand.swift Tests/ShiftPickCoreTests/LineBandTests.swift
git commit -m "feat(core): the line one icon thick between two icons, and what touches it

Owes docs/functional.md §3 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 5: `LayoutModel` answers a reading order, a shape and a click

**Files:**
- Modify: `Sources/ShiftPickCore/LayoutModel.swift` (everything above `// MARK: - Classification`; the classification code stays as it is)
- Modify: `Sources/ShiftPickCore/LayoutItem.swift` (`LayoutKind`)
- Modify: `Tests/ShiftPickCoreTests/RangeSelectionTests.swift`
- Create: `Tests/ShiftPickCoreTests/StandInTests.swift`
- Delete: `Tests/ShiftPickCoreTests/AnchorTests.swift`

**Interfaces:**
- Consumes: `ShiftClick` (Task 1), `Clusters` (Task 2), `Grid` (Task 3), `LineBand` (Task 4).
- Produces, all `public` on `LayoutModel`: `kind: LayoutKind` (`.arranged(Flow)` or `.handPlaced(grids: Int, scatters: Int)`); `flowPosition(of:) -> Int?` (unchanged); `readingPosition(of:) -> Int?`; `firstItem: Int?`; `effectiveAnchor(stored: Int?, selection: [Int]) -> Int?`; `range(from:to:) -> RangeShape?` where `enum RangeShape { case ordered([Int]); case line([Int]); var items: [Int] }`; `shiftClick(from anchor: Int, selection: [Int], target: Int) -> Outcome?` where `struct Outcome { let selection: [Int]; let anchor: Int; let shape: RangeShape }`. Tasks 7 and 11 call these. `derivedAnchor` is gone.

- [ ] **Step 1: Change `LayoutKind` in `LayoutItem.swift`**

Replace the `LayoutKind` enum at the bottom of the file with:

```swift
/// What the geometry says about how the items got where they are.
public enum LayoutKind: Equatable, Sendable {
    /// Finder is laying these out: the items fill a lattice contiguously along `Flow`, allowing a partial
    /// last line and a break at every group. Flow order is meaningful, so a range is a slice of it.
    case arranged(Flow)
    /// Holes in the lattice, or items that are not on one at all: *Sort By None*, a Desktop somebody has
    /// arranged by hand. The icons are cut into clusters; `grids` of them read along their rows and
    /// `scatters` have no grid. A range inside one grid is a slice of its order; any other range is a line.
    case handPlaced(grids: Int, scatters: Int)
}
```

- [ ] **Step 2: Rewrite the existing range tests for the new shapes**

In `Tests/ShiftPickCoreTests/RangeSelectionTests.swift`:

```bash
sed -i '' 's/model\.range(from: \([^)]*\))/model.range(from: \1)?.items/g' Tests/ShiftPickCoreTests/RangeSelectionTests.swift
sed -i '' 's/?\.items?\.count/?.items.count/g' Tests/ShiftPickCoreTests/RangeSelectionTests.swift
```

Then replace the five hand-placed tests (`testAGridWithAHoleIsHandPlaced` through `testAScatterRangeIsBoundedByTheTwoIcons`) with:

```swift
    // MARK: - Holes and grids nobody arranged

    func testAGridWithAHoleIsOneHandPlacedGrid() {
        var items = Layouts.filled(rows: 3, columns: 4)
        items.remove(at: 5)   // the second item of the second row
        XCTAssertEqual(model(items).kind, .handPlaced(grids: 1, scatters: 0))
    }

    /// The owner's rule: the first icon of one row to the first of the next takes the whole row between.
    func testAHandPlacedGridReadsAlongItsRows() {
        var items = Layouts.filled(rows: 2, columns: 3)
        items.remove(at: 1)   // row 0 holds columns 0 and 2; row 1 is full
        let model = model(items)
        XCTAssertEqual(model.range(from: 0, to: 2), .ordered([0, 1, 2]))
        XCTAssertEqual(model.readingPosition(of: 1), 1)
        XCTAssertEqual(model.readingPosition(of: 2), 2)
    }

    func testAGridWithAHoleReadsAcrossTheHole() {
        var items = Layouts.filled(rows: 3, columns: 4)
        items.remove(at: 5)
        // Indices after the removal: row 0 is 0...3, row 1 is 4, 5, 6 (columns 0, 2, 3), row 2 is 7...10.
        XCTAssertEqual(model(items).range(from: 1, to: 5), .ordered([1, 2, 3, 4, 5]))
    }

    func testIconsTooFarApartForAGridGetALine() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0),
                     Layouts.item(x: 900, y: 700, axOrder: 1),
                     Layouts.item(x: 100, y: 700, axOrder: 2)]
        let model = model(items)
        XCTAssertEqual(model.kind, .handPlaced(grids: 3, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 1), .line([0, 1]))
        XCTAssertEqual(model.range(from: 0, to: 2), .line([0, 2]))
    }

    func testTwoGridsFarApartGiveALineBetweenThemAndAnOrderInsideEach() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 100), firstAXOrder: 4)
        let model = model(items)
        XCTAssertEqual(model.kind, .handPlaced(grids: 2, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 3), .ordered([0, 1, 2, 3]))
        guard case .line(let touched)? = model.range(from: 0, to: 7) else { return XCTFail("a line") }
        XCTAssertTrue(touched.contains(0) && touched.contains(7))
    }

    func testAWobblyHandPlacedGridIsStillAGrid() {
        let jitter: [(CGFloat, CGFloat)] = [(-20, 15), (10, -25), (25, 20), (-15, -10), (18, -18)]
        var base = Layouts.filled(rows: 2, columns: 3, pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        base.remove(at: 4)
        let items = zip(base, jitter).enumerated().map { order, pair in
            LayoutItem(frame: pair.0.frame.offsetBy(dx: pair.1.0, dy: pair.1.1), axOrder: order)
        }
        let model = model(items, .columnsFromRight)
        XCTAssertEqual(model.kind, .handPlaced(grids: 1, scatters: 0))
        XCTAssertEqual(model.range(from: 0, to: 3), .ordered([0, 1, 2, 3]))
    }

    // MARK: - A free-form scatter

    func testAScatterIsHandPlaced() {
        // The Desktop as somebody left it: no two icons on a line, nothing on a pitch.
        let positions: [(CGFloat, CGFloat)] = [(1413, 43), (1423, 145), (1309, 43), (612, 511),
                                               (277, 388), (980, 133), (1041, 702), (355, 96)]
        let items = positions.enumerated().map { order, position in
            Layouts.item(x: position.0, y: position.1, axOrder: order, side: Layouts.desktopSide)
        }
        guard case .handPlaced = model(items, .columnsFromRight).kind else { return XCTFail("hand-placed") }
    }

    func testALineTakesWhatItTouchesAndNothingElse() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0),
                     Layouts.item(x: 300, y: 260, axOrder: 1),
                     Layouts.item(x: 700, y: 620, axOrder: 2),
                     Layouts.item(x: 900, y: 120, axOrder: 3)]
        // The line from the first to the third passes over the second and far from the fourth.
        XCTAssertEqual(model(items).range(from: 0, to: 2), .line([0, 1, 2]))
    }
```

Replace `testAStackIsNeverInARange`'s assertion with `XCTAssertEqual(range, [0, 1, 3, 4])` unchanged (the sed already made `range` the items). In `testFiveThousandScatteredItems`, change the comment to `// The other shape at that size: nothing on a lattice, so grids of one and lines are what answer.` and the two `contains` lines to `range?.items.contains(0) == true` and `range?.items.contains(4_999) == true` (the sed produced `range` as `[Int]?` from `let range = model.range(...)?.items`, so leave them if they already compile).

Add, before `// MARK: - The three properties`:

```swift
    // MARK: - The click

    /// The spec's §4: a 3 × 4 sorted window, icons numbered in reading order.
    func testTheOwnersExampleOnAnArrangedGrid() {
        let model = model(Layouts.filled(rows: 3, columns: 4))
        let first = model.shiftClick(from: 0, selection: [0], target: 4)
        XCTAssertEqual(first?.selection, [0, 1, 2, 3, 4])
        XCTAssertEqual(first?.anchor, 0)
        XCTAssertEqual(first?.shape, .ordered([0, 1, 2, 3, 4]))
        // ⌘ Command click 8 (index 7), then ⇧ Shift click 10 (index 9): the run {8} is replaced by 8...10.
        let second = model.shiftClick(from: 7, selection: [0, 1, 2, 3, 4, 7], target: 9)
        XCTAssertEqual(second?.selection, [0, 1, 2, 3, 4, 7, 8, 9])
        // ⇧ Shift click 6 (index 5): the range 6...8 touches {8,9,10}, which goes whole.
        let third = model.shiftClick(from: 7, selection: second!.selection, target: 5)
        XCTAssertEqual(third?.selection, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(third?.anchor, 7)
    }

    func testASelectedIconInAnotherClusterIsNeverTouched() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 100), firstAXOrder: 4)
        let outcome = model(items).shiftClick(from: 0, selection: [0, 6], target: 3)
        XCTAssertEqual(outcome?.selection, [0, 1, 2, 3, 6])
    }

    func testALineIsAddedToWhatWasSelected() {
        let items = [Layouts.item(x: 100, y: 100, axOrder: 0), Layouts.item(x: 900, y: 700, axOrder: 1),
                     Layouts.item(x: 100, y: 700, axOrder: 2)]
        let outcome = model(items).shiftClick(from: 0, selection: [2], target: 1)
        XCTAssertEqual(outcome?.shape, .line([0, 1]))
        XCTAssertEqual(outcome?.selection, [0, 1, 2])
    }

    func testAStackInsideTheRangeIsNotSelectedAndASelectedOneOutsideItIsKept() {
        var items = Layouts.filled(rows: 1, columns: 6, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[2] = LayoutItem(frame: items[2].frame, section: 0, axOrder: 2, isFile: false)
        let outcome = model(items, .columnsFromRight).shiftClick(from: 0, selection: [0], target: 4)
        XCTAssertEqual(outcome?.selection, [0, 1, 3, 4])
    }

    func testAnIndexThatIsNotAnItemIsNeverSelected() {
        let outcome = model(Layouts.filled(rows: 2, columns: 3)).shiftClick(from: 0, selection: [40, 5], target: 1)
        XCTAssertEqual(outcome?.selection, [0, 1, 5])
    }
```

- [ ] **Step 3: Write `StandInTests` and delete `AnchorTests`**

```bash
git rm -q Tests/ShiftPickCoreTests/AnchorTests.swift
```

`Tests/ShiftPickCoreTests/StandInTests.swift`:

```swift
import CoreGraphics
import XCTest
import ShiftPickCore

/// Where a ⇧ Shift click is measured from (`docs/functional.md` §2.1): the stored anchor while it is
/// selected, else a stand-in named in reading order, else nothing.
final class StandInTests: XCTestCase {
    private func grid() -> LayoutModel {
        LayoutModel(items: Layouts.filled(rows: 4, columns: 6), fallbackFlow: .rowsFromLeft)
    }

    func testASelectedAnchorIsUsed() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 5, selection: [5, 6, 7, 8]), 5)
    }

    func testADeselectedAnchorIsStoodInByTheFirstSelectedIconAfterIt() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 3, selection: [1, 2, 4, 5]), 4)
        XCTAssertEqual(grid().effectiveAnchor(stored: 3, selection: [1, 9]), 9)
    }

    func testElseByTheLastSelectedIconBeforeIt() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 22, selection: [3, 9]), 9)
    }

    func testNoAnchorMeasuresFromTheFirstSelectedIconInReadingOrder() {
        XCTAssertEqual(grid().effectiveAnchor(stored: nil, selection: [8, 5, 6, 7]), 5)
    }

    func testNothingSelectedIsNoAnchor() {
        XCTAssertNil(grid().effectiveAnchor(stored: 4, selection: []))
        XCTAssertNil(grid().effectiveAnchor(stored: nil, selection: []))
    }

    func testAStackIsNeitherAnAnchorNorACandidate() {
        var items = Layouts.filled(rows: 1, columns: 5, pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        let model = LayoutModel(items: items, fallbackFlow: .columnsFromRight)
        XCTAssertNil(model.effectiveAnchor(stored: 0, selection: [0]))
        XCTAssertEqual(model.effectiveAnchor(stored: 0, selection: [0, 1]), 1)
    }

    func testAnIndexThatIsNotAnItemIsIgnored() {
        XCTAssertEqual(grid().effectiveAnchor(stored: 99, selection: [99, 2, -4]), 2)
    }

    /// Reading order runs down a sorted Desktop's columns, so "after" means further down the column and
    /// then into the next one to the left.
    func testTheOrderIsTheViewsOwn() {
        let items = Layouts.filled(rows: 7, columns: 3, count: 10, flow: .columnsFromRight,
                                   origin: CGPoint(x: 1166, y: 42), pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        let model = LayoutModel(items: items, fallbackFlow: .columnsFromRight)
        XCTAssertEqual(model.effectiveAnchor(stored: 2, selection: [1, 8]), 8)
    }

    /// Clusters follow one another in reading order, so a stand-in can be found in the next cluster; a
    /// range to it is then a line, which is the caller's business.
    func testAStandInMayBeInAnotherCluster() {
        var items = Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 100, y: 100))
        items += Layouts.filled(rows: 2, columns: 2, origin: CGPoint(x: 900, y: 100), firstAXOrder: 4)
        let model = LayoutModel(items: items, fallbackFlow: .rowsFromLeft)
        XCTAssertEqual(model.effectiveAnchor(stored: 2, selection: [5]), 5)
        XCTAssertEqual(model.effectiveAnchor(stored: 6, selection: [1]), 1)
    }

    func testTheFirstItemIsTheFirstFileInReadingOrder() {
        XCTAssertEqual(grid().firstItem, 0)
        var items = Layouts.filled(rows: 1, columns: 3, flow: .columnsFromRight,
                                   pitch: Layouts.desktopPitch, side: Layouts.desktopSide)
        items[0] = LayoutItem(frame: items[0].frame, section: 0, axOrder: 0, isFile: false)
        XCTAssertEqual(LayoutModel(items: items, fallbackFlow: .columnsFromRight).firstItem, 1)
        XCTAssertNil(LayoutModel(items: [], fallbackFlow: .rowsFromLeft).firstItem)
    }
}
```

- [ ] **Step 4: Run to verify the new tests fail**

Run: `swift test --filter "RangeSelectionTests|StandInTests"`
Expected: compile errors (`readingPosition`, `effectiveAnchor`, `shiftClick`, `.handPlaced(grids:` unknown).

- [ ] **Step 5: Rewrite the top of `LayoutModel.swift`**

Replace everything from the file's first line down to (not including) `    // MARK: - Classification` with:

```swift
import CoreGraphics
import Foundation

/// What a range is: the slice of one reading order between two icons, or the icons a line between them
/// touches. `items` are indices into `LayoutModel.items`, ascending.
public enum RangeShape: Equatable, Sendable {
    /// Inside one order (an arranged view, or one grid of a hand-placed one). A ⇧ Shift click replaces every
    /// run of the selection it touches with it (`ShiftClick`).
    case ordered([Int])
    /// Between two grids, or to or from a scatter: a line one icon thick. A ⇧ Shift click adds it.
    case line([Int])

    public var items: [Int] {
        switch self {
        case .ordered(let items), .line(let items): items
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
    /// The icon's own side, which is what a line is as thick as.
    private let side: CGFloat
    private let lattice: Lattice

    /// `fallbackFlow` is what the caller knows about the container and the geometry cannot: a window fills
    /// rows from its leading edge, the Desktop fills columns from its trailing one. It breaks the tie when
    /// the geometry accepts several flows, and it says which edge is the leading one for a hand-placed grid.
    public init(items: [LayoutItem], fallbackFlow: Flow) {
        self.items = items
        lattice = Lattice.build(items)
        side = max(Lattice.median(items.map(\.frame.height)) ?? 1, 1)
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
        let candidates = Set(selection.filter { items.indices.contains($0) && items[$0].isFile }.map { position[$0] })
        let pivot = stored.flatMap { items.indices.contains($0) && items[$0].isFile ? position[$0] : nil }
        return ShiftClick.standIn(anchor: pivot, selection: candidates).map { itemAt[$0] }
    }

    // MARK: - The range

    /// Every file between the anchor and the target, inclusive, as indices into `items`, ascending, and
    /// how they were found: the slice of the reading order when both are in one grid (or the view is
    /// arranged), and otherwise the files a line one icon thick between the two centres touches.
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
        let band = LineBand(from: items[anchor].reference, to: items[target].reference,
                            thickness: side * K.lineThicknessSides)
        return .line(items.indices.filter {
            items[$0].isFile && ($0 == anchor || $0 == target || band.intersects(items[$0].frame))
        })
    }

    // MARK: - The click

    /// What one ⇧ Shift click leaves selected, measured from `anchor` (already the effective one) with
    /// `selection` what Finder has selected now. An ordered range replaces every run of the selection it
    /// touches inside its own cluster and leaves every other cluster's selection alone; a line is added.
    /// Selected indices that are not items are dropped; selected items that are not files are kept when
    /// they are outside the range's cluster.
    public func shiftClick(from anchor: Int, selection: [Int], target: Int) -> Outcome? {
        guard let shape = range(from: anchor, to: target) else { return nil }
        let valid = Set(selection.filter { items.indices.contains($0) })
        switch shape {
        case .ordered:
            let own = cluster[anchor]
            let start = clusterStart[own]
            let inside = Set(valid.filter { cluster[$0] == own }.map { position[$0] - start })
            guard let ranks = ShiftClick.resolve(anchor: position[anchor] - start, selection: inside,
                                                 target: position[target] - start, count: clusterCount[own])
            else { return nil }
            let chosen = ranks.map { itemAt[start + $0] }.filter { items[$0].isFile }
            let outside = valid.filter { cluster[$0] != own }
            return Outcome(selection: (chosen + outside).sorted(), anchor: anchor, shape: shape)
        case .line(let touched):
            return Outcome(selection: valid.union(touched).sorted(), anchor: anchor, shape: shape)
        }
    }

```

Delete the old `// MARK: - The anchor` block (`derivedAnchor` and `distance`) that sat between the range and the classification; nothing below `// MARK: - Classification` changes.

- [ ] **Step 6: Build and run the Core tests**

Run: `swift build && swift test --filter ShiftPickCoreTests`
Expected: green. If `PurityTests.testCoreNeverReachesForTheClockInARule` complains about nothing, fine; if `LatticeTests` needs `@testable`, it already has it.

- [ ] **Step 7: Commit**

```bash
git add Sources/ShiftPickCore/LayoutModel.swift Sources/ShiftPickCore/LayoutItem.swift Tests/ShiftPickCoreTests/RangeSelectionTests.swift Tests/ShiftPickCoreTests/StandInTests.swift Tests/ShiftPickCoreTests/AnchorTests.swift
git commit -m "feat(core): one reading order per view, a range as a slice or a line, and the click's outcome

A hand-placed view is cut into clusters, each fitted with a grid read along
its rows; a range inside one grid is a slice of its order and any other
range is a line one icon thick. The stand-in rule replaces the farthest-
selected-file rule, and the rubber band is gone.

Owes docs/functional.md §2.1 and §3 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 6: `FinderAX` keeps unmapped selected elements and says whether a view is scrolled

**Files:**
- Modify: `Sources/ShiftPickPlatform/FinderAX.swift` (`selection(in:among:)`, new `isScrolled(_:)`)
- Modify: `Tools/axdump/main.swift` (the one caller of `selection`, line `let selection = FinderAX.selection(...)`: read `.indices` for now; Task 11 rewrites the command)

No unit test can talk to Finder; the manual checklist (Task 12) and M2/M4 of Task 0 are this task's verification. `swift build` is the gate.

**Interfaces:**
- Produces: `FinderAX.SelectionReading { indices: [Int]; unmapped: [AXUIElement] }`, `FinderAX.selection(in:among:) -> SelectionReading`, `FinderAX.isScrolled(_ view: IconView) -> Bool?`. Task 7 uses all three.

- [ ] **Step 1: Replace `selection(in:among:)`**

```swift
    /// What Finder has selected in the view: which of `elements` (by index), and every selected element
    /// that is not among them, kept so that the one call that sets the selection can hand them back
    /// unchanged. Finder builds only the icons on screen, and whether it names an off-screen selected item
    /// here is not promised either way; the rule costs nothing if it never does.
    public struct SelectionReading {
        public let indices: [Int]
        public let unmapped: [AXUIElement]
    }

    /// Elements compare by `CFEqual`, which Finder's own answer to `AXSelectedChildren` is built from, so
    /// this costs one round trip and no attribute reads.
    public static func selection(in view: IconView, among elements: [AXUIElement]) -> SelectionReading {
        let selected = AX.elements(view.container, "AXSelectedChildren")
        guard !selected.isEmpty else { return SelectionReading(indices: [], unmapped: []) }
        var index: [UInt: Int] = [:]
        for (position, element) in elements.enumerated() { index[CFHash(element)] = position }
        var indices: [Int] = []
        var unmapped: [AXUIElement] = []
        for element in selected {
            if let candidate = index[CFHash(element)], CFEqual(elements[candidate], element) {
                indices.append(candidate)
            } else {
                unmapped.append(element)
            }
        }
        return SelectionReading(indices: indices, unmapped: unmapped)
    }
```

- [ ] **Step 2: Add `isScrolled`** after `index(of:among:)`

```swift
    /// Whether the view has been scrolled away from its top: its container's top edge then sits above its
    /// scroll area's (measured, Task 0 M4). The Desktop never scrolls. nil when a frame cannot be read,
    /// which the caller treats as "may be scrolled".
    public static func isScrolled(_ view: IconView) -> Bool? {
        if view.isDesktop { return false }
        guard let area = AX.parent(view.container), AX.role(area) == "AXScrollArea",
              let containerFrame = AX.frame(view.container), let areaFrame = AX.frame(area) else { return nil }
        return containerFrame.minY < areaFrame.minY - 1
    }
```

If Task 0's M4 found the container does not move, read the scroll bar instead: `AX.children(area).first { AX.role($0) == "AXScrollBar" && (AX.attribute($0, "AXOrientation") as String?) == "AXVerticalOrientation" }`, and its `"AXValue"` as `Double?`; scrolled when it is above `0.001`.

- [ ] **Step 3: Patch the probe's caller** so it builds: in `Tools/axdump/main.swift`, `let selection = FinderAX.selection(in: target.view, among: elements)` becomes `let selection = FinderAX.selection(in: target.view, among: elements).indices`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: the App target fails to build (`ShiftClickResolver` still uses `[Int]`); that is Task 7. Confirm the Platform target built: `swift build --target ShiftPickPlatform` succeeds.

- [ ] **Step 5: Commit** (with Task 7, below: the two land together so the tree builds at every commit).

---

### Task 7: The click, end to end

**Invoke the `shiftpick-safety-nets` skill first.** `ShiftClickResolver.swift` and `ClickGuard.swift` are files of the safety layer. What stays exactly as it is: the order `guard ticket.commit() else` → `guard FinderAX.select(` → `ticket.finish(swallow: true)`, the one swallow line, every `shouldContinue`/`wanted` check, `onGrantLost` on a refusal, and `dispatchPrecondition(.onQueue(queue))`. `SafetyNetTests.testAClickIsSwallowedOnlyAfterItsSelectionIsSet` reads those three strings in that order.

**Files:**
- Modify: `Sources/ShiftPickApp/ShiftClickResolver.swift`
- Modify: `Sources/ShiftPickPlatform/ClickGuard.swift:347` (the sentinel's `leftMouseDown`)
- Modify: `Sources/ShiftPickApp/ShiftPickEngine.swift` (drop `resolver.update(...)` and the `Options` sink; Task 9 finishes the engine)

**Interfaces:**
- Consumes: `LayoutModel.effectiveAnchor`, `.firstItem`, `.shiftClick(from:selection:target:)`, `FinderAX.selection` (`SelectionReading`), `FinderAX.isScrolled`.
- Produces: `ShiftClickResolver` without `Options`/`update(_:)`; `notePlainClick(at:)` unchanged in signature.

- [ ] **Step 1: The sentinel notes the anchor for a ⌘ Command press too**

In `ClickGuard.sentinelHeard`, replace

```swift
            if !flags.contains(.maskShift) { hooks.plainClick(event.location) }
```

with

```swift
            // A plain click and a ⌘ Command click set the anchor, and so does ⌘ Command with ⇧ Shift, which
            // is Finder's own toggle and passes through the click tap (docs/functional.md §2.1). Only a
            // plain ⇧ Shift press is not noted here: it is the click the worker decides.
            if !flags.contains(.maskShift) || flags.contains(.maskCommand) { hooks.plainClick(event.location) }
```

- [ ] **Step 2: Rewrite `ShiftClickResolver`**

Remove `struct Options`, the `options` lock, `update(_:)`, and the `guard options...` lines in `notePlainClick`. Replace `shiftClick` from its first `let options = ...` line to the end of the method with:

```swift
        // ⌘ Command with ⇧ Shift is Finder's own toggle, measured in its list view: the click passes, and the
        // sentinel, which heard the same press, notes the anchor.
        guard !flags.contains(.maskCommand) else { return pass("⌘ Command held: Finder's own toggle") }
        guard let pid = finderProcess() else { return }

        let timeout = Float(K.axTimeout)
        let wanted = { !ticket.isAbandoned }
        guard case .item(let target) = FinderAX.hit(at: point, finderPID: pid, timeout: timeout,
                                                    shouldContinue: wanted)
        else { return }

        // The application that owns the view, which is Finder for a window and for the Desktop and
        // whichever application put the panel up for a panel.
        let application = AXUIElementCreateApplication(AX.pid(of: target.view.container))
        AX.setTimeout(timeout, on: application)
        // A name being typed in place: the click belongs to the text field, not to a range. Finder only:
        // a Save panel keeps its own name field focused the whole time it is up, so the same question
        // asked of a panel would refuse every click in it.
        if target.view.host != .panel, FinderAX.isRenaming(finder: application) { return }

        let pairs = FinderAX.items(in: target.view, timeout: timeout, shouldContinue: wanted)
        guard !pairs.isEmpty else { return pass("Finder answered too slowly, or with nothing") }
        let elements = pairs.map(\.1)
        guard let targetIndex = FinderAX.index(of: target.item, among: elements) else { return }

        let model = LayoutModel(items: pairs.map(\.0), fallbackFlow: target.view.fallbackFlow)
        // One round trip: what Finder has selected now is the whole of the state besides the anchor.
        let reading = FinderAX.selection(in: target.view, among: elements)

        var stored: Int?
        if let anchor, CFEqual(anchor.container, target.view.container) {
            stored = FinderAX.index(of: anchor.item, among: elements)
        }
        var measuredFrom = model.effectiveAnchor(stored: stored, selection: reading.indices)
        if measuredFrom == nil {
            // Nothing is selected: a list view measures from its first row. The first icon is only known to
            // be on screen while the view is not scrolled (docs/pitfalls.md 1); otherwise the click is Finder's.
            guard FinderAX.isScrolled(target.view) == false, let first = model.firstItem
            else { return pass("nothing selected, and the first icon may be off screen") }
            measuredFrom = first
        }
        guard let measuredFrom,
              let outcome = model.shiftClick(from: measuredFrom, selection: reading.indices, target: targetIndex)
        else { return pass("the anchor or the target is not a file") }
        // Selected elements Finder named that are not on screen go back exactly as they came.
        let chosen = outcome.selection.map { elements[$0] } + reading.unmapped

        // The point of no return, and it can be refused: a click that has already gone back to the system
        // is Finder's, and a selection set now would land on top of whatever Finder did with it.
        guard ticket.commit() else { return pass("the click took too long and was given back") }
        guard FinderAX.select(chosen, in: target.view) else {
            ticket.finish(swallow: false)
            return pass("Finder refused the selection")
        }
        ticket.finish(swallow: true)

        // The click was swallowed, so what it would otherwise have done has to be done here. Nobody is
        // waiting for this part: the press was answered the line above.
        FinderAX.raise(target.view, application: application)
        // The anchor is the icon the range was measured from: the stored one, or its stand-in.
        anchor = Anchor(container: target.view.container, item: elements[outcome.anchor])
        let shape = if case .line = outcome.shape { "line" } else { "ordered" }
        Log.click.debug("""
            selected \(outcome.selection.count, privacy: .public) of \(elements.count, privacy: .public) \
            (\(String(describing: model.kind), privacy: .public), \(shape, privacy: .public), measured from \
            \(stored == outcome.anchor ? "the anchor" : "a stand-in", privacy: .public))
            """)
    }
```

Update the type's doc comment: replace the sentence about `Options` (there is none in the doc, but `Options` struct's comment goes with it) and add to the class comment: *"It keeps one anchor per container and nothing else: the selection is read from Finder at every click (`docs/functional.md` §2.1)."*

- [ ] **Step 3: Drop the engine's use of the options**

In `ShiftPickEngine.init`, delete `resolver.update(store.settings)` and, in the first `store.$settings ... .sink { [resolver, clickGuard] settings in ... }`, delete the line `resolver.update(settings)` (leave `clickGuard.setUserEnabled(settings.enabled)` for Task 9 to remove).

- [ ] **Step 4: Build and run the pins**

Run: `swift build && swift test --filter SafetyNetTests`
Expected: build clean; `SafetyNetTests` green, in particular `testAClickIsSwallowedOnlyAfterItsSelectionIsSet` and `testAClickReachesTheWorkerOnlyThroughTheDeadline`.

- [ ] **Step 5: Commit Tasks 6 and 7 together**

```bash
git add Sources/ShiftPickPlatform/FinderAX.swift Sources/ShiftPickPlatform/ClickGuard.swift Sources/ShiftPickApp/ShiftClickResolver.swift Sources/ShiftPickApp/ShiftPickEngine.swift Tools/axdump/main.swift
git commit -m "feat(click): a ⇧ Shift click leaves the selection a list view would

The selection is read from Finder at every click and the anchor is the one
thing kept; the range replaces the runs it touches, a stand-in answers for a
deselected anchor, nothing selected measures from the first icon while the
view is not scrolled, and ⌘ Command with ⇧ Shift is Finder's own toggle. The
one swallow line and its order behind commit and select are unchanged.

Safety layer touched: ShiftClickResolver, ClickGuard. §9 of the checklist is
owed before the next release. Owes docs/functional.md §2 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 8: Core loses the two switches, and gains the retry's words

**Files:**
- Modify: `Sources/ShiftPickCore/Settings.swift`, `StringsSettings.swift`, `StringsMenu.swift`, `StringsHealthPage.swift`, `StringsSystemPage.swift`, `HealthReport.swift`, `HealthRules.swift`
- Delete: `Sources/ShiftPickCore/StringsSelectionPage.swift`
- Test: `Tests/ShiftPickCoreTests/SettingsTests.swift`, `HealthTests.swift`, `LocalizationTests.swift`

**Interfaces:**
- Produces: `Settings { showInMenuBar; onboardingCompleted }`; `HealthFacts` without `userEnabled`; `HealthRules.listener(_ status: TapLifecycle.Status) -> HealthLevel?`; `HealthReport.listenerWord(_ status:) -> String`; `SystemPageStrings.listenerTitle`, `.listenerHint`, `.listenerStoppedWarning`, `.startListeningButton`. Task 10 uses them. `Loc.settings.selection`, `.pageSelection`, `Loc.menu.enable`, `.statusOff` are gone.

- [ ] **Step 1: Rewrite `SettingsTests`**

```swift
import XCTest
import ShiftPickCore

/// The one switch, the flag the onboarding wizard writes, and the rule that keeps an older settings file
/// from resetting the rest. ShiftPick has no setting about what it does: the feature is always on, one way.
final class SettingsTests: XCTestCase {
    func testTheDefaultIsOn() {
        XCTAssertTrue(Settings().showInMenuBar)
    }

    /// A fresh install has not walked the wizard, so the wizard opens.
    func testOnboardingStartsUnwalked() {
        XCTAssertFalse(Settings().onboardingCompleted)
    }

    /// A file written by a build that still had *Enable ShiftPick* and the ⌘ Command switch loads, the two
    /// keys ignored, and keeps what it says about the rest.
    func testAFileWrittenByAnOlderBuildKeepsWhatItSaysAndIgnoresTheRest() throws {
        let data = Data(#"{"enabled": false, "commandShiftAdds": false, "showInMenuBar": false}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertFalse(settings.showInMenuBar)
        XCTAssertFalse(settings.onboardingCompleted)
    }

    func testAFileFromBeforeTheWizardOpensTheWizard() throws {
        let data = Data(#"{"showInMenuBar": true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: data).onboardingCompleted)
    }

    func testAnEmptyFileIsEveryDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)), Settings())
    }

    func testItSurvivesARoundTrip() throws {
        var settings = Settings()
        settings.showInMenuBar = false
        settings.onboardingCompleted = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }
}
```

- [ ] **Step 2: Rewrite `Settings.swift`**

```swift
import Foundation

/// Everything the user can choose, and the one thing it remembers about them. One switch and nothing
/// else about the feature: ShiftPick does one thing one way, and no setting turns it off or changes it.
///
/// Stored as one JSON blob in `UserDefaults` by `ShiftPickPlatform.SettingsStore`. Every property has a
/// default here and is decoded tolerantly, so a settings file written by an older build, which may carry
/// keys that no longer exist, never resets the rest of it.
public struct Settings: Codable, Equatable, Sendable {
    /// The menu-bar item. Hiding it leaves the app working; opening the bundle again is the way back to
    /// the Settings window.
    public var showInMenuBar: Bool = true

    /// Whether the last page of the onboarding wizard has been reached and its button pressed. Not a
    /// setting: no window shows it, and Settings > System offers the wizard again rather than this flag. A
    /// wizard closed before that last button keeps it false, so it opens again at the next launch.
    public var onboardingCompleted: Bool = false

    public init() {}

    /// Written out rather than synthesised: a key missing from an older file has to fall back to its
    /// default instead of failing the whole decode, and a key an older build wrote is left unread.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings()
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar)
            ?? fallback.showInMenuBar
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? fallback.onboardingCompleted
    }
}
```

- [ ] **Step 3: The strings**

`git rm -q Sources/ShiftPickCore/StringsSelectionPage.swift`. In `StringsSettings.swift` delete `pageSelection` and `public var selection: SelectionPageStrings { ... }`. In `StringsMenu.swift` delete `enable` and `statusOff`. In `StringsHealthPage.swift` replace `listenerStoppedFix` with:

```swift
    /// The way back is a button on the System page, under the listener's own row.
    public var listenerStoppedFix: String {
        switch language {
        case .en: "macOS interrupted \(AppIdentity.name) \(K.breakerTrips) times in "
            + "\(Int(K.breakerWindow)) seconds, so it stopped listening for clicks. Press "
            + "\u{201C}Start Listening Again\u{201D} on the System page."
        case .fr: "macOS a interrompu \(AppIdentity.name) \(K.breakerTrips) fois en "
            + "\(Int(K.breakerWindow)) secondes, il a donc cessé d'écouter les clics. Cliquez sur "
            + "\u{201C}Réécouter les clics\u{201D} sur la page Système."
        }
    }
```

In `StringsSystemPage.swift` add, before `// MARK: Start over`:

```swift
    // MARK: The click listener

    public var listenerTitle: String {
        switch language {
        case .en: "Click listener"
        case .fr: "Écoute des clics"
        }
    }

    public var listenerHint: String {
        switch language {
        case .en: "\(AppIdentity.name) listens for ⇧ Shift while you click. When macOS interrupts that "
            + "listener too often, \(AppIdentity.name) stops it and waits for you to start it again."
        case .fr: "\(AppIdentity.name) surveille ⇧ Majuscule pendant vos clics. Quand macOS interrompt "
            + "cette écoute trop souvent, \(AppIdentity.name) l'arrête et attend que vous la relanciez."
        }
    }

    public var listenerStoppedWarning: String {
        switch language {
        case .en: "macOS interrupted \(AppIdentity.name) \(K.breakerTrips) times in "
            + "\(Int(K.breakerWindow)) seconds. ⇧ Shift clicks are Finder's until you start listening again."
        case .fr: "macOS a interrompu \(AppIdentity.name) \(K.breakerTrips) fois en "
            + "\(Int(K.breakerWindow)) secondes. Les clics avec ⇧ Majuscule reviennent au Finder jusqu'à "
            + "ce que vous relanciez l'écoute."
        }
    }

    public var startListeningButton: String {
        switch language {
        case .en: "Start Listening Again"
        case .fr: "Réécouter les clics"
        }
    }
```

- [ ] **Step 4: Health without the switch**

`HealthRules.listener` becomes:

```swift
    /// The click listener, as the engine reports it (`TapLifecycle.Status`). **It is the mechanism the whole
    /// app rests on**: a listener macOS refused, or one the breaker stopped, is an app that does nothing at
    /// all, red. Nil is no line at all, and it is two cases: waiting for the permission, which the
    /// permission's own line already says (one cause, one line); and nothing reported yet, before the first
    /// start and after the quit.
    public static func listener(_ status: TapLifecycle.Status) -> HealthLevel? {
        switch status {
        case .watching: return .good
        case .refused, .breakerOpen: return .failure
        case .needsPermission, .stopped: return nil
        }
    }
```

In `HealthReport.swift`: delete `HealthFacts.userEnabled` (property, init parameter and assignment, doc line); change `listener(_ facts:)` to call `HealthRules.listener(facts.listener)` and to take its word from a new shared accessor:

```swift
    /// The one word the listener's row carries, on the Health page and on the System page alike.
    public static func listenerWord(_ status: TapLifecycle.Status) -> String {
        switch status {
        case .refused: Loc.settings.words.failed
        case .breakerOpen: Loc.settings.health.stopped
        case .watching, .needsPermission, .stopped: Loc.settings.words.enabled
        }
    }
```

and inside `listener(_ facts:)`:

```swift
        guard let level = HealthRules.listener(facts.listener) else { return nil }
        let t = Loc.settings.health
        let fix: String? = switch facts.listener {
        case .refused: t.listenerRefusedFix
        case .breakerOpen: t.listenerStoppedFix
        case .watching, .needsPermission, .stopped: nil
        }
        return HealthRow(id: "listener", label: t.clicksRow, level: level, word: listenerWord(facts.listener),
                         detail: "\(facts.listener)", fix: fix)
```

Update the `checks(for:)` doc: *"the click listener, once past waiting for the permission"*.

- [ ] **Step 5: Tests that move**

`HealthTests`: remove the `userEnabled: Bool = true` parameter of the `facts(...)` helper and its argument to `HealthFacts(...)`; change `HealthRules.listener(.watching, userEnabled: true)` and the two beside it to `HealthRules.listener(.watching)`; delete the loop asserting `switched off` (lines 43 to 46) and `testShiftPickSwitchedOffIsNoLine`; add:

```swift
    func testTheListenersWordIsSharedByBothPages() {
        XCTAssertEqual(HealthReport.listenerWord(.watching), Loc.settings.words.enabled)
        XCTAssertEqual(HealthReport.listenerWord(.breakerOpen), Loc.settings.health.stopped)
        XCTAssertEqual(HealthReport.listenerWord(.refused), Loc.settings.words.failed)
    }
```

`LocalizationTests`: remove the `("settings.pageSelection", …)` line and the whole `let selection = settings.selection` block; remove `("menu.enable", …)` and `("menu.statusOff", …)` if the menu roster has them (the compiler names any survivor); add to the system roster:

```swift
                     ("system.listenerTitle", system.listenerTitle),
                     ("system.listenerHint", system.listenerHint),
                     ("system.listenerStoppedWarning", system.listenerStoppedWarning),
                     ("system.startListeningButton", system.startListeningButton),
```

- [ ] **Step 6: Build Core and run**

Run: `swift build --target ShiftPickCore && swift test --filter "SettingsTests|HealthTests|LocalizationTests"`
Expected: green. (The App target does not build until Task 10; that is expected here.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ShiftPickCore/Settings.swift Sources/ShiftPickCore/StringsSettings.swift Sources/ShiftPickCore/StringsMenu.swift Sources/ShiftPickCore/StringsHealthPage.swift Sources/ShiftPickCore/StringsSystemPage.swift Sources/ShiftPickCore/StringsSelectionPage.swift Sources/ShiftPickCore/HealthReport.swift Sources/ShiftPickCore/HealthRules.swift Tests/ShiftPickCoreTests/SettingsTests.swift Tests/ShiftPickCoreTests/HealthTests.swift Tests/ShiftPickCoreTests/LocalizationTests.swift
git commit -m "feat(core): no setting about what ShiftPick does, and the words for starting the listener again

Owes docs/functional.md §5 and §6 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 9: `TapLifecycle` loses the kill switch

**Invoke the `shiftpick-safety-nets` skill first.** `TapLifecycle.swift`, `ClickGuard.swift` and `ShiftPickEngine.swift` are files of the safety layer. Nothing about arming, the live question, the breaker or the teardown changes; the one flag that could stop arming goes, and `.tryAgain` stays the only thing that closes the breaker.

**Files:**
- Modify: `Sources/ShiftPickCore/TapLifecycle.swift`, `Sources/ShiftPickPlatform/ClickGuard.swift`, `Sources/ShiftPickApp/ShiftPickEngine.swift`
- Test: `Tests/ShiftPickCoreTests/TapLifecycleTests.swift`, `TapLifecycleInvariantTests.swift`

**Interfaces:**
- Produces: `TapLifecycle()` (no argument); `TapLifecycle.Event` without `.userEnabled`; `ClickGuard(hooks:)`; `ShiftPickEngine.tryAgain()`. Task 10 calls `engine.tryAgain()`.

- [ ] **Step 1: Tests first**

In `TapLifecycleTests.swift`: every `TapLifecycle(userEnabled: true)` becomes `TapLifecycle()`; delete `testTheKillSwitchArmsNothing`, `testTurningShiftPickOffWhileArmedDisarms` and `testTurnedOffNothingIsLookedAt`. In `TapLifecycleInvariantTests.swift`: `TapLifecycle(userEnabled: true)` becomes `TapLifecycle()`, and generator case 21 becomes another modifier move so the draw stays 24 wide:

```swift
        case 21: return .modifiers(shift: false, optionOrControl: true)
```

Run: `swift test --filter "TapLifecycleTests|TapLifecycleInvariantTests"`
Expected: compile errors (`userEnabled`).

- [ ] **Step 2: `TapLifecycle`**

Delete `private var userEnabled: Bool`; `public init(userEnabled: Bool)` becomes `public init() {}`; delete the `/// The Settings switch.` line and `case userEnabled(Bool)` from `Event`; delete the whole `case .userEnabled(let enabled):` transition; replace the four `keysAskForIt && userEnabled` with `keysAskForIt` (in `.modifiers`'s `.idle where`, `.suspended where`, in `.trustProbe`'s `.trusted` branch, and in `.trustNotification`'s `.armed` branch).

- [ ] **Step 3: `ClickGuard` and the engine**

`ClickGuard`: `public init(hooks: Hooks) { self.hooks = hooks; lifecycle = TapLifecycle() }`; delete `setUserEnabled(_:)` and its doc comment.

`ShiftPickEngine`: `ClickGuard(hooks: ClickGuard.Hooks(` (drop `userEnabled: store.settings.enabled,`); delete both `store.$settings` sinks and the comment above them (the kill switch and the *turning it on again* one); add after `start()`:

```swift
    /// The System page's button, once the breaker has opened: the only thing that closes it, and it still
    /// asks the live question about the grant before anything is created.
    func tryAgain() { clickGuard.tryAgain() }
```

Delete the `private let store: SettingsStore` property if nothing else reads it (`init(store:)` may keep its parameter for `SettingsStore` wiring; if the compiler says the property is unused, remove it and the parameter, and fix `AppDelegate`'s `ShiftPickEngine(store: store)` to `ShiftPickEngine()`).

- [ ] **Step 4: Build and run the safety suites**

Run: `swift build --target ShiftPickPlatform && swift test --filter "TapLifecycleTests|TapLifecycleInvariantTests|SafetyNetTests"`
Expected: green; the invariant run still reports 80,000 events with no assertion failed.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShiftPickCore/TapLifecycle.swift Sources/ShiftPickPlatform/ClickGuard.swift Sources/ShiftPickApp/ShiftPickEngine.swift Tests/ShiftPickCoreTests/TapLifecycleTests.swift Tests/ShiftPickCoreTests/TapLifecycleInvariantTests.swift
git commit -m "refactor(taps): the lifecycle has no kill switch; another try is asked for through the engine

Safety layer touched: TapLifecycle, ClickGuard, ShiftPickEngine. §9 of the
checklist is owed before the next release. Owes docs/functional.md §1 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 10: Four pages, a menu without the switch, and the retry button

**Invoke `macos-building-settings-pages` first**, and `shiftpick-safety-nets` (the button reaches the breaker; `SafetyNetTests` gains a pin).

**Files:**
- Delete: `Sources/ShiftPickApp/SettingsSelectionPage.swift`
- Modify: `Sources/ShiftPickApp/SettingsView.swift`, `MenuBarController.swift`, `SettingsSystemPage.swift`, `SettingsHealthPage.swift`, `HealthCheck.swift`
- Test: `Tests/ShiftPickCoreTests/SafetyNetTests.swift`

- [ ] **Step 1: The pin, first**

Add to `SafetyNetTests`, under `// MARK: - Around the taps`:

```swift
    /// The breaker is closed by the user asking, and by nothing else: one button, through the engine, and
    /// the engine alone talks to the guard about it.
    func testAnotherTryIsAskedForThroughTheEngineAlone() throws {
        let sources = try swiftFiles(under: ["Sources"])
        XCTAssertEqual(occurrences(of: "clickGuard.tryAgain()", in: sources), ["Sources/ShiftPickApp/ShiftPickEngine.swift"],
                       "Only ShiftPickEngine.tryAgain asks the guard for another try (docs/functional.md §1).")
        XCTAssertEqual(occurrences(of: "engine.tryAgain()", in: sources), ["Sources/ShiftPickApp/SettingsSystemPage.swift"],
                       "Only the System page's Start Listening Again button asks the engine.")
    }
```

Run: `swift test --filter SafetyNetTests/testAnotherTryIsAskedForThroughTheEngineAlone`
Expected: FAIL (no `engine.tryAgain()` anywhere yet).

- [ ] **Step 2: Remove the Selection page**

`git rm -q Sources/ShiftPickApp/SettingsSelectionPage.swift`. In `SettingsView.swift`: delete `case .selection: SelectionPage(store: store)`; in `SettingsPageID` delete `selection` from the cases, `case .selection: Loc.settings.pageSelection` and `case .selection: "square.stack.3d.up"`; the enum's comment becomes *"General first, then what the app needs from the system, then its health, then the tip jar."*

- [ ] **Step 3: The menu**

In `MenuBarController.menuNeedsUpdate` delete the `enable` item, its `target`, `state`, `addItem(enable)` and the separator after it; delete `toggleEnabled()`; in `statusLine()` delete `if store?.settings.enabled != true { return words.statusOff }`. The menu is then: Launch at Login · status · Settings… · Quit, and `docs/functional.md` §6 is redrawn in Task 12.

- [ ] **Step 4: Health without the switch**

`HealthCheck.facts(_:granted:listener:)`: drop the `userEnabled: Bool` parameter and the `userEnabled:` argument. `SettingsHealthPage`: `health.facts(status, granted: granted, listener: engine.status)`, and remove `@ObservedObject var store: SettingsStore` if nothing else on the page reads it (fix the call site in `SettingsView`: `HealthPage(status: status, engine: engine, health: health)`).

- [ ] **Step 5: The System page's listener group**

In `SettingsSystemPage.body`, between the Accessibility group and the Start over group:

```swift
            // The click listener is what the whole app rests on, and the one state whose fix is a button
            // rather than a switch: when macOS has taken the click tap away too often, the breaker stays
            // open until the user asks for another try (docs/functional.md §1). The row stays once green so
            // that the link between the app and what it needs from macOS stays visible; the button and the
            // warning show only while the breaker is open. No line while the permission is missing: the
            // permission's own row says it.
            if let level = HealthRules.listener(engine.status) {
                let stopped = engine.breakerIsOpen
                SettingsGroup(title: words.listenerTitle, hint: words.listenerHint,
                              warnings: stopped ? [words.listenerStoppedWarning] : []) {
                    StatusRow(Loc.settings.health.clicksRow,
                              mark: StatusMark(level, HealthReport.listenerWord(engine.status)))
                    if stopped {
                        ButtonRow { Button(words.startListeningButton) { engine.tryAgain() } }
                    }
                }
            }
```

Update the page's doc comment: the listener is now here **with its button**, and on Health as a verdict.

- [ ] **Step 6: Build, then every test**

Run: `swift build && swift test`
Expected: build clean; **two** summary lines, both `0 failures`. Note the two totals for the Status section of `CLAUDE.md` (Task 12).

- [ ] **Step 7: Commit**

```bash
git add Sources/ShiftPickApp/SettingsSelectionPage.swift Sources/ShiftPickApp/SettingsView.swift Sources/ShiftPickApp/MenuBarController.swift Sources/ShiftPickApp/SettingsSystemPage.swift Sources/ShiftPickApp/SettingsHealthPage.swift Sources/ShiftPickApp/HealthCheck.swift Tests/ShiftPickCoreTests/SafetyNetTests.swift
git commit -m "feat(settings): four pages, no switch in the menu, and Start Listening Again on the System page

Owes docs/functional.md §5 and §6 (Task 12).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 11: `axdump range` works the click out the new way

**Files:**
- Modify: `Tools/axdump/main.swift` (`main`, `usage`, `range`; `views` where it prints an item's place)

**Interfaces:**
- Consumes: `LayoutModel.effectiveAnchor`, `.firstItem`, `.shiftClick`, `.readingPosition(of:)`, `FinderAX.selection`, `FinderAX.isScrolled`.

- [ ] **Step 1: The command takes an optional anchor point**

In `main`, the `"range"` case:

```swift
        case "range":
            guard arguments.count >= 4, let x = Double(arguments[2]), let y = Double(arguments[3])
            else { usage(); exit(1) }
            var anchorPoint: CGPoint?
            if arguments.count >= 6, let ax = Double(arguments[4]), let ay = Double(arguments[5]) {
                anchorPoint = CGPoint(x: ax, y: ay)
            }
            range(CGPoint(x: x, y: y), anchorPoint: anchorPoint)
```

and in `usage`: `  range <x> <y> [ax ay]   what a Shift-click there would select, measured from the icon at ax ay or from what is selected`.

- [ ] **Step 2: Rewrite `range`**

```swift
    /// What a ⇧ Shift click at this point would select, worked out exactly as the app works it out and
    /// printed rather than applied. With no anchor point the stored anchor reads as gone, which is what a
    /// fresh launch sees: a stand-in is named from the selection.
    static func range(_ point: CGPoint, anchorPoint: CGPoint?) {
        let pid = finderPID()
        guard case .item(let target) = FinderAX.hit(at: point, finderPID: pid, timeout: 5) else {
            print("not an item: the click would be let through")
            return
        }
        let items = FinderAX.items(in: target.view, timeout: 5)
        let elements = items.map(\.1)
        guard let targetIndex = FinderAX.index(of: target.item, among: elements) else {
            print("the item is not among the ones the view lists")
            return
        }
        let model = LayoutModel(items: items.map(\.0), fallbackFlow: target.view.fallbackFlow)
        let reading = FinderAX.selection(in: target.view, among: elements)
        print("layout: \(model.kind); \(items.count) items; \(reading.indices.count) selected on screen, "
              + "\(reading.unmapped.count) selected elsewhere")

        var stored: Int?
        if let anchorPoint, case .item(let anchorHit) = FinderAX.hit(at: anchorPoint, finderPID: pid, timeout: 5),
           CFEqual(anchorHit.view.container, target.view.container) {
            stored = FinderAX.index(of: anchorHit.item, among: elements)
        }
        var from = model.effectiveAnchor(stored: stored, selection: reading.indices)
        if from == nil {
            let scrolled = FinderAX.isScrolled(target.view)
            guard scrolled == false, let first = model.firstItem else {
                print("nothing selected and the view is scrolled or unreadable: the click would be let through")
                return
            }
            print("nothing selected; the view is not scrolled, so the first icon stands in")
            from = first
        }
        guard let from, let outcome = model.shiftClick(from: from, selection: reading.indices, target: targetIndex) else {
            print("the anchor or the target is not a file: the click would be let through")
            return
        }
        let how = stored == from ? "the anchor" : "a stand-in"
        let shape = if case .line = outcome.shape { "a line" } else { "a slice of the reading order" }
        print("measured from item \(from) (\(how)) to \(targetIndex), \(shape): \(outcome.shape.items.count) in the range, "
              + "\(outcome.selection.count) selected afterwards")
        for index in outcome.selection {
            let name = AX.string(elements[index], "AXIdentifier")
                ?? AX.string(elements[index], kAXTitleAttribute as String) ?? "?"
            let place = model.readingPosition(of: index).map(String.init) ?? "-"
            print("  [\(place)] \(name)\(outcome.shape.items.contains(index) ? "" : "   (kept)")")
        }
    }
```

In `views()`, where each item is printed with its flow place, print `model.readingPosition(of:)` instead of `flowPosition(of:)` so a hand-placed view lists its clusters in order too.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean. If the terminal is trusted for Accessibility, `swift run axdump range <x> <y>` over a Finder window prints the new lines; not required to commit.

- [ ] **Step 4: Commit**

```bash
git add Tools/axdump/main.swift
git commit -m "feat(axdump): range prints the stand-in, the shape and the selection the click would leave

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 12: The documents say what the app now does

**Files:**
- Modify: `docs/functional.md`, `docs/architecture.md`, `docs/macOS.md`, `docs/manual-test-checklist.md`, `docs/README.md`, `README.md`, `CHANGELOG.md`, `DECISIONS.md`, `CLAUDE.md` (the Status counts, the "Where a change usually lands" rows naming the rubber band and the Selection page)

Every edit replaces the old rule; none annotates it. The owner's answers from Task 0 go into `docs/macOS.md`.

- [ ] **Step 1: `docs/functional.md`**

§1 *Arming*: delete step 1 (the kill switch) and renumber. In the *timeout* paragraph, replace *"turning Enable ShiftPick off and on again is what asks for another try, which still asks the live question first"* with *"**Start Listening Again**, on the System page, is what asks for another try, which still asks the live question first"*.

§2 step 7 becomes: *"**Set the selection.** One call, whatever its size: the selection §2.2 describes, with every selected element Finder named that is not on screen handed back as it came."* Add step 2a after step 2: *"**⌘ Command held with ⇧ Shift is Finder's own toggle**, measured in its list view: the click passes, and the sentinel notes the anchor."*

Replace §2.1 wholesale with:

```markdown
### 2.1 Where a range is measured from, and what it leaves selected

ShiftPick keeps **one anchor per container** and nothing else: the selection is read from Finder at every
⇧ Shift click, and no earlier range is remembered. This is the list view's own model, measured on AppKit's
`NSTableView` and confirmed in Finder (`docs/macOS.md`, *The selection model*).

- **A plain click, a ⌘ Command click or a ⌘ Command ⇧ Shift click on an icon sets the anchor.** The sentinel
  hears it, and the click itself is never held. The anchor is looked for **`K.anchorDelay` (60 ms) later**,
  on the worker, and only if the application that owns the view is frontmost by then.
- **A plain click on empty space inside an icon view clears the anchor.** Finder has just deselected
  everything. A click outside Finder leaves it alone.
- **The anchor is per container**: each window has its own, and the Desktop has its own.
- **The click is measured from the anchor while it is selected.** When it is not, a **stand-in** is used: the
  first selected icon after it in reading order (§3), however far; else the last selected icon before it. An
  anchor that is gone, stale or in another container counts as one before everything, so the first selected
  icon in reading order stands in. **After the click, the anchor is the icon the range was measured from.**
- **Nothing selected**: the click measures from the first icon in reading order **while the view is not
  scrolled** (the Desktop never is); a scrolled view may hold its first icon off screen, and the click goes
  through.

### 2.2 What the click leaves selected

With the range R between the icon measured from and the target (§3):

- **Inside one reading order** (an arranged view, or one grid of a hand-placed one): **the old selection,
  minus every run of consecutive selected icons that R touches, plus R.** A run R touches goes whole, its part
  outside R included; a run R does not touch stays, whatever ⌘ Command clicks built it with. Selected icons
  in another grid are never touched.
- **A line** (§3.5): the old selection **plus** the icons the line touches.
```

§3: renumber the current 5. as *5. The range*, with **Arranged** unchanged and **Hand-placed** replaced by:

```markdown
   - **Hand-placed**: the icons are cut into **clusters** (two icons are linked when their centres are within
     `K.gridLinkPitches` (1.5) pitches on both axes, the pitch being the median distance from an icon to its
     nearest neighbour within `K.neighbourReachSides` (3) icon sides), and each cluster is fitted with **a
     grid**: rows and columns cut at every gap wider than `K.gridLineTolerancePitches` (half) a pitch, which
     makes sense when no row and no column is wider than that. A grid is read **along its rows from the
     leading edge, rows top to bottom**; clusters follow one another by top edge then leading edge. A range
     with both ends in one grid is the slice of that order between them. **Any other range is a line**: the
     segment between the two centres, `K.lineThicknessSides` (one) icon thick, and every icon whose frame it
     touches. Best effort, and never a guess far from the two icons.
```

§4: add after the panels paragraph: *"**Where it does nothing**: list, column and gallery views select a range on their own, and ShiftPick never touches them."* (already stated; keep one sentence).

§5: delete the **Selection** row; in the **System** row add: *"| | Click listener | *Watching for ⇧ Shift clicks*, the Health page's row in the same colour, always once past waiting for the permission; while the breaker is open, **Start Listening Again** under it and a warning saying what happened. |"*; in the **Health** row replace *"While *Enable ShiftPick* is on and the listener is past waiting…"* with *"While the listener is past waiting for the permission…"* and delete *"No line while the switch is off (a preference),"*; the colour paragraph loses *"(*Enable ShiftPick*, Launch at login)"* for *"(Launch at login)"*; **Defaults** becomes *"**Show in menu bar on**. Launch at login is the system's answer…"*; *"stored beside the three switches"* becomes *"stored beside the one switch"*.

§6: redraw the menu without the first item, and *"The status line is one of four"*, dropping *Off: Finder handles every click*.

- [ ] **Step 2: `docs/architecture.md`**

*The click path* tree: replace the four lines from `LayoutModel(items:)` to `LayoutModel.range(from:to:)` with:

```
  │         ├─ FinderAX.selection           one round trip: what Finder has selected now
  │         ├─ LayoutModel(items:)          the reading order: flow, or clusters fitted with grids
  │         ├─ effectiveAnchor              the anchor, or its stand-in in reading order
  │         ├─ LayoutModel.shiftClick       the runs the range touches replaced, or a line added
```

*The selection maths*: step 3 becomes *"A layout no order fits is hand-placed: `Clusters` cuts it into groups under the link rule, `Grid` fits each with rows and columns and reads it along its rows, and a range between two grids or into a scatter is a `LineBand` one icon thick. `ShiftClick` is the list view's rule over any of those orders."* Add `ShiftClick`, `Clusters`, `Grid`, `LineBand`, `LayoutConstants` to the Core row of *What lives where*. In *Persistence*, the switches row: *"The one switch, and whether the wizard has been walked"*.

- [ ] **Step 3: `docs/macOS.md`**

Add a section *The selection model* after *Finder's icon views*: how AppKit was measured (the harness in one paragraph: a real `NSTableView`, events posted to the process's own queue, the app active and the window key), the table of §2.1 of the spec, and Finder's own answers from Task 0 (protocol P, M2, M3, M4) as measured facts, with the date and the macOS build. Also add to *What Finder does not give you* whatever M2 found about off-screen selected children.

- [ ] **Step 4: `docs/manual-test-checklist.md`**

§1: delete the two switch lines; replace the ⌘ Command line with *"⌘ Command click a file elsewhere, then ⇧ Shift click further on: the first range stays, and the new one runs from the ⌘ Command clicked file. ⇧ Shift click back inside the new range: it narrows and the first range still stays. ⌘ Command ⇧ Shift click: Finder toggles the one file, as in a list view."*; add *"⌘ Command click a file inside a range to deselect it, then ⇧ Shift click further on: the range runs from the first selected file after the deselected one, which stays deselected."* and *"Nothing selected, view at the top: ⇧ Shift click selects from the first file. Scroll down first: the click goes to Finder and `log stream --level debug` says `nothing selected, and the first icon may be off screen`."*
§2 and §3: replace the rubber band lines with *"Sort By None, icons dragged into a rough grid by hand: `axdump views` says `handPlaced(grids: 1, scatters: 0)`, and a range reads along the rows. Drag two groups apart (an empty column between): two grids; a ⇧ Shift click from one into the other selects a **line** one icon thick between the two icons and nothing else."*
§6: the empty-space line's expectation becomes the §1 nothing-selected line. §9 line 192 (*Enable ShiftPick off*): replace with *"Breaker open (after the drill's three timeouts): the System page shows Start Listening Again; press it: the log says `another try was asked for` and then `listening`."* §12: replace the Selection page line with the four-page toolbar.

- [ ] **Step 5: `README.md`, `docs/README.md`, `CHANGELOG.md`, `DECISIONS.md`, `CLAUDE.md`**

`README.md`: the ⌘ Command row of the gesture table becomes *"⌘ Command ⇧ Shift | Finder's own: the one file is toggled"*, a new row *"⌘ Command click, then ⇧ Shift click | The earlier selection stays; the range runs from the ⌘ Command clicked file, exactly as in a list view"*; the Settings table loses the Selection row; the paragraph on arranged/hand-placed replaces *rubber band* with *grids read along their rows, or a line one icon thick between two grids*.
`docs/README.md` line 41: *"…whether a layout is arranged or hand-placed, its clusters and grids, and which icons lie between…"*.
`CHANGELOG.md`: a new top entry for the version being prepared, one bullet per change of spec §1.
`DECISIONS.md`: replace the two anchor rows (*farthest from the target*, *distance is flow order…*) with one: *"The anchor rule is the list view's own, measured | AppKit's model, replayed from `NSTableView`: a deselected anchor is stood in by the first selected row after it, and a ⇧ Shift click replaces the runs it touches. One rule for every view Finder has."*; add *"A ⌘ Command ⇧ Shift click is let through | Measured as Finder's own toggle; ShiftPick has no meaning of its own for it."*, *"A hand-placed range is a grid's row order or a line, never a rectangle | The owner asked for grids read as a list is read; the line is the fallback that is never far wrong."*, *"No setting about the feature | The owner asked for a feature enabler with nothing to configure; the two switches went with their page."*; the *Five pages* row becomes *Four pages: General, System, Health, Tip*; the listener-line row loses *"while the switch is off"*; add *"Start Listening Again lives on the System page | The skill's rule for a state the user can fix: the row, and while red a button and a warning. The menu and a relaunch were the alternatives."*
`CLAUDE.md`: Status counts (from Task 10's two summary lines), the *Where a change usually lands* rows for the range (`Clusters`, `Grid`, `LineBand`, `ShiftClick`) and for the anchor (`effectiveAnchor`, `ShiftClick.standIn`), the *what one ⇧ Shift click does* row (`selection` read, `shiftClick`), and the Settings row (four pages).

- [ ] **Step 6: Check the documents against the code**

Run: `rg -n "rubber band|Enable ShiftPick|commandShiftAdds|farthest from the target|derivedAnchor|five-page|Five pages|pageSelection" docs README.md CHANGELOG.md DECISIONS.md CLAUDE.md`
Expected: no line left except in `docs/superpowers/` (the spec and this plan record the change) and `docs/pitfalls.md` 1's sentence about the rubber band, which is rewritten to *"the in-between icons of a slice lie geometrically between the two ends, and a line is bounded by their two centres"*.

- [ ] **Step 7: Commit**

```bash
git add docs/functional.md docs/architecture.md docs/macOS.md docs/manual-test-checklist.md docs/README.md docs/pitfalls.md README.md CHANGELOG.md DECISIONS.md CLAUDE.md
git commit -m "docs: the native selection model, inferred grids and the line, and no Selection page

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NSCoHqcdabAeQULVeTmnKR"
```

---

### Task 13: Verification and hand-over

- [ ] **Step 1: The whole tree**

Run: `swift build && swift test 2>&1 | rg "Executed .* tests"`
Expected: **two** lines, both with `0 failures`; `ShiftPickCoreTests`' count is higher than 262 and `ShiftPickPlatformTests`' is 38.

- [ ] **Step 2: The safety suites by name**

Run: `swift test --filter "SafetyNetTests|TapLifecycleTests|TapLifecycleInvariantTests|DeadlineGateTests|TapThreadTests|TrustVerdictTests|BoundedWaitTests"`
Expected: every suite green.

- [ ] **Step 3: The gates' view of the safety layer**

Run: `sh -c '. scripts/safety-gates.sh 2>/dev/null; for f in $SAFETY_FILES; do echo $f; done' | xargs git diff --name-only HEAD~12 --`
Expected: it names `ShiftClickResolver.swift`, `ClickGuard.swift`, `TapLifecycle.swift`, `ShiftPickEngine.swift` and nothing else of the layer. (If the script cannot be sourced that way, read `SAFETY_FILES` from it by eye.)

- [ ] **Step 4: Nothing left behind**

Run: `sh scripts/no-leftovers.sh && git status --short`
Expected: nothing under `build/`, a clean tree.

- [ ] **Step 5: Hand over, in these words**

> The tree builds and both test bundles are green (counts). Four files of the safety layer changed
> (`ShiftClickResolver`, `ClickGuard`, `TapLifecycle`, `ShiftPickEngine`), so **§9 of
> `docs/manual-test-checklist.md` is owed on an installed build before the next release**, and `make
> release` will refuse until you say `DRILL=walked` or `DRILL=waived`. Before installing, please walk
> protocol P of the spec in a Finder list view if Task 0 has not been done; then `make install`, and the
> new lines of §1 to §3 and §6 of the checklist.

Nothing is installed or published by this plan.

## Self-review

- **Spec coverage.** §2 → Task 1 (the rule) and 7 (the click); §3.1 → Tasks 3 and 5; §3.2, §3.3 → Task 7 and the sentinel; §3.4 → Tasks 1 and 5 (`effectiveAnchor`); §3.5 → Tasks 4 and 5; §3.6 → Tasks 6 and 7 (`isScrolled`, `firstItem`); §3.7 → Task 6 (`unmapped`); §5 → Tasks 2 to 5; §6 → Tasks 8 to 10; §7 tests → each task; §8 → Task 12; §9 limits → Task 12 (§4 of functional.md and the checklist); §10 → the owner's word, recorded in Task 12's commit; §11 → Task 0.
- **Types.** `RangeShape.items`, `LayoutModel.Outcome { selection, anchor, shape }`, `effectiveAnchor(stored:selection:)`, `shiftClick(from:selection:target:)`, `firstItem`, `readingPosition(of:)`, `FinderAX.SelectionReading { indices, unmapped }`, `FinderAX.isScrolled(_:)`, `HealthRules.listener(_:)`, `HealthReport.listenerWord(_:)`, `ShiftPickEngine.tryAgain()`, `ClickGuard(hooks:)`, `TapLifecycle()` are spelt the same in every task that names them.
- **Placeholders.** None: every code step carries its code; the documents task carries its replacement sentences.
