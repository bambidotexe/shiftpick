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
- **`ShiftPickApp`** owns the run loop, the windows and the wiring of the one behaviour.
- **`Tools/axdump`** never ships. `scripts/make-app.sh` copies one executable into the bundle and this is
  not it.

### What lives where

| Layer | Files | What they own |
|---|---|---|
| Core | `LayoutItem`, `Lattice`, **`LayoutModel`** | The selection maths. Frames in, a classified layout and a range out. |
| | **`TapLifecycle`**, `TrustVerdict` | When the click tap may be enabled, and what every event does to it. An event and the time in, the new state and what to do about it out. |
| | `Settings`, `Constants` (`K`), `AppIdentity`, `Paths`, `QuietLaunch`, `SupportLink` | The values the rest of the app is built on. |
| | `UpdateCheck`, `UpdateSchedule`, `UpdatePanel`, `UpdateSession`, `StagedUpdateCheck`, `UpdateInstallScript` | Every rule of the update that does not need a network or a disk. |
| | `UninstallPlan` | What an uninstall removes, and the text of the helper that finishes it. |
| | `Localization`, `Strings*` | Every sentence the user reads, in both languages. |
| Platform | **`ClickGuard`** | The two event taps, and the only thing that may swallow a click. It does what `TapLifecycle` says and decides nothing. |
| | `TapThread`, `DeadlineGate` + `ClickTicket` | The thread the taps are served on, and the wait that keeps a click's budget whatever the worker does. |
| | **`FinderAX`** | The only code that knows the shape of Finder's icon views. |
| | `AX` | The C Accessibility API, one round trip per call. |
| | `Permissions`, `LoginItem`, `SettingsStore`, `Log` | The rest of the system boundary. |
| | `UpdateChecker` + `UpdateDownload`, `UpdateStager`, `CodeSignature`, `UpdateInstaller`, `DetachedProcess` | The update's I/O. The only network code in the app. |
| | `Uninstall` | The registrations an uninstall gives back. |
| App | `ShiftPickMain`, `AppDelegate`, `MenuBarController` | The app: one instance, its windows, and what it does when the Mac sleeps, locks or quits. |
| | **`ShiftPickEngine`**, **`ShiftClickResolver`** | The one behaviour. The engine wires and publishes a status; the resolver is what one ⇧ Shift click does, and makes every Accessibility call. |
| | `OnboardingWindow` + `GrantCatalogue` + `ControlActionHandler`, `SettingsKit`, `SettingsWindow`, `SettingsView`, `Settings…Page` | The windows. The wizard is the one hand-built AppKit window; everything else is SwiftUI in a hosting controller. |
| | `UpdateController`, `UpdateNotifier`, `UpdateWindow` | The update's one owner and its two surfaces. |

## The safety model

One sentence shapes everything below: **a bug in this app must never be able to break clicking.**

An event tap that can swallow a click sits in the path of every click in the session, and the window server
waits for its answer. If its owner loses the Accessibility grant while it is enabled, the callback stops
being run and the clicks are still routed into it: each one stalls the whole session's input until macOS
gives up on the tap and disables it. macOS disabling it is the net under everything; an app that enables it
again from that callback cuts the net, and the Mac stays unusable until it is powered off. `pitfalls.md` 13
has the log of the day that happened here.

So the design does not try to notice that moment in time. **It arranges for there to be nothing to go wrong
at that moment**, and then layers what is left:

| Layer | What it is | What it survives |
|---|---|---|
| 0 | **The click tap is enabled only while ⇧ Shift is held.** The rest of the time the only live tap is a listener, which the window server never waits for. | A grant revoked, a thread hung, a Mac asleep, at any moment the key is up: nothing is enabled to stall. |
| 1 | **A tap macOS disabled is never enabled by the event that says so**, and three timeouts in a minute destroy both taps until another try is asked for. A disable "for user input" is not counted: it is also what a tap is told when the app disables it itself. | Everything the layers below miss costs one stalled click, once, and then heals itself. |
| 2 | **Arming asks first, and so does creating the taps**: a live Accessibility request, answered by the Dock, no older than 2 s and asked after the grant was last put in doubt. Only a process that has just started may create them on the cached answer. Any call that comes back refused destroys both taps. | `AXIsProcessTrusted()` going on saying yes after the grant has gone. |
| 3 | **The privacy notification disarms before anything is asked**, then the grant is looked at three times over three seconds. | The notification arriving before the answer changes. |
| 4 | **A watch while armed, and only then, that disarms rather than wait**: the keys according to the keyboard itself, a minute with nothing clicked, a question about the grant still unanswered at the next look. | A key release never heard, an ⌥ Option press never heard, a key held down by a bag, Sticky Keys, a worker that has stopped answering. |
| 5 | **Taps destroyed first** on quit and before an uninstall resets the grant, and nothing created after that whatever the lifecycle believes; nothing armed across sleep, the lock screen, another user's session, each counted apart and held against the session itself at any news. | The app taking its own grant away; a lid that locks, sleeps and wakes still locked; a notification that never arrives. |
| 6 | **The budget is kept by whoever waits.** The taps' thread hands a click to a worker and waits 150 ms. | A Finder, or an Accessibility call, that never answers. |

**The rules are a value.** `Core/TapLifecycle` decides all of layers 0 to 5 from an event and the time, with
no tap, no thread and no clock in sight, which is what lets every scenario be a unit test: 96 of them by
name, and a seeded run of 80,000 events in an order nobody would write, after each of which ten sentences
have to hold: the click tap is enabled in exactly one phase, only ever while the keys ask for it, and taps
are only ever created on a live answer. `Platform/ClickGuard` executes what it says, in order. What it
carries itself is what only it can see: which press is ShiftPick's to decide, that the callback never enables
a tap, and that nothing is created once it has been shut down.

**The code around the value is pinned where it stands.** `ClickGuard` cannot run in a test, because a test
runner has no Accessibility grant to create a tap with, so `SafetyNetTests` reads the source instead: one
tap that can swallow and one line that enables it, no enable in a callback, the taps on their own thread and
never asking anything that can block, a held click only through the deadline and swallowed only after its
selection, the taps down before the grant or the process goes, one copy at a time, and the numbers above in
their order. Each check was shown to fail against a copy of the code with its net removed.
**And a build that lost a net reaches no Mac**: `scripts/safety-gates.sh` (below) holds the gates. The
guarantees themselves are `functional.md` §0, and the `shiftpick-safety-nets` skill says where each lives and
what pins it; it comes before any change near one.

## The click path

**Three execution contexts, and nothing shared between them without a lock.**

| Context | Owns | Never does |
|---|---|---|
| **the taps' thread** (`TapThread`, its own run loop, user-interactive) | both event taps, `TapLifecycle`, the watch kept while armed, the looks after a notification | an Accessibility call, or anything else that can block without a timeout |
| **the worker** (one serial queue, user-interactive) | every Accessibility call, the anchor, the live question about the grant | hold an event |
| **the main thread** | windows, settings, the published status | touch an event, or delay one: a stalled window cannot delay a click |

```
sentinel tap (.listenOnly: flagsChanged | leftMouseDown)          always on, holds nothing up
  ├─ ⇧ Shift down  → TapLifecycle: kill switch? ⌥/⌃? grant vouched for within 2 s?
  │                    └─ no  → ask the worker for a live answer, arm when it says trusted
  │                    └─ yes → enable the click tap, start the watch
  ├─ ⇧ Shift up    → disable the click tap, stop the watch   (after a swallowed press: once its release has come)
  └─ a plain press → the worker looks for the anchor 60 ms later; the click itself was never held

click tap (.defaultTap: leftMouseDown | leftMouseUp)              enabled only while armed
  ├─ no ⇧ Shift, or ⌥ Option / ⌃ Control → return the event
  ├─ DeadlineGate.run                     the worker busy with the click before → return the event at once
  │    └─ on the worker: ShiftClickResolver.shiftClick
  │         ├─ FinderAX.hit(at:)            the element the window server draws there
  │         ├─ FinderAX.isRenaming          a text field has focus → no answer
  │         ├─ FinderAX.items(in:)          one AXFrame read per icon, stopping if nobody is waiting any more
  │         ├─ LayoutModel(items:)          rows, columns, arranged or not, the fill order
  │         ├─ the anchor                   stored, or derived from the selection
  │         ├─ LayoutModel.range(from:to:)  the answer
  │         ├─ ticket.commit()              refused when the click has already been given back → set nothing
  │         ├─ FinderAX.select              one call
  │         ├─ ticket.finish(swallow: true) ← the waiting thread wakes here
  │         └─ FinderAX.raise               Finder forward, the window up; nobody waits for this
  │    └─ the taps' thread waits 150 ms (100 ms more only if the selection is being set), then returns the event
  ├─ swallow the press, and the release that carries the same event number
  └─ tapDisabledByTimeout / ByUserInput → reported to TapLifecycle, and NEVER enabled here
```

**Costs, measured on macOS 27 on an M-series Mac.** One `AXFrame` read of a Finder icon is about 0.06 ms
warm, so a full screen of icons is 6 to 20 ms. `AXFrame` is asked for rather than `AXPosition` and
`AXSize` because it is one round trip instead of two, and the path asks it of every icon on screen. The
budget belongs to the thread that waits and not to the work, so a Finder that has stopped answering costs a
click its range rather than the Mac its mouse.

**An ordinary click never reaches ShiftPick's click tap at all**: with ⇧ Shift up it is disabled. The
sentinel hears the press, which holds nothing up, and the anchor is looked for on the worker afterwards.

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

- **Events never touch the main thread.** The taps have a thread of their own, the Accessibility calls a
  serial queue of their own, and the two meet only through `DeadlineGate`. The windows, the settings store
  and `ShiftPickEngine`'s published status are `@MainActor`; the engine hears about a change of status through
  one hop to the main queue and about nothing else.
- **`TapLifecycle` is touched only on the taps' thread**, so it needs no lock. Other threads hand it events
  with `TapThread.perform`. The one caller that cannot wait, the teardown, uses `performAndWait`, which says
  whether the block ran or never will: past `K.shutDownWait` the ports are disabled and invalidated from the
  calling thread instead, which the window server honours from any thread.
- **Nothing waits on another process on the main thread.** `Process.waitUntilExit()` runs the calling
  thread's run loop while it waits, which on the main thread re-runs timers, notifications and view updates
  in the middle of the wait (`pitfalls.md` 16). `Platform/BoundedWait` blocks the calling thread and nothing
  else, with a deadline, and is only ever called off the main thread: the uninstall's `tccutil` and login
  item run on a global queue and hop back to show the last alert.
- **Two more exceptions, both in the update.** `URLSession` calls its delegate on its own queue and the
  caller hops; unpacking a disk image runs on one serial queue of its own, because it mounts, copies and
  verifies, and two of those at once would share a mount point.
- **Nothing polls while idle.** With the permission granted and no window open, the only timer armed is the
  update schedule's, which is coarse (`K.updateTick`) and tolerant. The watch over the click tap exists only
  while ⇧ Shift is held; the looks after a privacy notification are three and then nothing. The Settings
  window starts and stops its own two-second poll; the onboarding wizard starts and stops the other, also two
  seconds.

## Persistence

| What | Where |
|---|---|
| The three switches, and whether the wizard has been walked | one JSON blob in `UserDefaults`, key `settings.v1` |
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

`scripts/release.sh` is the shippable build in the order Apple's checks need: the tests → build → verify the
signature, the runtime flag and the entitlements → notarize the app → staple → disk image → sign and notarize
the image → staple → `spctl` on both. It publishes nothing.

`scripts/install.sh` and `scripts/publish.sh` are **the only two ways a build reaches a Mac**, and neither
leaves an `.app` or a `.dmg` anywhere under the repository on any exit path.

**`scripts/safety-gates.sh` holds the three gates both pass through.**

- `tests_pass`, run by `release.sh` before it builds: `swift test`, both bundles' summary lines, and every
  suite that pins a net (`SAFETY_SUITES`) among the green. Neither way builds anything from a tree whose
  tests say a net is gone.
- `drill_gate`, run by `publish.sh` before it bumps and pushes the version: when a file of the safety layer
  (`SAFETY_FILES`) differs from the last release tag, it refuses until the owner says `DRILL=walked` (the
  drill of `manual-test-checklist.md` §9, walked on an installed build of that tree) or `DRILL=waived`.
- `launch_is_sound`, run by both after they open the app: the app's own log from the moment it was opened.
  The launch passes when it names the version installed and then says *listening* or *waiting for the
  permission*; it fails on a tap macOS took away, taps it would not create, an open breaker, a second copy, or
  twenty seconds of silence, which is how the first install of the rewritten taps would have been caught
  (`pitfalls.md` 15).

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
