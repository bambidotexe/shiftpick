# ShiftPick — how it is built

## Three targets, dependencies pointing one way

```
ShiftPickCore  ←  ShiftPickPlatform  ←  ShiftPickApp
                                     ←  Tools/axdump
```

- **`ShiftPickCore`** imports **Foundation and CoreGraphics and nothing else**, and never reads a clock:
  `now` is always passed in. `PurityTests` fails the build otherwise. Everything here is a value in and a
  value out, which is what lets the whole of the selection maths be tested with no Mac, no Finder and no
  click.
- **`ShiftPickPlatform`** is the only code that talks to the system. Nothing above it calls an
  Accessibility function, creates an event tap or opens a URL.
- **`ShiftPickApp`** owns the run loop, the windows and the one object that decides a click.
- **`Tools/axdump`** never ships. `scripts/make-app.sh` copies one executable into the bundle and this is
  not it.

### What lives where

| Layer | Files | What they own |
|---|---|---|
| Core | `LayoutItem`, `Lattice`, **`LayoutModel`** | The selection maths. Frames in, a classified layout and a range out. |
| | `Settings`, `Constants` (`K`), `AppIdentity`, `Paths`, `QuietLaunch`, `SupportLink` | The values the rest of the app is built on. |
| | `UpdateCheck`, `UpdateSchedule`, `UpdatePanel`, `UpdateSession`, `StagedUpdateCheck`, `UpdateInstallScript` | Every rule of the update that does not need a network or a disk. |
| | `UninstallPlan` | What an uninstall removes, and the text of the helper that finishes it. |
| | `Localization`, `Strings*` | Every sentence the user reads, in both languages. |
| Platform | **`MouseTap`** | The one event tap, and the only thing that may swallow a click. |
| | **`FinderAX`** | The only code that knows the shape of Finder's icon views. |
| | `AX` | The C Accessibility API, one round trip per call. |
| | `Permissions`, `LoginItem`, `SettingsStore`, `Log` | The rest of the system boundary. |
| | `UpdateChecker` + `UpdateDownload`, `UpdateStager`, `CodeSignature`, `UpdateInstaller`, `DetachedProcess` | The update's I/O. The only network code in the app. |
| | `Uninstall` | The registrations an uninstall gives back. |
| App | `ShiftPickMain`, `AppDelegate`, **`ShiftPickEngine`**, `MenuBarController` | The app, and the one behaviour. |
| | `OnboardingWindow`, `SettingsKit`, `SettingsWindow`, `SettingsView`, `Settings…Page` | The windows. |
| | `UpdateController`, `UpdateNotifier`, `UpdateWindow` | The update's one owner and its two surfaces. |

## The click path

Everything below happens **on the main run loop**, inside the event tap's callback, with the event still
held. That is the constraint the whole design is shaped by: while this runs, nobody's clicks are being
delivered.

```
CGEventTap  (leftMouseDown | leftMouseUp)
  │
  ├─ enabled?              no  → return the event                      (one boolean)
  ├─ ⇧ Shift held?         no  → note the anchor later, return         (one bit test)
  ├─ ⌥ Option / ⌃ Control? yes → return the event
  │
  └─ ShiftPickEngine.shiftClick
       ├─ FinderAX.hit(at:)            the element the window server draws there
       ├─ FinderAX.isRenaming          a text field has focus → return
       ├─ FinderAX.items(in:)          one AXFrame read per icon
       ├─ LayoutModel(items:)          rows, columns, arranged or not, the fill order
       ├─ the anchor                   stored, or derived from the selection
       ├─ LayoutModel.range(from:to:)  the answer
       ├─ FinderAX.select              one call
       ├─ FinderAX.raise               Finder forward, the window up
       └─ swallow the press, and its release
```

**Costs, measured on macOS 27 on an M-series Mac.** One `AXFrame` read of a Finder icon is about 0.06 ms
warm, so a full screen of icons is 6 to 20 ms. `AXFrame` is asked for rather than `AXPosition` and
`AXSize` because it is one round trip instead of two, and the path asks it of every icon on screen. The
whole path is bounded by `K.clickBudget`, and every element by `K.axTimeout`, so a Finder that has stopped
answering costs a click rather than the mouse.

**The anchor is tracked the other way round.** A plain or ⌘ Command click is handed straight back to the
system, and `K.anchorDelay` later the same point is hit-tested from a dispatched block. An ordinary click
therefore never reaches Accessibility at all.

## The selection maths

`LayoutModel` is built once per click from the icons of one view and answers two questions: where each icon
sits in fill order, and which icons lie between two of them.

1. `Lattice.build` clusters the reference points into rows and columns. Two passes, because the tolerance
   the rule asks for is half the median cell size and the cells are not known until the first pass has
   found them.
2. Each group's cells are held against the four fill orders. A group is *filled* by an order when its
   occupied cells are the first *n* of that order. All four fit a single row, which is why the order
   Accessibility listed the items in, and then the container's own default, break the tie.
3. A layout no order fits is *hand-placed*, and its range is the rectangle the two icons span.

**`O(n log n)`.** The clustering sorts, the check sorts ranks, and the lattice is never walked cell by
cell. The numbers every rank is counted from are worked out once per group and not inside a comparator:
that alone was the difference between 47 seconds and 0.06 for five thousand icons.

## Threading

- Everything is on the **main actor**. The tap's source is added to the main run loop, so its callback is,
  and the engine, the windows and the settings store are all `@MainActor`.
- **Two exceptions, both in the update.** `URLSession` calls its delegate on its own queue and the caller
  hops; unpacking a disk image runs on one serial queue of its own, because it mounts, copies and verifies,
  and two of those at once would share a mount point.
- **Nothing polls while idle.** With the permission granted and no window open, the only timer armed is the
  update schedule's, which is coarse (`K.updateTick`) and tolerant. The Settings window starts and stops
  its own two-second poll; the onboarding window starts and stops its one-second one.

## Persistence

| What | Where |
|---|---|
| The three switches | one JSON blob in `UserDefaults`, key `settings.v1` |
| Launch at login | `SMAppService`, and nowhere else: the system's answer is the only one |
| The quiet-launch marker, the update's working folder | `~/Library/Application Support/ShiftPick` |
| The anchor | nowhere. It is two Accessibility elements held in memory, and a launch starts without one |

## Build and signing

`scripts/make-app.sh` assembles `build/ShiftPick.app`: the release binary, `Assets.car` compiled by
`actool` from `Resources/AppIcon.icon`, a flat `.icns` rasterised from the 1024 px master, two `.lproj`
directories so the app appears in Language & Region's per-app list, a generated `Info.plist`, and one
`codesign` with `--options runtime --timestamp`. There is nothing nested to sign.

**The app's name, its bundle identifier and its GitHub repository are written once**, in
`scripts/signing.env`. `make-app.sh` puts all three into the built `Info.plist` — the repository as a
private `SPUpdateRepository` key — and `Core/AppIdentity` reads them back, so the running app never spells
its own name out.

`scripts/release.sh` is the shippable build in the order Apple's checks need: build → verify the signature,
the runtime flag and the entitlements → notarize the app → staple → disk image → sign and notarize the
image → staple → `spctl` on both. It publishes nothing.

`scripts/install.sh` and `scripts/publish.sh` are **the only two ways a build reaches a Mac**, and neither
leaves an `.app` or a `.dmg` anywhere under the repository on any exit path.

## The update, end to end

1. `UpdateController` is the one owner. It holds the schedule, the panel the Settings group draws, the
   session the window draws, and the outcome of the last install.
2. A check is `UpdateChecker.check`; what the answer means is `Core/UpdateCheck`.
3. Update opens `UpdateWindow`, which fetches through `UpdateDownload` — held against the length and
   SHA-256 GitHub stated — then `UpdateStager` mounts the image, copies the app out and checks it against
   `StagedUpdateCheck` and `CodeSignature`. **Everything that can refuse an update runs while the app is
   still up.**
4. Install and Relaunch writes `UpdateInstallScript.text` next to the update, starts it through
   `DetachedProcess` in a process group of its own, and quits. The helper waits for the pid, swaps two
   folders, opens the new copy, and puts the old one back if the new version is not seen running.
5. The helper leaves one line behind. The next launch reads it, renames it to `<result>.read` — which is
   how the helper knows a version that is gone again two seconds later had started properly — and opens the
   window that says how it ended.
