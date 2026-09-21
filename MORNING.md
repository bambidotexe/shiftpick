# MORNING

## Where it is, and whether it is running

**`/Applications/ShiftPick.app`, version 0.0.1, running now** (installed through the `install-locally`
skill: `sh scripts/install.sh`, which builds the real signed and notarized thing and leaves no `.app` or
`.dmg` under the repository). It has not crashed; there is no crash report for it.

You granted **Accessibility** while I was still working, so there is nothing left for you to click. The app
picked the grant up without a relaunch and its log says so:

```
the Accessibility permission has arrived
watching for clicks
```

The repository is committed locally on `main`, one commit, clean working tree. **Nothing was pushed,
uploaded or published**: there is no remote, no tag, no release.

## What I verified by running it

All of this is the **installed app**, driven with real synthetic clicks, with its selection read back out
of Finder and its own log line confirming it did the work.

- **A range across two groups.** Click a folder, ⇧ Shift click a file five icons further on: 8 of 11 items
  selected, in flow order, crossing a group boundary. `selected 8 of 11 (arranged(rowsFromLeft))`.
- **The range shrinks and reverses from the same anchor.** ⇧ Shift click nearer: 3 items. ⇧ Shift click
  *before* the anchor: the other 3. The anchor never moved.
- **⌘ Command with ⇧ Shift adds**: 3 + a new range of 8 came to 9 distinct files, a union and not a
  replacement.
- **The Desktop, with another app frontmost.** Plain click a Desktop icon from Terminal, bring Terminal
  back, ⇧ Shift click a second one: both selected, `arranged(columnsFromRight)`, **and Finder came
  forward** — the thing the swallowed click owes you.
- **Open panels (the stretch goal).** A real Open panel in icon view: 3 of 6 selected where the panel's own
  ⇧ Shift click selects the first and the third and skips the middle one. Measured both ways.
- **The kill switch round-trips.** Turned off from the menu-bar item, the setting was written; turned back
  on, it was written back. It is on now.
- **The permission, live**: granted while running, picked up with no relaunch; and it survived three
  reinstalls, because the Developer ID signature keeps the same code identity.
- **The whole window**, read back out of the running app: the three pages, every group, every row, the red
  *Refusée* status with its button while the permission was missing, the menu with its five items and its
  status line. In French, which is what this Mac is set to.

Two defects were found this way and fixed:

1. The onboarding window drew three **truncated one-line** sentences (460 × 205). Fixed, re-measured at
   460 × 269 with everything wrapping.
2. Five thousand icons took **47 seconds** to classify, because a group's bounds were recomputed inside a
   sort comparator. Fixed; the same test now runs in 0.06 s.

## What I verified only by compiling and by unit test

`swift build` is clean, **zero warnings**. `swift test` is green: **117 + 13 = 130 tests**, two summary
lines, both passing.

- The whole of the selection maths against synthetic layouts: perfect grid, partial last row, grid with
  holes, free-form scatter, Desktop column fill from the right, right-to-left, grouped sections, mixed
  label heights, one row, one column, anchor equal to target, 5,000 items, stacks, and the three properties
  (total, symmetric, deterministic).
- The anchor rules, including the case the brief does not name (a click inside the selection).
- Every rule of the update, and **the install helper run for real under `/bin/sh`**: it installed a
  stand-in app, rolled one back when the new version did not start, and refused a missing one.
- Both languages of every sentence, with the no-long-dash and key-symbol rules enforced.

## What you have to try by hand

`MANUAL_TESTS.md` is the list. The ones I could not reach:

- **Sort By modes other than the two I used**, and a **hand-placed folder** (Sort By None). The maths is
  unit-tested for both, and `swift run axdump views` will tell you which way it read any window, but I did
  not click in one.
- **Stacks on the Desktop.** I read one through Accessibility and confirmed the test that recognises it (no
  `AXURL`), then put your Desktop back the way it was. I never clicked one.
- **A 2,000-item folder where you scroll between the two clicks.** This is the one real limitation: Finder
  only builds the icons on screen, so if the first file has scrolled away the click goes to Finder
  untouched rather than selecting a range that quietly leaves files out. Both ends on screen is the
  ordinary gesture and works.
- **An inline rename**, a **Save** panel, **several windows**, the **update** and the **uninstall**.

## What needed a fallback, and what I left on your Mac

- **Apple events to Finder were measured and not used.** The brief allows them as a fallback when
  Accessibility only exposes the icons on screen, which it does. But the fallback cannot supply what it
  was expected to: `position of every item` answers `{-1, -1}` for every item of an *arranged* icon view,
  and `name of every item` answers in name order whatever the window's Sort By is. Both measurements are
  in `docs/pitfalls.md` 2. So ShiftPick asks for **no Automation permission at all**, and where
  Accessibility stops, the click goes through.
- **The Bash sandbox could not build, sign or ask the privacy database** (it cannot even answer
  `AXIsProcessTrusted`). Everything that touches the toolchain, the keychain or Finder ran outside it, as
  your three other projects' `.claude/settings.local.json` already arranges; ShiftPick has the same file.
- **Two things I could not put back, sorry.**
  1. Your **home folder's Finder window has *Use Groups* on**, from a menu press I made while reading
     Finder's hierarchy. I could not toggle it back off through Accessibility (`AXPress` on that item
     stopped taking effect). **View › Use Groups** turns it off.
  2. **Two Finder windows titled `claude-501`** are still open; their folders are gone. Just close them.
  Your Desktop's own settings, which I did change to read a stack, were exported first and imported back:
  `defaults read com.apple.finder DesktopViewSettings` is byte for byte what it was.

## Before you publish

Nothing in the repository is a placeholder except the icon. There is **no secret in it and none is needed
at build time**. Three things only you can provide, all named in the `publish-release` skill too:

| What | How |
|---|---|
| A **public** GitHub repository at `bambidotexe/shiftpick`, with `origin` set | `gh repo create bambidotexe/shiftpick --public --source . --remote origin` |
| A **Developer ID Application** certificate for team `85F6AC5QZF` | already in this keychain: the four builds tonight were signed and notarized with it |
| A **notarytool** profile called `wooflab-notary` | already in this keychain |

The signing identity and the notary profile are therefore **done**; only the repository is missing, which
is why every update check says *No release published yet*.

Then, once you have asked for a release:

```sh
make release LEVEL=patch                  # or: sh scripts/publish.sh patch
sh scripts/publish.sh patch --no-install   # to test the update the way a user gets it
```

**I did not run any of it, or any part of it.** I did validate it without executing: every script it
references exists, is executable and passes `sh -n`, and `dmg-settings.py` parses.

The **app icon is a placeholder** — the same three-bar mark the menu-bar item draws, generated by
`scripts/make-icon-preview.swift`. `Resources/ICON-NOTES.md` says what replacing it means.

## Where to start reading

`CLAUDE.md`, then `docs/functional.md`. `CONVENTIONS.md` says what I took from SnappySnap, KoffeeLid and
MySidepulse and where each rule came from; `DECISIONS.md` says what I decided without asking and why.
