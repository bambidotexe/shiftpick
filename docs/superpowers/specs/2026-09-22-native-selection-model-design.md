# ShiftPick: the native selection model, grid inference, and no settings — design

**Status: draft for the owner's review.** Decisions marked *recommended* are the ones this design is built on;
each has the alternative beside it. §10 lists the rules of `docs/functional.md` this design overrules, quoted,
which the workflow in `CLAUDE.md` says nothing changes until the owner has said so.

## 1. What changes, and what does not

Three changes, asked for together:

1. **ShiftPick has no settings about what it does.** The *Selection* page goes, with both of its switches
   (*Enable ShiftPick*, *⌘ Command with ⇧ Shift adds the range to the selection*). The feature is always on,
   and it does one thing one way.
2. **A ⇧ Shift click in an icon view selects exactly what the same clicks would select in Finder's list,
   column or gallery view.** Every combination of plain, ⌘ Command, ⇧ Shift and ⌘ Command ⇧ Shift clicks, in
   any order, ends with the same selection it ends with in a list view. The list view's order is top to
   bottom; an icon view's is its grid, read along the lines Finder fills it (§4).
3. **A view Finder is not laying out gets grids inferred from where the icons are**, one grid per cluster of
   icons, tolerant of a grid somebody placed by hand. A range runs inside one grid, in reading order. When
   no grid can be made out, or the two ends are in different grids, the range is **the rubber band, as
   today**: the rectangle the two icons span, and every icon whose centre falls inside it.

Unchanged: **where it works** (every Finder icon view, the Desktop, and Open and Save panels shown as icons;
list, column and gallery views are never touched), the safety model and every one of its nets
(`docs/functional.md` §0), the shape of the click path (the taps, the worker, the budget), the anchor being
looked for after a plain click rather than the click being held, and everything about the update, the
onboarding, the uninstall and the Health page's readings.

## 2. What the native views do: measured

The rules below are not remembered; they were measured. Finder's list view is an `NSOutlineView`, and the
column and gallery views select through the same AppKit machinery, so **AppKit's `NSTableView` was driven
directly**: a throwaway harness (a real window, a real `NSTableView` with multiple selection, synthetic
`NSEvent`s posted to the process's own event queue with `NSApplication.postEvent`, so nothing touched the
system event stream and no tap was involved) ran fifteen hand-written sequences (about sixty clicks) and then, for 22 constructed
states, one ⇧ Shift click and one ⌘ Command ⇧ Shift click from every one of twelve rows. Appendix A holds
the data. **The owner confirms the same sequences in a Finder list view before the code is written** (§11,
protocol P); where Finder differs from AppKit, Finder wins and this section is corrected.

### 2.1 The model

The state is two things and nothing else: **the set of selected rows** and **one anchor row**, which may be
deselected and may not exist. There is no memory of earlier ranges: three different histories that reach the
same selection and the same anchor answer every later click identically (states B, B′, B″).

| Click | The selection | The anchor |
|---|---|---|
| **plain click on r** | becomes {r} | r |
| **⌘ Command click on r** | r is toggled; nothing else moves | r, whether r ended selected or not |
| **⌘ Command ⇧ Shift click on r** | **the same as a ⌘ Command click**: r is toggled | r |
| **⇧ Shift click on t** | see below | the row the range was measured from (§2.3) |

### 2.2 The ⇧ Shift click

With effective anchor *e* (§2.3) and target *t*, the range is **R = [min(e, t), max(e, t)]**, and the new
selection is

> **(the old selection, minus every maximal run of consecutive selected rows that intersects R) ∪ R.**

A *run* is a maximal set of consecutive selected rows. Every run R touches is removed whole, including the
part of it outside R; every run R does not touch stays. Examples, from the data:

| Before | Anchor | ⇧ Shift click | After | Why |
|---|---|---|---|---|
| {1,2,3,5} | 5 | 7 | {1,2,3,5,6,7} | R=[5,7] touches only {5}; {1,2,3} stays. **The owner's own example.** |
| {1,2,3,5,6,7} | 5 | 6 | {1,2,3,5,6} | R=[5,6] touches {5,6,7}, which goes whole; the range comes back narrower |
| {1,2,3,5,6,7,8,9} | 5 | 4 | {1,2,3,4,5} | R=[4,5] touches {5..9}; {1,2,3} does not contain 4 or 5, so it stays |
| {2,5,6,7,8} | 8 | 10 | {2,8,9,10} | R=[8,10] touches {5,6,7,8}, which goes whole, 5 to 7 with it |
| {1,2,3,6,7,8} | 8 | 2 | {2,3,4,5,6,7,8} | R=[2,8] touches both runs; 1 goes although it is outside R |
| {1,2,3,4,5} | 1 | 3 | {1,2,3} | the ordinary narrowing: one run, replaced |
| {3,7} | 3 | 5 | {3,4,5,7} | R=[3,5] touches {3}; {7} is adjacent to nothing in R and stays |

Two consequences worth saying in words: a ⇧ Shift click **never removes a selected row it does not reach**
unless that row is in one unbroken run with a row it does reach; and a ⇧ Shift click after a ⌘ Command click
keeps everything the ⌘ Command clicks built, which is the behaviour the owner asked for.

### 2.3 The effective anchor

The click is measured from the anchor when the anchor is selected. When it is not, a **stand-in** is used:

1. the anchor, if it is selected;
2. else the **first selected row after it** (whatever its distance: {2,7} with anchor 4 stands in 7);
3. else the **last selected row before it**;
4. else, nothing being selected, **the first row**.

An anchor that does not exist (a fresh view, a selection nothing clicked for) behaves as an anchor before
every row: the first selected row stands in, or the first row. **After the click, the anchor is the row the
range was measured from**, the stand-in included (state W).

### 2.4 What is left to Finder

A plain click and a ⌘ Command click change the selection the way Finder's icon view already does, and ShiftPick
only notes the anchor. A ⌘ Command ⇧ Shift click is, in AppKit, a ⌘ Command click; if Finder's list view
agrees (protocol P, sequence S7), ShiftPick **lets it through** and notes the anchor. ⌥ Option and ⌃ Control
stay Finder's, as today.

## 3. The rules for icon views

Everything in §2 is stated over a **reading order**, which a list view has by construction and an icon view
has to be given. Once every icon has a place in one order, §2 applies word for word: rows become icons, runs
become runs of consecutive icons in that order.

### 3.1 The order

- **Arranged** (Finder is laying the view out): unchanged. The fill order inferred today, inside every group,
  groups top to bottom. A window fills rows from the leading edge; **a sorted Desktop fills columns from the
  trailing edge, and the order follows the columns**, because that is what the eye follows on a sorted
  Desktop (*recommended*; the alternative, rows left to right on every view, would make a range down one
  column of a sorted Desktop take every other column with it).
- **Hand-placed**: the icons are cut into **clusters** (§5), each cluster is fitted with a **grid**, and a
  grid is read **along its rows from the leading edge, rows top to bottom**: the first icon of the second row
  follows the last icon of the first. Clusters are ordered by their top edge, then their leading edge, and a
  cluster's icons follow the previous cluster's; a cluster in which no grid makes sense orders its icons by
  their top edge then their leading edge. **A range never crosses a cluster**: the global order across
  clusters exists only so that §2.3 can name a stand-in.

### 3.2 The state

ShiftPick keeps **one anchor per container** (an Accessibility element, as today) and reads **the selection
live from Finder** at every ⇧ Shift click. It remembers nothing about earlier ranges, exactly like AppKit:
whatever the user did meanwhile with the mouse, the keyboard, a drag or ⌘ A is simply what is selected now.

### 3.3 The clicks

- **A plain or ⌘ Command click on an icon sets the anchor**, looked for `K.anchorDelay` later on the worker
  (unchanged). **A ⌘ Command ⇧ Shift click sets it too** and is otherwise Finder's (§2.4).
- **A plain click on empty space clears the anchor** (unchanged; Finder deselected everything).
- **A ⇧ Shift click**: the effective anchor (§3.4), the range (§3.5), the new selection (§2.2 or §3.5's band
  rule), set in one call, the click swallowed, the anchor set to the icon the range was measured from.

### 3.4 The effective anchor

§2.3 over the reading order: the stored anchor if it is among the selected icons on screen; else the first
selected icon after it in reading order; else the last selected icon before it; **a stored anchor that is
gone, stale or in another container counts as an anchor before everything**, so the first selected icon in
reading order stands in. **Nothing selected** and no anchor: see §3.6.

### 3.5 The range

- **Effective anchor and target in the same order** (an arranged view, or one cluster with a grid): the
  slice of the reading order between them, inclusive, and the new selection is §2.2's, runs replaced.
- **Otherwise** (two clusters, or a cluster with no grid): **the rubber band**, unchanged from today: the
  anchor, the target, and every icon whose centre falls inside the rectangle their two frames span. The new
  selection is **the old selection plus the band** (*recommended*: memoryless, like AppKit, and the band is
  a fallback; the alternative, replacing the last band ShiftPick drew in that container when the selection
  is still exactly what that click left, would allow narrowing across clusters at the cost of one
  remembered range).
- **A collapsed Desktop stack is not a file** (unchanged): never in a range, and a click whose anchor or
  target is one goes through.
- Total, symmetric, deterministic, `O(n log n)`, as today; §7 pins them.

### 3.6 Nothing selected, no anchor

The list view selects from its first row. The icon view's first icon may not be on screen (Finder builds only
what is visible, `docs/pitfalls.md` 1), and a range that quietly starts elsewhere is worse than none. So
(*recommended*): **from the first icon in reading order when the view is not scrolled** (its container's top
edge is at or below its scroll area's top edge, one frame read of the parent; the Desktop never scrolls),
and the click goes through when it is, logged. The alternative is to let the click through in every such
case, as today.

### 3.7 Selected items that are not on screen

Finder may name items in `AXSelectedChildren` that it has not built, and the one call that sets the
selection replaces all of it. **Every selected element ShiftPick cannot map to an icon on screen is kept in
the new selection verbatim.** Whether Finder ever reports such an element is a platform fact to measure (§11,
M2); the rule costs nothing either way.

## 4. Reading order examples

A 3 × 4 window, sorted (arranged, rows from the left), icons numbered in reading order:

```
 1  2  3  4
 5  6  7  8
 9 10 11 12
```

click 1, ⇧ Shift click 5 → {1,2,3,4,5} (the whole first row and the first of the second: the owner's
example). Then ⌘ Command click 8 → {1,2,3,4,5,8}; ⇧ Shift click 10 → {1,2,3,4,5,8,9,10}; ⇧ Shift click 6
→ R=[6,8] touches {8,9,10} → {1,2,3,4,5,6,7,8}.

## 5. Grid inference for a hand-placed view

Input: every icon's frame (the icon's own box, `docs/macOS.md`). The arranged test runs first and is
unchanged; what follows is only for a view it refuses.

1. **The pitch** *p*: the median, over the icons, of the distance from an icon's centre to its nearest
   neighbour's centre, looked up in a spatial hash of cell *3 × side* (an icon with no neighbour within
   three sides is left out of the median). This survives wobble, which the coarse two-pass pitch of the
   lattice does not: a hand-placed row that wanders twenty points splits into several coarse groups and
   drags that pitch down.
2. **Clusters**: two icons are linked when their centres are within **1.5 p** of each other on both axes
   (orthogonal and diagonal neighbours of a grid are within one pitch and a bit of wobble; an empty row or
   column between two groups is two pitches, and breaks the link). Clusters are the connected components,
   found with union-find over the same spatial hash: `O(n)` expected.
3. **A grid per cluster**: its centres' *y* values are cut into rows at every gap wider than **p / 2**, its
   *x* values into columns the same way (the lattice's own one-dimensional clustering, `Lattice.cluster`).
   The grid **makes sense** when no row and no column is wider than **p / 2** (a line that only exists
   because a scatter chained together is wider). Two icons in one cell keep the order Accessibility listed
   them in. A cluster of one or two icons is always a grid.
4. **Reading order** inside a grid: row by row from the top, along each row from the leading edge (mirrored
   for a right-to-left layout, like the arranged flows).
5. **The rubber band** (§3.5) is the rule the code already has and needs nothing new.

The three numbers (1.5, 1/2, three sides) live in a **new `Core/LayoutConstants.swift`**, an extension of `K`
kept out of `Constants.swift`, which is a file of the safety layer, exactly as `HealthConstants.swift` is.
Each carries the reason above. **They are best-effort tolerances, not guarantees**, and the manual checklist
says what a wobbly grid looks like when they hold and when they do not.

**The engine as built refines this section.** §5.1's pitch takes one sample per icon and per direction, so
that an icon wobbled towards this one and one wobbled away cancel, passes over an icon that overlaps
another, and measures its reach and its overlap in sides of an icon no smaller than 64 points, which is what
a label-driven cell is; §5.3's verdict holds only the rows to the tolerance and, past `K.gridAlwaysCount`
icons, asks that some row or column be shared by two of them. `docs/functional.md` §3 and the grid engine's
report (`.superpowers/sdd/2026-09-22-native-selection-model/task-2-3-report.md`) are the statement of
record; this section is the design they started from.

## 6. The settings, the menu, the Health page, and the breaker

- **`Core/Settings.swift`** keeps `showInMenuBar` and `onboardingCompleted` and loses `enabled` and
  `commandShiftAdds`. Decoding stays tolerant, so a file written by today's build loads with the two keys
  ignored.
- **The Settings window has four pages**: General, System, Health, Tip. `SettingsPageID.selection`,
  `SelectionPage`, `StringsSelectionPage.swift` and `pageSelection` go, and `LocalizationTests`' roster with
  them.
- **The menu** loses *Enable ShiftPick* and the *Off: Finder handles every click* line.
- **`TapLifecycle` loses `userEnabled` and the `.userEnabled` event.** Its scenarios that used the switch go,
  and the invariant generator's case for it. The breaker keeps `.tryAgain` as the only thing that closes it.
- **Asking for another try** (the breaker open, §0 guarantee 2 unchanged: *no tap exists until the user asks
  for another try*), *recommended*: **the System page gets the click listener's row** (*Watching for ⇧ Shift
  clicks*, in the Health page's colour, green *Enabled* or red *Stopped* or *Failed*) **and, while the breaker
  is open, a button under it, *Start Listening Again*, with a warning saying what happened**; once green the
  button and the warning go and the row stays, which is the skill's rule for a state the user can fix. The
  Health page's fix sentence names that button. The alternatives: a *Try Again* item in the menu (a second
  place), or quitting and reopening the app (no control at all; the breaker is not persisted).
- **Health**: `HealthRules.listener` loses its `userEnabled` parameter; the listener's line shows whenever
  the status is past waiting for the permission. `HealthFacts.userEnabled` goes.

## 7. Where it lands, and what pins it

| Layer | Change |
|---|---|
| **Core** | `ShiftClick` (new): §2 as a value over ranks, `resolve(anchor:selection:target:) → (selection, anchor)`. `LayoutModel`: `kind` grows a hand-placed detail (grids, scatters), `place(of:) → (cluster, rank)`, `range(from:to:) → .ordered([Int]) / .band([Int])`, `firstItem`, and the stand-in rule replacing `derivedAnchor`. New `Clusters`, `Grid`, `LayoutConstants`. `Settings`, `TapLifecycle`, `HealthReport`, `HealthRules`, `Strings*` as §6. |
| **Platform** | `FinderAX.selection` also returns the elements it could not map; `FinderAX.isScrolled(view)`; `ClickGuard`: the sentinel notes the anchor for any press with ⌘ Command held or without ⇧ Shift, one condition. |
| **App** | `ShiftClickResolver.shiftClick`: read the selection, the effective anchor, `LayoutModel.range`, `ShiftClick.resolve` or the band added, the unmapped elements kept, one `select`, `commit`/`finish` untouched in shape and order, the anchor set to what it measured from; ⌘ Command ⇧ Shift passes. `ShiftPickEngine`: no options, `tryAgain` exposed. Settings pages, menu, Health as §6. |
| **Tools** | `axdump range` prints the clusters, the shape (ordered or rubber band), the stand-in and the selection §2 would leave, from an optional anchor point. `axdump views` prints each cluster and whether it made a grid. |

Tests: **`ShiftClickTests`** replays Appendix A verbatim over a twelve-item single column (every row of the
table is one assertion); `GridInferenceTests` (clusters, wobble inside and outside tolerance, two grids, a
scatter, one or two icons, right to left); `RangeSelectionTests` keeps every arranged case and every
rubber-band case, adds the grids, and keeps its three properties and its five thousand icons; `StandInTests` replaces `AnchorTests`;
`SettingsTests`, `HealthTests`, `LocalizationTests`, `TapLifecycleTests`, `TapLifecycleInvariantTests`
updated. **`SafetyNetTests` moves with the code and asserts the same things**: one swallow line, after
`commit`, after `select`; and one new pin, that the System page's button reaches the breaker only through
`ShiftPickEngine.tryAgain`.

**Files of the safety layer touched**: `ShiftClickResolver.swift`, `ShiftPickEngine.swift`,
`TapLifecycle.swift`, `ClickGuard.swift`. **§9 of `docs/manual-test-checklist.md` is owed** on an installed
build before the next release, and `make release` will refuse until the owner says so. No net is loosened:
the click tap's arming, the live question, the budget, the one swallow line and its order, the breaker, the
teardown are exactly as they are. The one wording that moves is *how* the user asks for another try.

## 8. Documents

`docs/functional.md` §1 (arming step 1 goes; the breaker's *another try* sentence names the button), §2
(step 7 and the ⌘ Command rule), §2.1 (rewritten as §3.3 and §3.4 above), §3 (5. and the new §5 above), §5
(the Selection row goes, System gains the row and the button, Health's rule), §6 (the menu), the defaults
line; `docs/architecture.md` (*The click path*, *The selection maths*, the Core table); `docs/macOS.md`
(what M1 to M3 measured, and the AppKit model as a platform fact with Appendix A's method); `README.md`,
`CHANGELOG.md`, `DECISIONS.md` (the anchor rule, the hand-placed range, the five pages, the listener line: replaced,
not annotated); `docs/manual-test-checklist.md` (§1 to §3, §6, §7, §12 rewritten for the new gestures, and a
new section for wobbly grids); `docs/README.md` where it describes a hand-placed range.

## 9. Known limits, stated

- A right click (⌃ Control click, or the secondary button) selects an item in Finder and, in a list view,
  moves the anchor. The sentinel does not listen to the secondary button, so the anchor is not moved by one;
  the stand-in rule then measures from the first selected icon after the stale anchor. Listening to
  `rightMouseDown` is a feature that listens to input and is designed with the owner if wanted.
- Both ends of a range still have to be on screen (`docs/pitfalls.md` 1); the stand-in and §3.6 obey the
  same limit.
- A grid is inferred, so a grid a person would see and the tolerances do not gets the rubber band, which
  selects the rectangle between the two icons rather than a run of the grid.

## 10. Rules this design overrules (the owner's word is needed for each)

From `docs/functional.md`:

1. §1, Arming, step 1: *"The kill switch is read first. With Enable ShiftPick off nothing is armed…"* → goes.
2. §1: *"turning Enable ShiftPick off and on again is what asks for another try"* → the System page's button.
3. §2, step 7: *"With ⌘ Command held and the switch on, the range is added to what was already selected
   instead of replacing it; with the switch off, a ⌘ Command ⇧ Shift click is left to Finder entirely."* →
   §2.4 (Finder's own meaning, measured).
4. §2.1: *"A ⇧ Shift click does not move the anchor."* → it is set to the icon the range was measured from,
   which is the anchor itself except when a stand-in was used.
5. §2.1: *"If the stored anchor is gone, stale, or in another container, it is derived from what is selected…
   the selected file farthest from the target."* → §3.4.
6. §2.1: *"If nothing is selected there either, the click goes through."* → §3.6.
7. §3, 5: *"Hand-placed: the anchor, the target, and every icon whose reference point falls inside the
   rectangle their two frames span. A rubber band drawn between the two icons."* → narrowed: a hand-placed
   **grid** reads along its rows (§3.1), and the rubber band stays for two grids and for a cluster with no
   grid (§3.5).
8. §5: the *Selection* row of the table, and *"Defaults: Enable ShiftPick on, ⌘ Command adds on"*.
9. §6: *Enable ShiftPick ✓* in the menu and the status line *Off: Finder handles every click*.

None of §0 changes. Guarantee 2's *"until the user asks for another try"* keeps its words and changes its
button.

## 11. Measurements owed before the code (the plan's first task)

**P. Finder's list view.** In a folder of twelve files in list view, the owner performs each sequence and
notes the selection after every click; the expected column is AppKit's answer (Appendix A). One deviation
anywhere corrects §2 before anything is built.

| # | Sequence | Expected (AppKit) |
|---|---|---|
| S1 | click 1 · ⇧3 · ⌘5 · ⇧7 | {1,2,3}, {1,2,3,5}, **{1,2,3,5,6,7}** |
| S2 | then ⇧6 · ⇧9 · ⇧4 | {1,2,3,5,6}, {1,2,3,5,6,7,8,9}, {1,2,3,4,5} |
| S3 | click 1 · ⇧5 · ⇧3 · ⇧8 | {1..5}, {1,2,3}, {1..8} |
| S4 | click 1 · ⇧5 · ⌘3 · ⇧2  /  again with ⇧8 last | {1,2,4,5} then **{2,3,4}**  /  **{1,2,4,5,6,7,8}** |
| S5 | click empty space · ⇧4 | {1,2,3,4} |
| S6 | ⌘A · ⇧3 | {1,2,3} |
| S7 | click 1 · ⇧3 · ⌘6 · ⌘⇧8 · ⌘⇧7 · ⇧9 | {1,2,3,6,**8**} (a toggle, not a range), {1,2,3,6,7,8}, {1,2,3,7,8,9} |
| S9 | click 3 · ⇧6 · ⇧3 | {3,4,5,6}, {3} |
| S10 | ⌘2 · ⌘5 · ⌘8 · ⇧6 · ⇧10 | {2,5,6,7,8}, **{2,8,9,10}** |
| S11 | click 1 · ⇧5 · click 3 · ⇧6 | {3}, {3,4,5,6} |
| S12 | rubber-band rows 3 to 5 from empty space · ⇧8  /  ⇧1 | {3..8}  /  {1,2,3} |
| S13 | click 4 · ⌘4 · ⇧7 | {}, {1..7} |
| S14 | click 1 · ⇧3 · ⌘8 · ⇧10 · ⇧6 · ⇧2 | {1,2,3,8,9,10}, {1,2,3,6,7,8}, {2..8} |
| W | click 1 · ⇧5 · ⌘3 · ⇧6 · then ⌘3 · ⇧1 | {1,2,4,5,6}, {1,2,3,4,5,6}, then **{1,2,3,4}** if the anchor moved to 4 |

**M2.** In icon view, select three icons, scroll them off screen, and read `AXSelectedChildren` with the
probe: does it still name them; set a selection through it: do they stay selected. Decides whether §3.7's
rule ever has work to do.

**M3.** In icon view, ⌘ Command ⇧ Shift click an icon with others selected: Finder's own icon view toggles
it, or not. Confirms §2.4's pass-through is safe (it is only unsafe if Finder's icon view did something
worse than a toggle with the click).

## Appendix A: the AppKit data

Harness: an `NSTableView` of twelve rows, `allowsMultipleSelection`, the app activated and the window key
(a plain press on a non-key window is eaten as the activation click), each click a `leftMouseDown` and
`leftMouseUp` with the same event number posted with `NSApplication.postEvent` and pumped through
`sendEvent`. macOS 27.0. Rows are 1-based below.

**Sequences** (the fifteen hand-written ones all agree with the model; a selection):

```
click 1 → {1}; ⇧3 → {1,2,3}; ⌘5 → {1,2,3,5}; ⇧7 → {1,2,3,5,6,7}; ⇧6 → {1,2,3,5,6}; ⇧9 → {1,2,3,5..9}; ⇧4 → {1,2,3,4,5}
click 1; ⇧5 → {1..5}; ⇧3 → {1,2,3}; ⇧8 → {1..8}
click 1; ⇧5; ⌘3 → {1,2,4,5}; ⇧2 → {2,3,4}          click 1; ⇧5; ⌘3; ⇧8 → {1,2,4,5,6,7,8}
(nothing selected) ⇧4 → {1,2,3,4}                  deselect all; ⇧6 → {1..6}
select all; ⇧3 → {1,2,3}                           select all; ⇧10 → {1..10}
click 1; ⇧3; ⌘6 → {1,2,3,6}; ⌘⇧8 → {1,2,3,6,8}; ⌘⇧7 → {1,2,3,6,7,8}; ⇧9 → {1,2,3,7,8,9}
click 1; ⌘⇧3 → {1,3}; ⇧5 → {1,3,4,5}; ⌘⇧2 → {1,2,3,4,5}
⌘2; ⌘5; ⌘8 → {2,5,8}; ⇧6 → {2,5,6,7,8}; ⇧10 → {2,8,9,10}
click 1; ⇧5; click 3 → (AppKit kept {1..5} until a drag or release settled it; anchor 3); ⇧6 → {3,4,5,6}
programmatic {3,4,5}; ⇧8 → {3..8}  |  ⇧1 → {1,2,3}  |  ⇧4 → {3,4}
click 4; ⌘4 → {}; ⇧7 → {1..7}
click 1; ⇧3; ⌘8 → {1,2,3,8}; ⇧10 → {1,2,3,8,9,10}; ⇧6 → {1,2,3,6,7,8}; ⇧2 → {2..8}
click 1; ⇧4; ⌘2 → {1,3,4}; ⇧6 → {1,3,4,5,6}; ⇧1 → {1,2,3}
click 1; ⇧5; ⌘3; ⇧6 → {1,2,4,5,6}; (select 3 programmatically) → {1..6}; ⇧1 → {1,2,3,4}   ← the anchor moved to the stand-in
```

**States, then one ⇧ Shift click on t = 1 … 12** (`t:{result}`):

```
A  {1..5} a=1        1:{1} 2:{1,2} 3:{1,2,3} 4:{1..4} 5:{1..5} 6:{1..6} 7:{1..7} 8:{1..8} 9:{1..9} 10:{1..10} 11:{1..11} 12:{1..12}
B  {2,5,8} a=8       1:{1..8} 2:{2..8} 3:{2..8} 4:{2,4..8} 5:{2,5..8} 6:{2,5,6,7,8} 7:{2,5,7,8} 8:{2,5,8} 9:{2,5,8,9} 10:{2,5,8,9,10} 11:{2,5,8..11} 12:{2,5,8..12}
B′ B″ (other histories, same state)  identical to B, ⇧ and ⌘⇧ alike
C  {1,2,4,5} a=3 off 1:{1,2,3,4} 2:{2,3,4} 3:{1,2,3,4} 4:{1,2,4} 5:{1,2,4,5} 6:{1,2,4,5,6} 7:{1,2,4..7} 8:{1,2,4..8} … 12:{1,2,4..12}
D  {} a=6 off        t:{1..t}
E  {3,7,8,9} a=9     1:{1..9} 2:{2..9} 3:{3..9} 4:{3..9} 5:{3,5..9} 6:{3,6..9} 7:{3,7,8,9} 8:{3,8,9} 9:{3,9} 10:{3,9,10} 11:{3,9,10,11} 12:{3,9..12}
F  {3,7} a=3         1:{1,2,3,7} 2:{2,3,7} 3:{3,7} 4:{3,4,7} 5:{3,4,5,7} 6:{3..7} 7:{3..7} 8:{3..8} … 12:{3..12}
G  {6,7,8} a=5 off   1:{1..6} 2:{2..6} 3:{3..6} 4:{4,5,6} 5:{5,6} 6:{6} 7:{6,7} 8:{6,7,8} 9:{6..9} … 12:{6..12}
H  {5,6,8} a=7 off   1:{1..8} 2:{2..8} 3:{3..8} 4:{4..8} 5:{5..8} 6:{6,7,8} 7:{5,6,7,8} 8:{5,6,8} 9:{5,6,8,9} … 12:{5,6,8..12}
I  {6..10} a=10      1:{1..10} … 6:{6..10} 7:{7..10} 8:{8,9,10} 9:{9,10} 10:{10} 11:{10,11} 12:{10,11,12}
J  {} a=4 off        t:{1..t}
K  {9} a=4 off       1:{1..9} … 8:{8,9} 9:{9} 10:{9,10} 11:{9,10,11} 12:{9..12}
L  {2} a=9 off       1:{1,2} 2:{2} 3:{2,3} … 12:{2..12}
M  {4,5,6,9,11} a=10 off  1:{1..11} … 6:{6..11} 7:{4,5,6,7..11} 8:{4,5,6,8..11} 9:{4,5,6,9,10,11} 10:{4,5,6,9,10,11} 11:{4,5,6,9,11} 12:{4,5,6,9,11,12}
N  {1,2,3,6,8} a=8   1:{1..8} 2:{2..8} 3:{3..8} 4:{1,2,3,4..8} 5:{1,2,3,5..8} 6:{1,2,3,6,7,8} 7:{1,2,3,6,7,8} 8:{1,2,3,6,8} 9:{1,2,3,6,8,9} … 12:{1,2,3,6,8..12}
P  {2,5} a=9 off     1:{1..5} 2:{2..5} 3:{2..5} 4:{2,4,5} 5:{2,5} 6:{2,5,6} … 12:{2,5..12}          ← stand-in 5: the last selected before
Q  {2,7} a=4 off     1:{1..7} … 7:{2,7} 8:{2,7,8} … 12:{2,7..12}                                    ← stand-in 7: the first after, not the nearest
R  {2,7} a=5 off     identical to Q
T  {3,9} a=6 off     1:{1..9} 2:{2..9} 3:{3..9} 4:{3..9} 5:{3,5..9} 6:{3,6..9} 7:{3,7,8,9} 8:{3,8,9} 9:{3,9} 10:{3,9,10} … 12:{3,9..12}
U  {1,3} a=11 off    1:{1,2,3} 2:{1,2,3} 3:{1,3} 4:{1,3,4} … 12:{1,3..12}                           ← stand-in 3
V  {10,12} a=2 off   1:{1..10,12} 2:{2..10,12} … 10:{10,12} 11:{10,11,12} 12:{10,11,12}             ← stand-in 10
```

**⌘ Command ⇧ Shift click on t**, every state: the selection with t toggled, nothing else moved, and the
anchor at t afterwards (state N, and sequences S7 and S8).
