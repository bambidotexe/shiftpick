# ShiftPick — pitfalls

What looks right on macOS and is not, with the measurement that settled it. **This is the only place that
records approaches that failed.** Nothing here is a rule; the rules are in `functional.md`.

---

## 1. Finder only builds the icons that are on screen

**Measured.** A folder of 2,500 files, opened in icon view on a 1512 × 982 display:

```
== iconview window=finder-big frame=540,258 705x48390
   items=24 sections=1
```

Twenty-four items, and the container's own frame says the content is 48,390 points tall. Scrolling to the
middle re-reads as 30 items with a different range of `y`: Finder builds the visible band plus a little
beyond it and nothing else. There is no attribute, and no option, that makes the rest appear;
`AXEnhancedUserInterface` cannot even be set on Finder (`-25208`).

**What follows.** A range is only ever as complete as what is on screen. Both ends have to be visible, and
that is a real guarantee rather than a hope: the in-between icons of an arranged layout lie geometrically
between the two ends, and the rubber band of a hand-placed one is bounded by their two frames, so an
in-between icon cannot be off screen when both ends are on it.

When an end is **not** on screen, its stored anchor reads as gone and nothing usable is selected, so the
click goes through. **That is deliberate.** A range that quietly left files out would be worse than no
range at all: nobody would notice until they had moved or deleted the wrong set.

## 2. Apple events are not the way around that, although they look like it

Two measurements, both on the 2,500-item folder above, with Automation to Finder already granted:

```applescript
tell application "Finder" to get position of every item of (target of Finder window 1)
-- {-1, -1}, {-1, -1}, {-1, -1}, … for all 2,500
```

Finder reports a position for an item in an icon view **only when that view is not arranged**. Every
sorted view, which is the default and the common case, answers `{-1, -1}` for everything.

```applescript
tell application "Finder" to get name of every item of (target of Finder window 1)
-- alphabetical, with the window sorted by modification date
```

The enumeration order is the folder's, not the view's. Compared against the same window's Accessibility
order, which *is* the view's (`file-05, file-10, file-01, …` for a window sorted by modification date), the
two do not agree.

So an Apple-events fallback could supply **neither** the geometry of an arranged view nor its order, and
reconstructing the order would mean reimplementing Finder's collation, its folders-on-top rule and its
tie-breaks, blind. It would also cost a second permission for every user, to cover a case that only
arises after scrolling. **It was measured and not built.** Do not build it without re-measuring both
lines above.

## 3. `set -e` reaches inside command substitutions

`scripts/install.sh` ran `set -eu`, sourced `scripts/version.sh`, and exited **1 with no output at all**.

The cause: `version_published` assigns `tag="$(gh release list …)"`. A command substitution is a subshell
that inherits `set -e`, so a `gh` that exits non-zero — no repository yet, not logged in, no network — took
the function's own `echo "0.0.0"` fallback with it and handed the caller an empty version. The trace ended
at `+ VERSION=` / `+ exit 1`.

The fix is one `|| true` on the `gh` call. The same shape is in the reference projects and does not fire
there only because their repositories exist.

## 4. `swift test` prints one summary line per bundle

```
Test Suite 'ShiftPickPlatformTests.xctest' passed …  Executed 13 tests
Test Suite 'ShiftPickCoreTests.xctest' passed …      Executed 117 tests
```

**Count two.** A bundle that crashes prints none, so grepping for one green line reads a crash as a pass.

## 5. Recomputing a group's bounds inside a comparator

The first version of `LayoutModel` worked a section's first row and row span out inside `rank`, which is
called from a sort comparator. Five thousand icons took **47.2 seconds**. Moving those two numbers out to
where the section is described, once, took the same test to **0.06 seconds**. The complexity claim in
`functional.md` §3.7 is not decoration.

## 6. A Finder window's `AXRole` can read as `AXApplication`

For a second or two after Finder relaunches, its children answer `AXApplication` for elements that are
plainly windows, while their own children are correct. Walking **up** from a hit test is unaffected, which
is what `FinderAX.hit` does. Walking **down** from the application and trusting a role is not.

Never index into Finder's children either: the order of the application's children is not stable, and the
Desktop has been seen at index 2 and at index 3 of the same process.

## 7. An ad-hoc signature loses the Accessibility grant

The grant is per code identity. An ad-hoc build gets a new one every time it is built, so the owner would
have to grant Accessibility again after every build, and would end up with a privacy list full of dead
entries. `scripts/make-app.sh` refuses an ad-hoc build without `DEBUG_OK=1` for that reason, and an ad-hoc
build is never installed.

## 8. A sandboxed shell cannot answer `AXIsProcessTrusted()`

Inside the session's Bash sandbox the probe answered `false`; the same binary run outside it answered
`true`. Anything that asks the privacy database, lists processes or reads `~/Library` has to run outside
the sandbox, which is why all three reference projects ship `.claude/settings.local.json` with the sandbox
off.

## 9. SwiftUI text in a hosting controller does not wrap on its own

The onboarding window came out **460 × 205** with three one-line texts in it, two of them truncated. A
hosting controller sizing itself is free to propose a width no window has, and a `Text` with no
`fixedSize(horizontal: false, vertical: true)` will take it. With the `fixedSize` and an explicit content
width the same window is 460 × 269 and every sentence wraps. The settings kit already does this on every
row, which is why only the one hand-written window was wrong.

## 10. A file panel's collection list has no `AXWindow`

Finder's `AXList/AXCollectionList` answers `AXWindow` with the window it is in. **An Open or Save panel's
does not**: it answers `kAXErrorNoValue`. Since the window's `AXIdentifier` is the only thing that tells a
panel from any other application's collection view, that silently refused every panel click until the
window was found by walking the chain the hit test had already built instead.

---

## Open issues

- **The Desktop's fill direction is inferred, not asked for.** A Desktop sorted by name was measured
  filling a column at x 1410 from y 42 downwards and then a column at x 1286, which is to its left, and the
  code falls back to that. Finder states nothing about it, so a Desktop arranged some way nobody has seen
  would be classified from its geometry alone.
- **Groups have been read with three sections and with one.** A view with many small groups, where a
  section holds fewer icons than the view has columns, is handled by the same rule but has not been seen.
- **The update has never been walked end to end in this app.** Its rules are unit-tested and the install
  helper has installed and rolled back a stand-in app under a real `/bin/sh`; the notification, the window
  and ShiftPick installing over itself are `MANUAL_TESTS.md` §10.
- **The uninstall has not been walked.** Its two halves are tested apart, and the order is the one
  `snappy-snap` has walked.
- **Open and Save panels are covered, and only lightly walked.** A panel's icon view was read, its
  selection was set through Accessibility, and its own ⇧ Shift click was measured toggling one item; the
  live gesture in a panel is `MANUAL_TESTS.md` §5. A panel that allows only one file is left alone by the
  panel itself, not by ShiftPick.
