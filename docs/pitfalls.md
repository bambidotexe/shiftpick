# ShiftPick — pitfalls

What looks right on macOS and is not, with the measurement that settled it. **This is the only place that
records approaches that failed.** Nothing here is a rule; the rules are in `functional.md`.

The traps every app of the family shares are `shared/pitfalls.md`. Entries 13, 15 and 16 below are this
app's own record, logs and all, of what is there as E1, E2 and X4.

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
that is a real guarantee rather than a hope: the in-between icons of an arranged layout, and of one inferred
grid of a hand-placed one, lie in the band of lines between the two ends, and the rubber band is bounded by
their two frames, so an in-between icon cannot be off screen when both ends are on it.

When an end is **not** on screen it is not something Accessibility can name, so a stored anchor that has
scrolled away reads as gone and a stand-in is taken from what is still selected on screen. With nothing
selected there either, the click is measured from the first icon while the view is at its top, and otherwise
goes through. **That is deliberate.** A range that quietly left files out would be worse than no range at
all: nobody would notice until they had moved or deleted the wrong set.

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

This is every app's trap: `docs/shared/pitfalls.md`, **B5**. It fired here first: `version_published` handed `install.sh` an empty version, and the trace ended at `+ VERSION=` / `+ exit 1`.

## 4. `swift test` prints one summary line per bundle

This is every app's trap: `docs/shared/pitfalls.md`, **T2**. Here: `ShiftPickPlatformTests` and `ShiftPickCoreTests`, two lines.

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

This is every app's trap: `docs/shared/pitfalls.md`, **B1**.

## 8. A sandboxed shell cannot answer `AXIsProcessTrusted()`

This is every app's trap: `docs/shared/pitfalls.md`, **T5**. Inside the sandbox the probe answered `false`; the same binary outside it answered `true`.

## 9. SwiftUI text in a hosting controller does not wrap on its own

This is every app's trap: `docs/shared/pitfalls.md`, **O10**. It was measured here: 460 × 205 with three truncated one-line texts, 460 × 269 with `fixedSize` and a content width.

## 10. A permission's name in System Settings is not the permission's name

This is every app's trap: `docs/shared/pitfalls.md`, **O6**. Here both places that name the grant quote the pane's own strings (`docs/macOS.md`, *The permission*), and `LocalizationTests` holds a two-entry exemption so that the "Control" in the quoted name is not read as the ⌃ Control key.

## 11. An `NSStackView` spacer with no intrinsic height absorbs every point of a page's slack

This is every app's trap: `docs/shared/pitfalls.md`, **O9**. Here the footer is `OnboardingWindowController.listPage`, and `swift run axdump at <x> <y>` is the instrument: its hit test is system-wide, so it answers over this app's own windows. (`axdump tree` will not help: it walks Finder and takes no pid.)

## 12. A file panel's collection list has no `AXWindow`

Finder's `AXList/AXCollectionList` answers `AXWindow` with the window it is in. **An Open or Save panel's
does not**: it answers `kAXErrorNoValue`. Since the window's `AXIdentifier` is the only thing that tells a
panel from any other application's collection view, that silently refused every panel click until the
window was found by walking the chain the hit test had already built instead.

## 13. An enabled click tap, a revoked grant, and a callback that enables the tap again

**Symptom.** The Accessibility switch for ShiftPick is turned off in System Settings while the app is
running. The pointer still moves. No click lands anywhere, the keyboard does nothing, and the only way out
is holding the power button.

**What the log said**, read back after the reboot:

```
16:00:09.491 E [click] the event tap was disabled by TIMEOUT (1 this launch) and re-enabled; clicks were lost
16:00:19.032 E [click] the event tap was disabled by TIMEOUT (2 this launch) and re-enabled; clicks were lost
16:00:22.781 E [click] the event tap was disabled by TIMEOUT (3 this launch) and re-enabled; clicks were lost
16:03:07.996    [app]  ShiftPick enabled                                     ← pid 1415: after the power button
```

and what it did **not** say: no `the Accessibility permission has been taken away`, anywhere.

**Why, in three parts.**

1. The tap was `.defaultTap` and enabled for the life of the process. Once the grant went, macOS stopped
   running the callback and went on routing every click into the tap, so each click held the whole session's
   input, keyboard included, until the system's own timeout gave up on the tap.
2. **The system's safety net worked, three times, and the app cut it three times.** macOS disabled the tap
   and said so with `tapDisabledByTimeout`, which still reaches the callback of a process that has lost the
   grant. The callback's answer to that event was `CGEvent.tapEnable(tap, true)`. Without that one line the
   incident is a second of lost clicks.
3. The revocation was never noticed. The handler for `com.apple.accessibility.api` read
   `AXIsProcessTrusted()` once, got the answer from before the change, found the engine already watching,
   and returned. Nothing asked again.

**How it got here.** The tap's scaffolding (the main run loop, enable-again-on-disable, the notification as
the only watch on the grant) was taken from a sibling app whose taps are `.listenOnly`, where all of it is
harmless: a listener holds nothing up. One option was changed to `.defaultTap` and everything around it
stayed. **What is safe around a listening tap is not safe around one that can swallow.**

**The second way in.** The uninstall ran `tccutil reset Accessibility` with the tap still enabled, and then
waited for a click on an alert.

**What holds now** is `architecture.md`, *The safety model*. In one line each: the click tap is enabled only
while ⇧ Shift is held; a tap macOS disabled is never enabled by the event that says so; arming asks a live
question first; the notification disarms before it asks; both taps are destroyed before the uninstall touches
the grant. `TapLifecycleTests.testATapMacOSDisabledIsNeverReEnabledByThatEvent` is this incident as a test,
and putting the line back fails it and 6,137 assertions of `TapLifecycleInvariantTests`.

**Do not measure this by trying it.** `manual-test-checklist.md` §9 is the drill, and it starts a dead-man's switch
first: `scripts/drill.sh` kills the app after thirty seconds whatever happens to the mouse, and a process
that dies takes its taps with it.

## 14. A budget the work checks on itself is not a budget

The click path promised 150 ms and checked the clock at three places between steps, while every
Accessibility element was given 200 ms to answer, which is more than the whole budget, and the loop that
reads one frame per icon checked nothing. A Finder stuck on a network volume would have held a click for
200 ms times the number of icons on screen, with the event tap's thread inside the call.

**What holds.** The thread that holds the click does no work and waits with a timeout (`DeadlineGate`); the
work happens elsewhere and is told when nobody is waiting any more. `K.axTimeout` sits under `K.clickBudget`.
The same stuck Finder now costs a click its range, 150 ms later, and nothing else.

## 15. A tap disabled by its own app is told it was disabled for user input

**Symptom.** The first install of the rewritten taps, on the owner's Mac, with nobody touching anything:

```
21:29:41.042 [click] listening for ⇧ Shift; the click tap exists and is disabled
21:29:41.042 [click] macOS took the click tap away (userInput), 1 of 3 inside 60 s; …
21:29:41.042 [click] macOS took the click tap away (userInput), 2 of 3 inside 60 s; …
21:29:41.042 [click] macOS took the click tap away (userInput) 3 times in 60 s; both taps destroyed …
21:29:41.042 [app]   not listening: macOS kept taking the click tap away, so it is no longer created
```

**Why.** `CGEventTapEnable(tap, false)` makes macOS deliver `kCGEventTapDisabledByUserInput` to that tap's
own callback, for every call, even on a tap already disabled. The SDK's own comment on `CGEventTapEnable` says
it ("a user requests taps be disabled"), the user being the program. The click tap is born enabled and was
disabled in the next line; that came back as a trip, the trip disabled the tap again, which came back as the
next one, and the third opened the breaker, all in one millisecond. It failed the safe way (no tap, every click
to Finder), and it would have happened again at every disarm: three ⇧ Shift releases a minute and ShiftPick
turned itself off.

**What holds.** Only a timeout is a trip. A disable for user input disarms if the tap is armed and is nothing
otherwise, and is never answered with another disable. `TapLifecycleTests` has the launch as a scenario, and
the invariant run treats the event as the tap being off, so a lifecycle that stayed armed through one fails it.
The lesson is the one entry 13 already names, from the other side: **the tap API's pseudo-events are not what
their names say**, and a rule built on one needs the event measured, not read.

## 16. `Process.waitUntilExit()` on the main thread runs the main run loop

**Symptom.** The first uninstall on the owner's Mac, from Settings › General › Uninstall: a spinning wheel
over the app for as long as the dead-man's switch let it live, a minute. The Mac itself kept answering. When
the switch killed the app, the permission had been reset and nothing else had happened: the bundle was still
in `/Applications`, the login item still registered, the preferences still there.

**What the log said.** The taps were destroyed first, as they should be (`stopped listening; no event tap
exists`, 22:15:42.062), and `tccutil` reset the grant and exited in ten milliseconds. The app's main thread
then logged one more thing, an `SMAppService` status read at 22:15:42.082, **while it was still waiting for
`tccutil`**, and nothing ever again. The login-item daemon never received an unregister.

**Why.** The uninstall waited for `tccutil` with `Process.waitUntilExit()`, on the main thread, and that call
**runs the calling thread's run loop until the tool is done**. Measured with a throwaway app: thirteen timer
ticks during a 64 ms wait for `/usr/bin/true`. So in the middle of an uninstall that was resetting the grant,
the Settings window's two-second refresh ran, read the grant and the login item, and one of the main thread's
own calls from inside that wait never came back. Which one is not known: a hardened app cannot be sampled
without root, and the next run's log now times every step to say.

**What holds.** Nothing waits on another process on the main thread. `Platform/BoundedWait` blocks the calling
thread and nothing else, stops a tool past its deadline and gives up on a reply that does not come; the
uninstall's `tccutil` and login item run on a global queue through it, `K.uninstallStepWait` at most each,
with the Settings refresh paused and a line in the log per step. A step that does not answer is named in the
last alert and the uninstall goes on. `BoundedWaitTests` pins both waits, including that nothing on the
caller's run loop fires while they wait.

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
  and ShiftPick installing over itself are `manual-test-checklist.md` §10.
- **Open and Save panels are covered, and only lightly walked.** A panel's icon view was read, its
  selection was set through Accessibility, and its own ⇧ Shift click was measured toggling one item; the
  live gesture in a panel is `manual-test-checklist.md` §5. A panel that allows only one file is left alone by the
  panel itself, not by ShiftPick.
