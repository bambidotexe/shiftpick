# ShiftPick — CLAUDE.md

The operating manual for an agent working in this tree. Read it whole before the first edit.

## What this project is

ShiftPick is a macOS menu-bar accessory that gives **every Finder icon view, the Desktop, and every Open
or Save panel shown as icons, the Shift-click range selection Windows has always had**: click one file,
hold ⇧ Shift, click another, and everything between them is selected. Finder already does this in list,
column and gallery views; in icon view ⇧ Shift only adds the one item under the pointer, and an AppKit file
panel shown as icons has exactly the same gap. ShiftPick closes it and does nothing else.

It holds two event taps, and they are not alike. A **listening** one hears ⇧ Shift go down and come up, and
a listening tap can hold nothing up whatever happens to the app. The one that **can swallow a click** is
enabled only while ⇧ Shift is held: with no finger on the key, no click on the Mac passes through ShiftPick
at all. A ⇧ Shift click is handed to a worker and hit-tested through the Accessibility API: if what is under
the pointer is an icon in a Finder icon view, ShiftPick works out the range, sets Finder's selection itself,
**swallows the click** so Finder does not apply its own toggle on top, brings Finder forward and raises the
clicked window. Anything else at all — another application, a list view, the gap between two icons, a rename
in progress, a question Accessibility will not answer, a budget of 150 ms running out — returns the event
unmodified. **A bug in this app must never be able to break clicking**, and that sentence is not a hope:
`docs/architecture.md` *The safety model* is how it is kept, and `docs/pitfalls.md` 13 is the day it was not.

Accessibility is the only permission it needs, and it is not sandboxed, because neither an event tap that
may swallow an event nor control of Finder's selection is a thing a sandbox allows.

Swift, SwiftPM (tools 5.10), macOS 26+, no Xcode project, no third-party dependency. One process, signed
with the Wooflab team's Developer ID and notarized. It looks for a newer release on GitHub at launch and
once a week, announces one with a notification, and installs it on a click. **The check is anonymous, so
the repository has to be public for it to see anything**: a private one reads exactly like no release at
all.

## The safety nets come first

**Invoke the `shiftpick-safety-nets` skill before touching** the taps, when a tap is armed, enabled or
created, the click path or its budget, how the Accessibility grant is read, asked for or lost, sleep and the
lock screen, a second copy, the quit, the uninstall, the update's install, anything that waits on another
process or thread, a number in `Core/Constants.swift`, the build scripts, or **any feature that listens to,
swallows, delays or posts input events**. It lists every net, where it lives and what pins it.

- **The guarantees are `docs/functional.md` §0.** A request that would loosen one is a conflict (step 2
  below), and **no net is removed, loosened or worked around without the owner saying so, in words, for that
  net**: not for a moment, not behind a flag, not because a test was in the way.
- **`SafetyNetTests` pins each net in the code no test can run**, and `TapLifecycleTests`,
  `TapLifecycleInvariantTests`, `DeadlineGateTests` and `TapThreadTests` pin the rest. A check that fails
  because code moved is moved with the code, keeping what it asserts; one that fails because a net is gone
  means the net goes back.
- **The build scripts enforce them** (`scripts/safety-gates.sh`): nothing is built from failing tests, an
  install fails when the launch it reads back from the log is not sound, and a release refuses while the
  safety layer differs from the last one until the owner says `DRILL=walked` or `DRILL=waived`.
- **Never take the grant away, run `tccutil`, or create an event tap yourself**, from a shell, a script or a
  test. The drill (`docs/manual-test-checklist.md` §9) is the owner's, behind `sh scripts/drill.sh`.

## The family, and the shared documents

This app is one of the macOS apps under `~/Projects` that share one shape; the `macos-map` skill lists
them and routes a task to the right skill. **`docs/shared/` is a synced copy of
`~/Projects/macos-app-template/docs/shared/`, and it is never edited here**: a change goes in the template
and `sh ~/Projects/macos-app-template/scripts/sync-shared-docs.sh` replicates it to every app. A trap, a
convention or a platform fact that applies to more than this app goes there, not in this app's own
documents. `docs/shared/workflow.md` is the change workflow every app of the family follows and
`docs/shared/pitfalls.md` the traps they all share; the sections below are this app's own statement of the
workflow, with its own file names, and this app's own traps.

## Read first

| File | What it is |
|---|---|
| `docs/README.md` | The index: which document answers which question, and how to start. |
| the `shiftpick-safety-nets` skill (`.claude/skills/`) | **Every safety net**, where it lives, what pins it, the thoughts that mean stop, and how a change near one is verified. |
| `docs/functional.md` | **The authority on behaviour.** §0 is the guarantees every other rule is held to; then every rule of the click, the range, the anchor and the window, with the numbers. Kept in sync with the code by the workflow below. |
| `docs/architecture.md` | The three targets, the click path end to end, what each layer owns, threading, the update, the build. |
| `docs/macOS.md` | The platform boundary, and **the Accessibility hierarchy of Finder's icon views as it was actually read**, dumps and all. Read it before designing on a platform assumption. |
| `docs/pitfalls.md` | What looks right and is not, with the measurements. The only place that records approaches that failed. |
| `docs/manual-test-checklist.md` | What only a person can see. The app target has no automated tests. |
| `docs/shared/conventions.md` | How every app of the family is built, and where this one differs (its last section). |
| `DECISIONS.md` | Every choice made without asking, with its one-line reason. |

## Changing behaviour — the workflow

Every change to what the app does follows these steps, in this order. A change that skips one is not done.

1. **Find the rule.** Read the section of `docs/functional.md` that governs the behaviour. It is the
   authority: what it says is what the app is supposed to do today.
2. **Check for a conflict.** If the request contradicts a rule that is written there — a number, a trigger,
   an order, a "never" — **stop and ask the owner whether the existing rule is overruled, quoting the
   rule.** Do not guess, do not implement both, do not add an exception beside the old rule. A request that
   only adds behaviour no rule covers needs no question, and a purely technical change needs none either.
   **A change that would loosen a guarantee of §0 is always a conflict**, however technical it looks.
3. **Change the code**, in the layer that owns it: `ShiftPickCore` for anything decidable from values alone
   (it imports Foundation and CoreGraphics and never reads a clock), `ShiftPickPlatform` for the one call
   that touches Accessibility, the event tap, the network or a file, `ShiftPickApp` for wiring and windows.
   A comment states the present rule, never the history of the change. **Anywhere near a net, the
   `shiftpick-safety-nets` skill first**; a new net gets its check in `SafetyNetTests`, proven to fail
   against a copy of the code with the net removed.
4. **Update `docs/functional.md` in the same commit.** Replace the old rule with the new one. Never keep an
   outdated rule, not as a note, not as "it used to be". If the change touches how it is built, a platform
   fact or a trap, update `architecture.md`, `macOS.md` or `pitfalls.md` the same way, and `README.md` if it
   says anything about it.
5. **Verify.** `swift build`, then `swift test` and **count two summary lines** (see Traps), with
   `SafetyNetTests` among the green. A pure rule gets a test in `ShiftPickCoreTests`; an I/O behaviour gets
   one in `ShiftPickPlatformTests`. Anything only a person can see gets a line in
   `docs/manual-test-checklist.md`. **A change to a file of `SAFETY_FILES` (`scripts/safety-gates.sh`) owes
   §9 of that checklist, walked by the owner on an installed build, before the next release**: say so when
   you hand the change over.
6. **Commit per task**, conventional commits, files staged by path, with the attribution trailers from the
   session's system reminder.

The sync rule in one sentence: **the code and `docs/functional.md` describe the same app at every commit,
and the newer of a request and a written rule wins only after the owner has said so.**

### Where a change usually lands

| To change… | Edit | Then document in |
|---|---|---|
| what counts as a range: the lattice, the flow, the clusters and their grids, the rubber band | `Core/LayoutModel.swift`, `Core/Lattice.swift`, `Core/LayoutItem.swift`, `Core/Clusters.swift`, `Core/Grid.swift`, `Core/LayoutConstants.swift` — pinned by `RangeSelectionTests`, `LatticeTests`, `ClustersTests`, `GridTests` | `functional.md` §3 |
| what a ⇧ Shift click leaves selected: the runs it replaces, the band it adds | `Core/ShiftClick.resolve`, `Core/LayoutModel.shiftClick` — `ShiftClickTests`, `RangeSelectionTests`. It is AppKit's own rule, measured: `macOS.md` *The selection model* is the data, and a change to it needs a new measurement | `functional.md` §2.2 |
| where a range is measured from | `Core/LayoutModel.effectiveAnchor` and `firstItem`, `Core/ShiftClick.standIn`, `App/ShiftClickResolver` (`anchor`, `notePlainClick`) — `StandInTests`. **`ShiftClickResolver` is a file of the safety layer**: invoke `shiftpick-safety-nets` first, and a change to it owes §9 of the checklist before the next release | `functional.md` §2.1 |
| **when the click tap may be enabled**: arming, a tap macOS took away, the breaker, the grant going or coming, sleep and the lock screen | **Invoke `shiftpick-safety-nets` and read `architecture.md` *The safety model* first.** `Core/TapLifecycle.swift`, and nowhere else: a new way for the tap's state to move is a new `Event`, its scenario in `TapLifecycleTests`, and a line in `TapLifecycleInvariantTests`' generator | `functional.md` §0, §1 and §7 |
| the taps themselves, their thread, what is swallowed, the click's budget | **Invoke `shiftpick-safety-nets` first.** `Platform/ClickGuard.swift` (it executes `TapLifecycle`'s effects and decides nothing), `TapThread.swift`, `DeadlineGate.swift` — `DeadlineGateTests`, `TapThreadTests`, `SafetyNetTests` | `functional.md` §0, §1 and §2, `macOS.md` *The event taps* |
| **a feature that listens to, swallows, delays or posts input** | **Invoke `shiftpick-safety-nets` first, and design it with the owner.** Listening goes through the sentinel and swallowing through the click tap, both under `TapLifecycle`; never a tap, an `NSEvent` global monitor or a `CGEvent.post` of its own | `functional.md` §0 and §1 |
| how the grant is read, asked about live, or lost | **Invoke `shiftpick-safety-nets` first.** `Platform/Permissions.swift` (`liveVerdict`, `verdict(for:)`), `Platform/AX.swift` (`refusalCount`) — `TrustVerdictTests` | `macOS.md` *The permission*, `functional.md` §7 |
| how Finder is read and written | `Platform/FinderAX.swift`, `Platform/AX.swift`. **`AX.swift` is a file of the safety layer**: every call it makes carries `K.axTimeout` and is a witness to the grant through `refusalCount`, so invoke `shiftpick-safety-nets` before touching it | **`macOS.md` first**, then `functional.md` §4 |
| what one ⇧ Shift click does, end to end | **Invoke `shiftpick-safety-nets` first.** `App/ShiftClickResolver.shiftClick`, which runs on the worker and answers through its `ClickTicket`: ⌘ Command with ⇧ Shift passes, `FinderAX.selection` is read once, `LayoutModel.shiftClick` answers, and the anchor becomes what the range was measured from. The one line that swallows and its order behind `commit()` and `FinderAX.select` are pinned by `SafetyNetTests`, and the file is in the safety layer | `functional.md` §1–2, `architecture.md` *The click path* |
| a timing, a budget, a threshold | **Invoke `shiftpick-safety-nets` first.** `Core/Constants.swift`, with its measurement in the comment. **The order of the safety numbers is pinned** (`SafetyNetTests.testTheSafetyNumbersKeepTheirOrder`), and a value that moves them is the owner's call. The inferred grids' tolerances are **not** in that file: they are `Core/LayoutConstants.swift`, out of the safety layer as `HealthConstants.swift` is | the section that states it |
| a user setting | **Invoke the `macos-building-settings-pages` skill first.** `Core/Settings.swift` + a row on its page + `SettingsTests`. **ShiftPick has no setting about what it does**, and the owner's word comes before adding one | `functional.md` §5 |
| the Settings window's pages, look or copy | **Invoke the `macos-building-settings-pages` skill first**: it holds every rule of the window's structure, numbers and wording. `App/SettingsKit.swift` (the kit and `SettingsMetrics`), `App/SettingsView.swift` (`SettingsPageID`, `SystemStatus`), `App/SettingsWindow.swift` (the toolbar, the height that follows the page), `App/Settings…Page.swift`. Three nets live in these pages and `SafetyNetTests` pins all three: the System and Health pages' permission rows show the grant through `TapLifecycle.Status.showsGrant`, the Uninstall group of the General page destroys the taps before anything else, and the System page's *Start Listening Again* button reaches the breaker only through `ShiftPickEngine.tryAgain`. **The words are not in the page files**: they are `Core/Strings<Page>Page.swift` | `functional.md` §5 |
| the Health page: a row, its colour, its sentence, a reading | **Invoke the `macos-building-settings-pages` skill first** (*The Health page*). The page is two tables and nothing else: the checks (`HealthReport.checks(for:)`, green, orange or red, never a preference) and the readings (`readings(for:)`, blue), built from plain facts in `Core/HealthReport.swift`, coloured by `Core/HealthRules.swift` (which also colours the System page's permission row), and held under `HealthLimits` by `HealthTests`; the words are `Core/StringsHealthPage.swift`. The page's own readings are `App/HealthCheck.swift`, read when the page is shown and on Check Again, never on a timer, from `Platform/CrashReports`, `ProcessStats`, `FinderProcess`; the view is `App/SettingsHealthPage.swift`. **A reading comes from what the engine already publishes on the main actor, or from a read that cannot block**: never an Accessibility call, never the taps' thread, never a request API. A reading that needs a file of `SAFETY_FILES` (the last ⇧ Shift click, the breaker's trips) is a change to the safety layer: `shiftpick-safety-nets` first, and the drill before the next release | `functional.md` §5 |
| the menu-bar item or its menu | `App/MenuBarController.swift`, `Core/StringsMenu.swift`. Its status line shows the grant through `TapLifecycle.Status.showsGrant`, never the cached answer alone, which `SafetyNetTests` pins | `functional.md` §6 |
| onboarding, or what happens when the permission moves | **Invoke the `macos-building-onboarding` skill first**: it holds every rule of the wizard, who is in front, and what a grant button may do. `App/OnboardingWindow.swift` (the controller, the pages, the row, `OnboardingMetrics`), `App/GrantCatalogue.swift` (what a grant is, the two lists), `App/AppDelegate` (`showOnboarding`, `watchTheGrant`, `grantChanged`), `Platform/Permissions.swift`. **`AppDelegate` and `Permissions.swift` are files of the safety layer**: invoke `shiftpick-safety-nets` as well, and a change to either owes §9 of the checklist before the next release. **The words are not in the page files**: they are `Core/StringsOnboarding.swift` | `functional.md` §7, `macOS.md` *The permission* |
| updates: the check, its schedule, the notification | `Core/UpdateCheck.swift`, `UpdateSchedule.swift`, `UpdatePanel.swift`, the `update…` numbers in `Core/Constants.swift`; `Platform/UpdateChecker.swift`; `App/UpdateController.swift` (the one owner), `UpdateNotifier.swift` | `functional.md` §8 |
| updates: the window, the fetch, making it ready, Install and Relaunch | `Core/UpdateSession.swift`, `StagedUpdateCheck.swift`, `UpdateInstallScript.swift` (the helper's text, run under a real `/bin/sh` by `UpdateInstallScriptTests`); `Platform/UpdateStager.swift`, `CodeSignature.swift`, `UpdateInstaller.swift`, `DetachedProcess.swift`; `App/UpdateWindow.swift` | the same, plus `pitfalls.md`. **Read those entries before touching the order of an install** |
| the uninstall | **Invoke `shiftpick-safety-nets` first.** `Core/UninstallPlan.swift` (the helper's text, why it waits for the pid, **and what it refuses to be pointed at**), `Platform/Uninstall.swift` (the order, every step within `K.uninstallStepWait`, off the main thread), the Uninstall group of `App/SettingsGeneralPage.swift` (**the taps go first**), `Core/StringsGeneralPage.swift` | `functional.md` §9 |
| anything that deletes, renames or runs a shell after the app has quit | `Core/PathRules.swift` holds the questions every such path is asked first; `UninstallPlan.helperScript` answers nil and `UpdateInstallPlan.isSafe` false when one fails. **A new helper, or a new path in an old one, goes through them**, with its refusals in `UninstallPlanTests` or `UpdateInstallPlanTests` | `functional.md` §8 and §9 |
| **any sentence the user reads**, in either language | `Core/Strings*.swift` (one table per surface; a string is one accessor switching over `Language`, so the two languages are added together or not at all), `Core/Localization.swift` — `LocalizationTests`, which also reads the tables off disk | `functional.md` §10 |
| the app's name, its identifier or its repository | **`scripts/signing.env` only.** `make-app.sh` writes all three into the built `Info.plist` and `Core/AppIdentity.swift` reads them back | `docs/shared/conventions.md` §7 |
| the icon | `Resources/AppIcon.icon` (re-export from Icon Composer, never hand-edit `icon.json`), `Resources/previews/ShiftPick-preview-1024.png`, `Resources/ICON-NOTES.md` | `architecture.md` *Build and signing* |
| the signing identity, the build or the release | `scripts/signing.env`, `scripts/make-app.sh`, `Resources/ShiftPick.entitlements`, `scripts/make-dmg.sh`, `scripts/release.sh` | `architecture.md` *Build and signing*, `macOS.md` |
| the gates a build passes: the tests it needs, what counts as the safety layer, what a sound launch is | `scripts/safety-gates.sh` (`SAFETY_FILES`, `SAFETY_SUITES`, `launch_is_sound`). **A gate is never removed or skipped without the owner** | `architecture.md` *Build and signing* |

## Commands

```bash
# ---- the two actions. A build of this app reaches a Mac by one of these and by nothing else. ----
make install     # skill: macos-install-locally. The production build → /Applications; leaves no .app or .dmg behind
make release     # skill: macos-publish-release. The same, plus tag, push, GitHub release, and the tree moves on
# -------------------------------------------------------------------------------------------------
```

- `swift build` — the three code targets and the probe. **This is the truth**; editor diagnostics are
  frequently stale.
- `swift test` — two bundles, and **one summary line each: count two.** `ShiftPickCoreTests` (330) runs in
  about four seconds; `ShiftPickPlatformTests` (38) spawns real subprocesses and threads and takes a moment
  longer.
  `swift test --filter <SuiteName>` runs one suite; `swift test --filter SafetyNetTests` is the quick look
  after any change near a net.
- `swift run axdump <command>` — the Accessibility probe (`Tools/axdump`, never shipped). `trust`, `views`,
  `at <x> <y>`, `range <x> <y> [ax ay]`, `tree [depth]`. **A command-line tool inherits the Accessibility
  grant of the terminal that starts it**, which is the only way to read Finder's hierarchy before the app
  itself is allowed to. `axdump range` works a ⇧ Shift click out exactly as the app does — the reading order,
  the stand-in, the shape and the selection it would leave — and prints it instead of applying it, which is
  how a doubt about a layout is settled.
- `make install` (`scripts/install.sh`) — **one of the two ways a build of this app reaches a Mac.** It
  refuses a tree whose tests fail, builds the real thing — Release, Developer ID, Hardened Runtime,
  notarized, stapled, wrapped in the disk image — takes the bundle out of that image into `/Applications`,
  opens it, and **reads its launch back from the log**: it fails on a tap macOS took away, taps it would not
  create, an open breaker, a second copy or silence, and passes on *listening* or *waiting for the
  permission*. It leaves **no `.app` and no `.dmg` anywhere under the repository**, on any exit path.
- `make release LEVEL=<patch|minor|major>` (`scripts/publish.sh <level>`) — **the other way.** Refuses on a
  dirty tree, on a failing test, and **while a file of the safety layer differs from the last release**,
  until the owner says `DRILL=walked` or `DRILL=waived` (never an agent's to set); computes the new version
  and refuses if that tag already exists, then bumps the version by the level given, commits and pushes that
  bump, and only then builds — everything `install` does, plus the tag, the push and the GitHub release
  carrying the image. Nothing bumps the version again afterward. Run it only when the owner has asked for a
  release, and ask which level if they have not said. `sh scripts/publish.sh <level> --no-install` publishes
  and leaves `/Applications` alone, which is how the update a user gets is tested.
- `sh scripts/drill.sh [seconds]` — **the dead-man's switch for the safety drill**
  (`docs/manual-test-checklist.md` §9): it kills ShiftPick after 30 s whatever happens, then follows the log.
  The owner starts it, right before each step that takes the grant away. An agent never runs a drill step.
- **There is no third way.** A bundle left in `build/` is a complete application that Spotlight offers;
  launching it by accident gives a second ShiftPick with a second event tap on the same clicks.
  `scripts/no-leftovers.sh` holds that rule.
- `scripts/version.sh` — the version rule, and the only thing that writes the version: **a local install
  always builds and installs exactly the tree's own version.** `scripts/publish.sh <patch|minor|major>` is
  the only thing that moves it: it bumps by that level, commits and pushes the bump before it builds
  anything, then releases exactly that version. Nothing bumps it again afterward. No releases yet → the tree
  is `0.0.1`.
- `/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug` — the app's log
  (`log` alone is a zsh builtin, hence the full path). Categories: `app`, `click`, `update`, `onboarding`
  (the wizard's poll, the stepping button's word, and at `debug` where that button actually is). **`click` says
  nothing on the ordinary path**: a line there is always about a ⇧ Shift click, and at `debug` it says why
  one was let through.
- `SHIFTPICK_UPDATE_FEED=file:///…/latest.json` in the installed app's environment replaces GitHub's reply
  with a stand-in, which is how the whole update is walked offline (`docs/manual-test-checklist.md` §10).

## Architecture

Three code targets, dependencies pointing one way: Core ← Platform ← App. Full version in
`docs/architecture.md`.

- **`Sources/ShiftPickCore`** — pure rules, **Foundation and CoreGraphics only** (`PurityTests` fails the
  build otherwise), and it never reads a clock. `LayoutItem` + `Lattice` + `Clusters` + `Grid` +
  **`LayoutModel`** (the whole of the selection maths: classify a set of icon frames, put every one of them
  in one reading order — the flow, or clusters fitted with grids — and answer with a range) + **`ShiftClick`**
  (AppKit's own selection model as a value over any order: the stand-in for a deselected anchor, and the runs
  a range replaces) + `LayoutConstants` (the inferred grids' tolerances, an extension of `K` kept out of the
  safety layer's `Constants.swift`) · `Settings` ·
  `Constants` (`K`, every number with its measurement) · `AppIdentity` + `Paths` · `QuietLaunch` ·
  `PathRules` + `UninstallPlan` · the update's rules (`UpdateCheck`, `UpdateSchedule`, `UpdatePanel`, `UpdateSession`,
  `StagedUpdateCheck`, `UpdateInstallScript`) · the Health page's rules (`Health`, `HealthRules`, `HealthReport`,
  and `HealthConstants`, its two numbers as an extension of `K` kept out of the safety layer's `Constants.swift`) · **`TapLifecycle`** + `TrustVerdict` (when the click tap may be
  enabled, as a value: an event and the time in, the new state and what to do about it out) · `Localization` (`Language`, `Loc`) + `Strings*` (every
  user-facing string, English and French side by side, one table per surface).
- **`Sources/ShiftPickPlatform`** — the only code that talks to the system. **`ClickGuard`** (the two event
  taps, and the only thing that may swallow a click; it executes what `Core/TapLifecycle` decides) ·
  `TapThread` (the thread the taps are served on, and nothing else is) · `DeadlineGate` + `ClickTicket` (the
  wait that keeps a click's budget whatever the worker does) · **`FinderAX`** (the only code that knows the shape of
  Finder's icon views: find the view under a point, read its items, read and set its selection) · `AX` (the
  C Accessibility API, one round trip per call) · `Permissions` · `LoginItem` · `SettingsStore` · `Log` ·
  `BoundedWait` (the one way to wait on another process: with a deadline, never on the main thread) ·
  the Health page's readers (`CrashReports`, `ProcessStats`, `FinderProcess`, each a read that answers
  at once) · the update's I/O (`UpdateChecker` + `UpdateDownload`, the only network code; `UpdateStager`,
  `CodeSignature`, `UpdateInstaller`, `DetachedProcess`) · `Uninstall`.
- **`Sources/ShiftPickApp`** — `AppDelegate` wires everything, including what happens when the Mac sleeps,
  locks or quits. **`ShiftPickEngine`** wires the guard, the gate and the resolver and publishes one status;
  **`ShiftClickResolver`** owns the anchor, makes every Accessibility call on its worker queue, and is where
  one ⇧ Shift click is decided. `MenuBarController` · the onboarding wizard
  (`OnboardingWindow` the controller, the pages, the row and `OnboardingMetrics`; `GrantCatalogue` what a
  grant is and the two lists; `ControlActionHandler`) ·
  `UpdateController` (the update's one owner) + `UpdateNotifier` + `UpdateWindow` · the settings window
  (`SettingsKit` the kit, `SettingsWindow` the toolbar window whose height follows the page, four
  `Settings…Page`, `SettingsView` with `SettingsPageID` and `SystemStatus`, `HealthCheck` the Health page's
  own readings).
- **`Tools/axdump`** — the Accessibility probe. Ships with nothing.

The app target has no automated tests. Its verification is `docs/manual-test-checklist.md`, `swift run axdump range`, and
the log.

## Rules

- **A build of this app reaches a Mac in exactly two ways, and there is no third.** See Commands.
- **Every safety net stays** (the section at the top). `docs/functional.md` §0 states them, the
  `shiftpick-safety-nets` skill locates them, `SafetyNetTests` and the `TapLifecycle` tests pin them, and
  `scripts/safety-gates.sh` keeps a build that lost one off every Mac. Loosening any of them is the owner's
  decision, asked for by quoting the rule.
- **Event taps are created in `ClickGuard` and nowhere else, and there are two**: the sentinel, which only
  listens, and the click tap. A new feature that needs input goes through them, under `TapLifecycle`.
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
  has already been set. The one line that swallows is `ticket.finish(swallow: true)`, and it is only honoured
  after a `ticket.commit()` that was granted. Adding a path that can swallow a click without having selected
  anything is a defect even if it never fires.
- **The click tap is enabled only while ⇧ Shift is held, and only `TapLifecycle` says when.**
  `CGEvent.tapEnable(…, enable: true)` on the click tap exists in exactly one place, `ClickGuard.run`, under
  `.enableClickTap`. A second place is a defect, whatever it is for.
- **A tap macOS disabled is never enabled by the event that says so.** That is the system's own safety net,
  and the callback that cut it is what cost a hard reboot (`docs/pitfalls.md` 13). What comes back is the
  next ⇧ Shift press, asked about like any other.
- **`AXIsProcessTrusted()` never keeps a tap enabled on its own, never creates one after launch, and is
  never called on the taps' thread.** It is a cached answer and has been seen to be wrong, and the call that
  refills it is a round trip with no timeout. Arming and creating ask `Permissions.liveVerdict`, on the
  worker; windows may show the cached one.
- **A helper that deletes is only ever pointed at what is provably ShiftPick's own.** Its paths are glued
  together from strings the bundle supplied, and an identifier that came back empty turns
  `~/Library/Caches/<identifier>` into the user's whole Caches folder. `Core/PathRules` asks first; nothing
  is removed when the answer is no. **And an uninstall touches nothing that is not ShiftPick's**: no other
  program's files, no system daemon.
- **Anything that takes the grant or the process away destroys both taps first**: `engine.shutDown()` comes
  before `tccutil`, before a quit, before anything new of that kind.
- **Nothing waits on another process on the main thread.** `Process.waitUntilExit()` runs the main run
  loop while it waits and froze the uninstall for a minute (`docs/pitfalls.md` 16). A wait on a tool or a
  daemon goes through `Platform/BoundedWait`, off the main thread, with a deadline.
- **The thread that serves the taps never calls Accessibility and never blocks without a timeout.** It hands
  a click to the worker through `DeadlineGate` and waits `K.clickBudget`; the budget belongs to whoever waits,
  never to the work. Every Accessibility element gets `K.axTimeout`, which sits under the budget, and an
  ordinary click never reaches ShiftPick's click tap at all. **The main thread touches no event**: nothing a
  window does can delay a click.
- **Never assume Finder's hierarchy.** It is not documented and it is not stable. `docs/macOS.md` holds
  what was read, `swift run axdump` is how it is read again, and `FinderAX` is the only file that may know
  it.
- **A view that is not Finder's is refused unless its window says it is a file panel.** The process check
  is what keeps ShiftPick out of everybody else's controls; `open-panel` and `save-panel` are the only two
  identifiers that get past it, and they are AppKit's own and not translated.
- **Accessibility is the only permission the app needs, and the only one it asks for.** Notifications are
  asked for the first time an automatic check has a release to announce, and for nothing else. **No Apple
  events**: `docs/pitfalls.md` says what was measured and why.
- **Every permission prompt follows a click of the user's, and the reader is never the asker.** Only the
  onboarding wizard's own button calls `Permissions.requestAccessibility`; nothing at launch, nothing when a
  window opens. `Permissions.accessibilityGranted` is what reads, which is why it may run behind a poll.
  `~/.claude/skills/macos-building-onboarding` says why, at length.
- **No user-facing string is written at its point of use.** It goes in a `Core/Strings*.swift` table, where
  one accessor answers for every language, so a string cannot exist in English alone.
- **Silence is a defect.** Anything that declines to act logs why, once, with the numbers.
- `ShiftPickCore` imports Foundation and CoreGraphics only, and never reads a clock: `now` is passed in.
- Commit per task, conventional commits, attribution trailers from the session's system reminder.
- **Stage by path. Never `git add -A`.**

## Traps

`docs/pitfalls.md` is the full list, with the measurements. The nine that cost the most:

0. **An enabled tap that can swallow, a revoked grant, and a callback that enables the tap again: the Mac
   takes no click and no key until the power button.** It happened here, and the log of it is
   `docs/pitfalls.md` 13. What is safe around a `.listenOnly` tap is not safe around a `.defaultTap`. **Never
   reproduce it by trying it**: `docs/manual-test-checklist.md` §9 is the drill, the owner's, behind the
   dead-man's switch of `scripts/drill.sh`.
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
5. **`set -e` reaches inside command substitutions.** A bare assignment from a command that can fail —
   `gh` with no repository yet, no login, no network — takes the assignment down with it under `set -e`
   unless the command ends in `|| true`; the full incident is in `docs/pitfalls.md` §3.
6. **An `NSStackView` spacer with no intrinsic height absorbs every point of a page's slack**, which left
   the onboarding wizard's stepping button drawn at the bottom right of the page and unclickable for ever
   from the moment the permission was granted. No constraint breaks and `AXFrame` keeps naming a plausible
   rectangle, so only a real hit test shows it. It shipped in four apps at once because the skill's reference
   file carried it: `docs/pitfalls.md` 11.
7. **A tap its own app disables is told it was disabled "for user input"**, the same reason macOS gives
   when it turns a tap off itself. Counted as a trip, that echo opened the breaker within a millisecond of the
   first launch; answered with another disable, it is heard back again. It is never counted and never
   answered (`docs/pitfalls.md` 15). Only a **timeout** is a trip.
8. **`Process.waitUntilExit()` runs the calling thread's run loop while it waits.** On the main thread it
   re-entered a window's poll and froze the uninstall for a minute (`docs/pitfalls.md` 16). A wait on another
   process goes through `BoundedWait`, off the main thread, with a deadline.

## Status

`swift build` is clean and `swift test` is green (330 + 38) at this commit. The app target has no automated
tests; `docs/manual-test-checklist.md` is its verification.

**Five files of the safety layer have changed since the last release** — `TapLifecycle.swift`,
`ClickGuard.swift`, `ShiftPickEngine.swift`, `ShiftClickResolver.swift`, `AppDelegate.swift` — so **§9 of
`docs/manual-test-checklist.md` is owed**, walked by the owner on an installed build, before the next
release. `make release` refuses until the owner says `DRILL=walked` or `DRILL=waived`, which is never an
agent's to set.

**What is proven and what is not, about the safety model.** The rules are proven: `TapLifecycle` is a value,
and its scenarios and 80,000 seeded events run on every `swift test`, as do the click's deadline and the
taps' thread. **The code no test can run is pinned where it stands**: `SafetyNetTests` holds 19 checks over
it, and each was shown to fail against a copy of the code with its net removed.
**The taps have been seen on the owner's Mac**, which is the only place they can be:
`ClickGuard` cannot run in a test, because a test runner has no Accessibility grant to create a tap with. The
first install found `docs/pitfalls.md` 15 within the millisecond; the builds after it passed the Finder
gesture, the lid closed and opened twice, a second copy started with `open -n`, drill steps A, B, C and E
of `docs/manual-test-checklist.md` §9, and the uninstall (step D, on its second walk). The grant was taken away with the switch
and with the minus button, the loss was caught before anything was enabled every time, and no click or key
was ever held up. `docs/macOS.md` has what the walk measured.

Known limitations, in plain words:

- **The first ⇧ Shift click can be Finder's.** Arming happens when the key goes down and takes a live answer
  from the Dock, about a millisecond. A click faster than that, a Dock that takes more than 50 ms to answer,
  a key press the sentinel never hears (a password field has the keyboard), or the first press after a wake or
  unlock notification that never arrived, leaves that one click to Finder, which adds one file; the press
  itself arms for the next, or wakes ShiftPick up. Never the other way round: nothing is ever
  swallowed on a guess.
- **One case the drill has not shown**: the click tap enabled at the very moment a grant goes. Turning the
  switch off takes a click and Touch ID, and the live question at the ⇧ Shift press got there first each
  time; the watch bounds that case to half a second. Whether `tccutil` reaches a running process is still
  reported by others, because the uninstall destroys both taps before it asks.
- **A range is bounded by what Finder has built.** Both ends have to be on screen. Click a file, scroll
  three screens, ⇧ Shift click another, and the click goes to Finder untouched, because the first file is
  no longer something Accessibility can name. Everything between two icons that are both visible is
  complete, which is the ordinary gesture.
- **The Desktop's flow is inferred, not asked for**, and so are the grids of a view nobody sorted. A Desktop
  sorted by name was measured filling columns from the right; a Desktop nobody sorted is classified
  hand-placed, cut into clusters and fitted with grids from where the icons sit, and a cluster whose rows
  are too ragged for the tolerances, or a range whose two ends are in different clusters, gets the rubber
  band. The tolerances hold a twenty-point wobble on the Desktop's 122-point pitch with a fifty-percent
  margin over forty layouts, and the cliff is a quarter of the pitch. None of it is something Finder states.
- **Labels on the right are a known gap.** Finder's *Label position: Right* makes cells several icon sides
  wide, which reads as one cluster per column, so a range across columns is the rubber band. A per-axis
  pitch was built and removed: it cannot tell a wide-celled grid from two ragged columns at opposite edges
  of the Desktop, and it would link both of those into one grid.
- **The update has never been seen end to end in this app.** Its rules are unit-tested and the install
  helper has installed and rolled back a stand-in app for real; the notification, the update window and
  ShiftPick installing over itself are `docs/manual-test-checklist.md` §10. Nothing is published, so every check answers
  **No release published yet** until the repository is public and carries a release.
- **The uninstall froze on its first walk and passed its second.** The first waited on its main thread
  (`docs/pitfalls.md` 16). The rework took about fifty milliseconds for its system steps, with no spinning
  wheel, and left nothing behind: the bundle in the Trash, the domain, the support folder, the caches and the
  saved state gone, the grant reset and the login item removed.
