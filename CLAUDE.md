# ShiftPick — CLAUDE.md

The operating manual for an agent working in this tree. Read it whole before the first edit.

## What this project is

ShiftPick is a macOS menu-bar accessory that gives **every Finder icon view, the Desktop, and every Open
or Save panel shown as icons, the Shift-click range selection Windows has always had**: click one file,
hold ⇧ Shift, click another, and everything between them is selected. Finder already does this in list,
column and gallery views; in icon view ⇧ Shift only adds the one item under the pointer, and an AppKit file
panel shown as icons has exactly the same gap. ShiftPick closes it and does nothing else.

It listens on one `CGEventTap` for the left mouse button. A click without ⇧ Shift leaves the callback after
one bit test. A click with it is hit-tested through the Accessibility API: if what is under the pointer is
an icon in a Finder icon view, ShiftPick works out the range, sets Finder's selection itself, brings Finder
forward, raises the clicked window, and **swallows the click** so Finder does not apply its own toggle on
top. Anything else at all — another application, a list view, the gap between two icons, a rename in
progress, a question Accessibility will not answer, a budget of 150 ms running out — returns the event
unmodified. **A bug in this app must never be able to break clicking.**

Accessibility is the only permission it needs, and it is not sandboxed, because neither an event tap that
may swallow an event nor control of Finder's selection is a thing a sandbox allows.

Swift, SwiftPM (tools 5.10), macOS 26+, no Xcode project, no third-party dependency. One process, signed
with the Wooflab team's Developer ID and notarized. It looks for a newer release on GitHub at launch and
once a week, announces one with a notification, and installs it on a click. **The check is anonymous, so
the repository has to be public for it to see anything**: a private one reads exactly like no release at
all.

## Read first

| File | What it is |
|---|---|
| `docs/README.md` | The index: which document answers which question, and how to start. |
| `docs/functional.md` | **The authority on behaviour.** Every rule of the click, the range, the anchor and the window, with the numbers. Kept in sync with the code by the workflow below. |
| `docs/architecture.md` | The three targets, the click path end to end, what each layer owns, threading, the update, the build. |
| `docs/macOS.md` | The platform boundary, and **the Accessibility hierarchy of Finder's icon views as it was actually read**, dumps and all. Read it before designing on a platform assumption. |
| `docs/pitfalls.md` | What looks right and is not, with the measurements. The only place that records approaches that failed. |
| `MANUAL_TESTS.md` | What only a person can see. The app target has no automated tests. |
| `CONVENTIONS.md` | What the three reference projects agreed on, with file references. Why this app is built the way it is. |
| `DECISIONS.md` | Every choice made without asking, with its one-line reason. |

## Changing behaviour — the workflow

Every change to what the app does follows these steps, in this order. A change that skips one is not done.

1. **Find the rule.** Read the section of `docs/functional.md` that governs the behaviour. It is the
   authority: what it says is what the app is supposed to do today.
2. **Check for a conflict.** If the request contradicts a rule that is written there — a number, a trigger,
   an order, a "never" — **stop and ask the owner whether the existing rule is overruled, quoting the
   rule.** Do not guess, do not implement both, do not add an exception beside the old rule. A request that
   only adds behaviour no rule covers needs no question, and a purely technical change needs none either.
3. **Change the code**, in the layer that owns it: `ShiftPickCore` for anything decidable from values alone
   (it imports Foundation and CoreGraphics and never reads a clock), `ShiftPickPlatform` for the one call
   that touches Accessibility, the event tap, the network or a file, `ShiftPickApp` for wiring and windows.
   A comment states the present rule, never the history of the change.
4. **Update `docs/functional.md` in the same commit.** Replace the old rule with the new one. Never keep an
   outdated rule, not as a note, not as "it used to be". If the change touches how it is built, a platform
   fact or a trap, update `architecture.md`, `macOS.md` or `pitfalls.md` the same way, and `README.md` if it
   says anything about it.
5. **Verify.** `swift build`, then `swift test` and **count two summary lines** (see Traps). A pure rule
   gets a test in `ShiftPickCoreTests`; an I/O behaviour gets one in `ShiftPickPlatformTests`. Anything only
   a person can see gets a line in `MANUAL_TESTS.md`.
6. **Commit per task**, conventional commits, files staged by path, with the attribution trailers from the
   session's system reminder.

The sync rule in one sentence: **the code and `docs/functional.md` describe the same app at every commit,
and the newer of a request and a written rule wins only after the owner has said so.**

### Where a change usually lands

| To change… | Edit | Then document in |
|---|---|---|
| what counts as a range: the lattice, the flow, the rubber band | `Core/LayoutModel.swift`, `Core/Lattice.swift`, `Core/LayoutItem.swift` — pinned by `RangeSelectionTests`, `LatticeTests` | `functional.md` §3 |
| where a range is measured from | `Core/LayoutModel.derivedAnchor`, `App/ShiftPickEngine` (`anchor`, `notePlainClick`) — `AnchorTests` | `functional.md` §2 |
| which clicks are looked at at all, and what is swallowed | `Platform/MouseTap.swift` | `functional.md` §1, `macOS.md` *The event tap* |
| how Finder is read and written | `Platform/FinderAX.swift`, `Platform/AX.swift` | **`macOS.md` first**, then `functional.md` §4 |
| what one ⇧ Shift click does, end to end | `App/ShiftPickEngine.shiftClick` | `functional.md` §1–2, `architecture.md` *The click path* |
| a timing, a budget, a threshold | `Core/Constants.swift`, with its measurement in the comment | the section that states it |
| a user setting | **Invoke the `building-settings-pages` skill first.** `Core/Settings.swift` + a row on its page + `SettingsTests` | `functional.md` §5 |
| the Settings window's pages, look or copy | **Invoke the `building-settings-pages` skill first**: it holds every rule of the window's structure, numbers and wording. `App/SettingsKit.swift` (the kit and `SettingsMetrics`), `App/SettingsView.swift` (`SettingsPageID`, `SystemStatus`), `App/SettingsWindow.swift` (the toolbar, the height that follows the page), `App/Settings…Page.swift`. **The words are not in the page files**: they are `Core/Strings<Page>Page.swift` | `functional.md` §5 |
| the menu-bar item or its menu | `App/MenuBarController.swift`, `Core/StringsMenu.swift` | `functional.md` §6 |
| onboarding, or what happens when the permission moves | `App/OnboardingWindow.swift`, `App/AppDelegate` (`watchTheGrant`, `grantChanged`), `Platform/Permissions.swift` | `functional.md` §7, `macOS.md` *The permission* |
| updates: the check, its schedule, the notification | `Core/UpdateCheck.swift`, `UpdateSchedule.swift`, `UpdatePanel.swift`, the `update…` numbers in `Core/Constants.swift`; `Platform/UpdateChecker.swift`; `App/UpdateController.swift` (the one owner), `UpdateNotifier.swift` | `functional.md` §8 |
| updates: the window, the fetch, making it ready, Install and Relaunch | `Core/UpdateSession.swift`, `StagedUpdateCheck.swift`, `UpdateInstallScript.swift` (the helper's text, run under a real `/bin/sh` by `UpdateInstallScriptTests`); `Platform/UpdateStager.swift`, `CodeSignature.swift`, `UpdateInstaller.swift`, `DetachedProcess.swift`; `App/UpdateWindow.swift` | the same, plus `pitfalls.md`. **Read those entries before touching the order of an install** |
| the uninstall | `Core/UninstallPlan.swift` (the helper's text and why it waits for the pid), `Platform/Uninstall.swift` (the order), the Uninstall group of `App/SettingsGeneralPage.swift`, `Core/StringsGeneralPage.swift` | `functional.md` §9 |
| **any sentence the user reads**, in either language | `Core/Strings*.swift` (one table per surface; a string is one accessor switching over `Language`, so the two languages are added together or not at all), `Core/Localization.swift` — `LocalizationTests`, which also reads the tables off disk | `functional.md` §10 |
| the app's name, its identifier or its repository | **`scripts/signing.env` only.** `make-app.sh` writes all three into the built `Info.plist` and `Core/AppIdentity.swift` reads them back | `CONVENTIONS.md` §7 |
| the icon | `Resources/AppIcon.icon` (re-export from Icon Composer, never hand-edit `icon.json`), `Resources/previews/ShiftPick-preview-1024.png`, `Resources/ICON-NOTES.md` | `architecture.md` *Build and signing* |
| the signing identity, the build or the release | `scripts/signing.env`, `scripts/make-app.sh`, `Resources/ShiftPick.entitlements`, `scripts/make-dmg.sh`, `scripts/release.sh` | `architecture.md` *Build and signing*, `macOS.md` |

## Commands

```bash
# ---- the two actions. A build of this app reaches a Mac by one of these and by nothing else. ----
make install     # skill: install-locally. The production build → /Applications; leaves no .app or .dmg behind
make release     # skill: publish-release. The same, plus tag, push, GitHub release, and the tree moves on
# -------------------------------------------------------------------------------------------------
```

- `swift build` — the three code targets and the probe. **This is the truth**; editor diagnostics are
  frequently stale.
- `swift test` — two bundles, and **one summary line each: count two.** `ShiftPickCoreTests` (117) runs in
  under three seconds; `ShiftPickPlatformTests` (13) spawns real subprocesses and takes a moment longer.
  `swift test --filter <SuiteName>` runs one suite.
- `swift run axdump <command>` — the Accessibility probe (`Tools/axdump`, never shipped). `trust`, `views`,
  `at <x> <y>`, `range <x> <y>`, `tree [depth]`. **A command-line tool inherits the Accessibility grant of
  the terminal that starts it**, which is the only way to read Finder's hierarchy before the app itself is
  allowed to. `axdump range` works a ⇧ Shift click out exactly as the app does and prints it instead of
  applying it, which is how a doubt about a layout is settled.
- `make install` (`scripts/install.sh`) — **one of the two ways a build of this app reaches a Mac.** It
  builds the real thing — Release, Developer ID, Hardened Runtime, notarized, stapled, wrapped in the disk
  image — takes the bundle out of that image into `/Applications`, and opens it. It leaves **no `.app` and
  no `.dmg` anywhere under the repository**, on any exit path.
- `make release` (`scripts/publish.sh`) — **the other way.** Everything `install` does, plus the tag, the
  push, the GitHub release carrying the image, and the version raised again afterwards. Refuses on a dirty
  tree, an existing tag or a `HEAD` that differs from `origin`, all before it builds anything. Run it only
  when the owner has asked for a release. `sh scripts/publish.sh --no-install` publishes and leaves
  `/Applications` alone, which is how the update a user gets is tested.
- **There is no third way.** A bundle left in `build/` is a complete application that Spotlight offers;
  launching it by accident gives a second ShiftPick with a second event tap on the same clicks.
  `scripts/no-leftovers.sh` holds that rule.
- `scripts/version.sh` — the version rule, and the only thing that writes the version: **the tree is always
  one patch ahead of the newest GitHub release.** No releases yet → the tree is `0.0.1`.
- `/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug` — the app's log
  (`log` alone is a zsh builtin, hence the full path). Categories: `app`, `click`, `update`. **`click` says
  nothing on the ordinary path**: a line there is always about a ⇧ Shift click, and at `debug` it says why
  one was let through.
- `SHIFTPICK_UPDATE_FEED=file:///…/latest.json` in the installed app's environment replaces GitHub's reply
  with a stand-in, which is how the whole update is walked offline (`MANUAL_TESTS.md` §10).

## Architecture

Three code targets, dependencies pointing one way: Core ← Platform ← App. Full version in
`docs/architecture.md`.

- **`Sources/ShiftPickCore`** — pure rules, **Foundation and CoreGraphics only** (`PurityTests` fails the
  build otherwise), and it never reads a clock. `LayoutItem` + `Lattice` + **`LayoutModel`** (the whole of
  the selection maths: classify a set of icon frames, order them, and answer with a range) · `Settings` ·
  `Constants` (`K`, every number with its measurement) · `AppIdentity` + `Paths` · `QuietLaunch` ·
  `UninstallPlan` · the update's rules (`UpdateCheck`, `UpdateSchedule`, `UpdatePanel`, `UpdateSession`,
  `StagedUpdateCheck`, `UpdateInstallScript`) · `Localization` (`Language`, `Loc`) + `Strings*` (every
  user-facing string, English and French side by side, one table per surface).
- **`Sources/ShiftPickPlatform`** — the only code that talks to the system. **`MouseTap`** (the one event
  tap, and the only thing that may swallow a click) · **`FinderAX`** (the only code that knows the shape of
  Finder's icon views: find the view under a point, read its items, read and set its selection) · `AX` (the
  C Accessibility API, one round trip per call) · `Permissions` · `LoginItem` · `SettingsStore` · `Log` ·
  the update's I/O (`UpdateChecker` + `UpdateDownload`, the only network code; `UpdateStager`,
  `CodeSignature`, `UpdateInstaller`, `DetachedProcess`) · `Uninstall`.
- **`Sources/ShiftPickApp`** — `AppDelegate` wires everything. **`ShiftPickEngine`** owns the tap and the
  anchor and is where one ⇧ Shift click is decided. `MenuBarController` · `OnboardingWindow` ·
  `UpdateController` (the update's one owner) + `UpdateNotifier` + `UpdateWindow` · the settings window
  (`SettingsKit` the kit, `SettingsWindow` the toolbar window whose height follows the page, three
  `Settings…Page`, `SettingsView` with `SettingsPageID` and `SystemStatus`).
- **`Tools/axdump`** — the Accessibility probe. Ships with nothing.

The app target has no automated tests. Its verification is `MANUAL_TESTS.md`, `swift run axdump range`, and
the log.

## Rules

- **A build of this app reaches a Mac in exactly two ways, and there is no third.** See Commands.
- **A debug or ad-hoc build is never installed, and never made without asking the owner first.** It exists
  only to read something a release build will not show. `scripts/make-app.sh` refuses one without
  `DEBUG_OK=1`; that guard is there to make the decision deliberate, not to be worked around. **An ad-hoc
  signature gives the app a new code identity, so the owner loses the Accessibility grant and has to give
  it again.**
- **The version is not chosen.** `scripts/version.sh` holds the rule; publishing is the only thing that
  moves it.
- **`docs/functional.md` is kept in sync with every behaviour change, in the same commit, and never carries
  an outdated rule.** A rule the owner has overruled is replaced, not annotated.
- **Comments and documents state the present.** A comment records a rule, an invariant, a fact the code
  depends on, or the measurement behind a derived number. No dates, versions, attributions or accounts of
  what the code replaced. History belongs in git and, for traps only, in `docs/pitfalls.md`.
- **Fail safe, always.** Every path through the click returns the event unmodified unless the new selection
  has already been set. Adding a path that can swallow a click without having selected anything is a defect
  even if it never fires.
- **Nothing on the click path may be slow.** It runs inside the event tap's callback, which holds up every
  click on the Mac while it runs. Every Accessibility element it touches gets `K.axTimeout`; the whole path
  is bounded by `K.clickBudget`; and an ordinary click never reaches Accessibility at all.
- **Never assume Finder's hierarchy.** It is not documented and it is not stable. `docs/macOS.md` holds
  what was read, `swift run axdump` is how it is read again, and `FinderAX` is the only file that may know
  it.
- **A view that is not Finder's is refused unless its window says it is a file panel.** The process check
  is what keeps ShiftPick out of everybody else's controls; `open-panel` and `save-panel` are the only two
  identifiers that get past it, and they are AppKit's own and not translated.
- **Accessibility is the only permission the app needs, and the only one it asks for.** Notifications are
  asked for the first time an automatic check has a release to announce, and for nothing else. **No Apple
  events**: `docs/pitfalls.md` says what was measured and why.
- **No user-facing string is written at its point of use.** It goes in a `Core/Strings*.swift` table, where
  one accessor answers for every language, so a string cannot exist in English alone.
- **Silence is a defect.** Anything that declines to act logs why, once, with the numbers.
- `ShiftPickCore` imports Foundation and CoreGraphics only, and never reads a clock: `now` is passed in.
- Commit per task, conventional commits, attribution trailers from the session's system reminder.
- **Stage by path. Never `git add -A`.**

## Traps

`docs/pitfalls.md` is the full list, with the measurements. The five that cost the most:

1. **Finder only builds the icons that are on screen.** A folder of 2,500 files answers with 24 to 30. A
   range is therefore only ever as complete as what is visible, and ShiftPick lets the click through rather
   than making a quietly smaller selection.
2. **Apple events are not the way out of that**, although they look like it: `position of every item`
   answers `{-1, -1}` for an arranged icon view, and `name of every item` answers in name order whatever
   the window's Sort By is. Measured; do not try it again without reading the entry.
3. **`swift test` prints one summary line per bundle — count two.** A crashed bundle prints none, so a
   crash reads as a pass if you grep for one green line.
4. **A Finder window element's `AXRole` can read as `AXApplication`** for a second after Finder relaunches.
   Walk **up** from the hit test, never down from the application, and never index into children.
5. **`set -e` reaches inside command substitutions.** `version_published` has to end its `gh` call with
   `|| true`, or a repository that does not exist yet takes the function's own fallback with it and every
   script that sources it exits 1 with no output at all.

## Status

`swift build` is clean and `swift test` is green (117 + 13) at this commit. The app target has no automated
tests; `MANUAL_TESTS.md` is its verification.

Known limitations, in plain words:

- **A range is bounded by what Finder has built.** Both ends have to be on screen. Click a file, scroll
  three screens, ⇧ Shift click another, and the click goes to Finder untouched, because the first file is
  no longer something Accessibility can name. Everything between two icons that are both visible is
  complete, which is the ordinary gesture.
- **The Desktop's flow is inferred, not asked for.** A Desktop sorted by name was measured filling columns
  from the right; a Desktop nobody sorted is classified hand-placed and gets the rubber band. Both are
  right for what they are, but neither is something Finder states.
- **The update has never been seen end to end in this app.** Its rules are unit-tested and the install
  helper has installed and rolled back a stand-in app for real; the notification, the update window and
  ShiftPick installing over itself are `MANUAL_TESTS.md` §10. Nothing is published, so every check answers
  **No release published yet** until the repository is public and carries a release.
- **The uninstall has not been walked.** Its two halves are tested apart (`UninstallPlanTests`, and the
  helper's quoting), and the order is `snappy-snap`'s, which has been walked.
