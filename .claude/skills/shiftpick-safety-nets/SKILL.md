---
name: shiftpick-safety-nets
description: Use before changing anything in ShiftPick that can reach the event taps or the user's input — the click tap or the sentinel, when a tap is armed, enabled or created, the click path and its budget, ShiftClickResolver or DeadlineGate, how the Accessibility grant is read, asked for or lost, sleep, the lock screen and fast user switching, a second copy, the quit, the uninstall, the update's install and relaunch, anything that waits on another process or thread, a number in Core/Constants.swift, or scripts/install.sh, release.sh, publish.sh or safety-gates.sh — and before adding any feature that listens to, swallows, delays or posts input events. Also use when SafetyNetTests, TapLifecycleTests or TapLifecycleInvariantTests fail, when a request would loosen a rule in docs/functional.md §0, and when asked to test what happens when the permission is taken away.
---

# ShiftPick's safety nets

**A bug in this app must never be able to break clicking.** ShiftPick holds an event tap that can swallow a
click, and the window server waits for that tap's answer on every click it is enabled for. An enabled tap, a
grant taken away while the app ran, and a callback that enabled the tap again once left the owner's Mac
taking no click and no key until the power button (`docs/pitfalls.md` 13). The nets below are what stands
between the app and that again. **Your change keeps every one of them.**

Read these first: `docs/functional.md` §0 (the guarantees, as rules), `docs/architecture.md` *The safety
model*, `docs/pitfalls.md` 13 to 16.

## The owner's rule

**No net is removed, loosened or worked around without the owner saying so, in words, for that net.** A
request that needs one to go is a conflict under step 2 of the workflow in `CLAUDE.md`: stop, quote the
rule from `docs/functional.md` §0, and ask. Not "it is only for a moment", not "behind a flag", not "the
test was in the way". A test that pins a net fails because code moved: **move the check with the code and
keep what it asserts.** It fails because a net is gone: **put the net back.**

## The nets

| # | The net | Where it lives | What pins it |
|---|---|---|---|
| 1 | **One tap can swallow a click**, ClickGuard's click tap (`.defaultTap`). The sentinel is `.listenOnly` and can hold nothing up. No other tap, in the app or in `Tools/axdump`; no `NSEvent` global monitor, no HID manager, and no posted event | `Platform/ClickGuard.createTaps` | `SafetyNetTests.testOnlyOneTapCanSwallowAClick`, `testNothingElseTouchesTheEventStream` |
| 2 | **The click tap is enabled only while ⇧ Shift is held** (or while a swallowed press waits for its release), decided by `TapLifecycle` alone. `tapEnable(tap: click, enable: true)` exists once, under `.enableClickTap` | `Core/TapLifecycle.swift`; `ClickGuard.run` | `TapLifecycleTests`, `TapLifecycleInvariantTests` 1, 5, 8; `SafetyNetTests.testTheClickTapIsEnabledInOnePlaceOnly` |
| 3 | **A tap macOS disabled is never enabled by the event that says so.** No callback calls `tapEnable`. The notice is fed after its callback returns (`feedAfterThisCallback`). What comes back is the next ⇧ Shift press, asked about like any other | `ClickGuard.sentinelHeard`, `clickHeard`; `TapLifecycle.tripped` | `TapLifecycleInvariantTests` 4; `SafetyNetTests.testATapIsNeverEnabledFromACallback`, `testANoticeThatATapWasDisabledIsHeardAfterItsCallback` |
| 4 | **The breaker.** `K.breakerTrips` (3) timeouts inside `K.breakerWindow` (60 s) destroy both taps, and only `tryAgain` (the *Enable ShiftPick* switch turned off and on) creates them again. A disable **for user input** is the app's own disable heard back and is never counted (`docs/pitfalls.md` 15) | `TapLifecycle.tripped`, `disabledForUserInput` | `TapLifecycleTests`; `SafetyNetTests.testTheSafetyNumbersKeepTheirOrder` |
| 5 | **Arming asks a live question**: a real Accessibility request to the Dock, `K.trustProbeTimeout` (50 ms), on the worker, fresh for `K.trustFreshness` (2 s) and forgotten at every doubt. The cached `AXIsProcessTrusted()` never arms and never creates taps after launch: it was measured saying yes for seconds after the grant had gone | `Platform/Permissions.liveVerdict`; `TapLifecycle` (`forgetTrust`) | `TrustVerdictTests`; `TapLifecycleInvariantTests` 5, 9 |
| 6 | **A watch while armed, and only then**: every `K.armedWatchInterval` (0.5 s) the keyboard is read, not the event stream. It disarms on ⇧ Shift up, on ⌥ Option or ⌃ Control, after `K.armedIdleLimit` (60 s), and when a look's live question goes unanswered. An App Nap activity is held for exactly as long | `ClickGuard.startWatchdog`; `TapLifecycle` `.watchdog` | `TapLifecycleInvariantTests` 2 |
| 7 | **The taps have a thread of their own** (`TapThread`), never the main run loop. **Nothing on it calls Accessibility, reads the cached grant, or waits without a deadline** | `Platform/TapThread.swift`; `ClickGuard` | `TapThreadTests`; `SafetyNetTests.testTheTapsAreServedOnTheirOwnThread`, `testTheTapsThreadNeverAsksAnythingThatCanBlock` |
| 8 | **A held click's budget is kept by whoever waits**: `DeadlineGate.run(budget: K.clickBudget, grace: K.commitGrace)` (0.15 s + 0.1 s once the selection is being set). A worker still busy refuses the next click at once; a click never queues | `Platform/DeadlineGate.swift`; `App/ShiftPickEngine` | `DeadlineGateTests`; `SafetyNetTests.testAClickReachesTheWorkerOnlyThroughTheDeadline` |
| 9 | **Fail safe**: a click is swallowed only after `ticket.commit()` was granted and `FinderAX.select` succeeded. `ticket.finish(swallow: true)` exists once. A release is swallowed only when its own press was (same `mouseEventNumber`) | `App/ShiftClickResolver.shiftClick`; `TapLifecycle.shouldSwallowRelease` | `DeadlineGateTests.testSwallowingWithoutCommittingIsNotHonoured`; `SafetyNetTests.testAClickIsSwallowedOnlyAfterItsSelectionIsSet` |
| 10 | **The grant moving**: `com.apple.accessibility.api` disarms first and asks after (`K.trustRecheckDelays`: 0.25, 1, 3 s); a request refused by name (`apiDisabled`) destroys both taps | `AppDelegate.watchTheGrant`; `TapLifecycle` | `TapLifecycleTests`; `SafetyNetTests.testTheLaunchWatchesTheGrantTheSessionAndASecondCopy` |
| 11 | **Asleep, locked, or another user's session**: suspended (disarmed, nothing arms) until every reason it was away has gone. Reasons are counted and checked against the session itself (`CGSessionCopyCurrentDictionary`), and a ⇧ Shift press while away looks again | `AppDelegate.watchTheSession`, `reconcileAway` | `TapLifecycleTests`; `TapLifecycleInvariantTests` 10 |
| 12 | **The taps go before the grant or the process**: `engine.shutDown()` returns once no tap exists (from any thread after `K.shutDownWait`), and nothing is created after it. It comes before the uninstall's `tccutil`, and first in `applicationWillTerminate`, which every quit reaches through `NSApp.terminate` | `ClickGuard.shutDown`; `SettingsGeneralPage.confirmUninstall`; `AppDelegate` | `SafetyNetTests.testTheUninstallStopsTheTapsBeforeItTakesTheGrant`, `testAQuitTearsTheTapsDownFirst` |
| 13 | **Nothing waits on another process on the main thread, and no new wait is open-ended.** `BoundedWait`, off the main thread, with `K.uninstallStepWait` per uninstall step. `waitUntilExit` runs the caller's run loop and froze the uninstall (`docs/pitfalls.md` 16). The waits without a deadline are known and stay where they are: `TapThread`'s own two, and the update's staging on its own queue | `Platform/BoundedWait.swift`; `Platform/Uninstall.swift` | `BoundedWaitTests`; `SafetyNetTests.testWaitsWithoutADeadlineStayWhereTheyAre` |
| 14 | **One copy at a time.** A second copy leaves before `NSApplication` exists and asks the first for its window (`AppDelegate.openedAgain`). No `.app` is ever left under the repository (`scripts/no-leftovers.sh`) | `App/ShiftPickMain.leaveIfAlreadyRunning` | `SafetyNetTests.testASecondCopyLeavesBeforeItCreatesAnything`; `launch_is_sound` |
| 15 | **Only a button asks for the permission**, and a window shows the grant through `TapLifecycle.Status.showsGrant`, never through the cached answer alone | `Platform/Permissions`; `App/GrantCatalogue` | `SafetyNetTests.testOnlyAButtonAsksForThePermission`, `testWindowsShowTheGrantThroughOneRule` |
| 16 | **A helper that deletes is only pointed at what is provably ShiftPick's own** | `Core/PathRules.swift`, `UninstallPlan`, `UpdateInstallPlan` | `UninstallPlanTests`, `UpdateInstallPlanTests` |
| 17 | **The numbers keep their order**: one Accessibility call cannot spend a click's budget, the longest wait stays far under macOS's own tap timeout, the teardown outwaits one click | `Core/Constants.swift` (`K`) | `SafetyNetTests.testTheSafetyNumbersKeepTheirOrder` |
| 18 | **No build reaches a Mac from failing tests, no release skips the drill, and every install reads its launch back** | `scripts/safety-gates.sh`, called by `release.sh`, `install.sh`, `publish.sh` | the scripts themselves |

## Thoughts that mean stop

| The thought | What it really is |
|---|---|
| "When macOS disables the tap, enable it again so the feature keeps working" | The exact wedge of `docs/pitfalls.md` 13. Net 3. |
| "Arming on ⇧ Shift is fiddly; keep the click tap enabled and decide in the callback" | Removes the first layer: every click on the Mac would wait on this process again. Net 2, and the owner's call. |
| "Check `AXIsProcessTrusted()` before enabling, it is cheap" | It is a cached answer that lies for seconds after a loss, and its refill is a round trip with no timeout. Net 5 and 7. |
| "Do the Accessibility work in the callback, it saves a hop" | The taps' thread never calls Accessibility. Net 7. |
| "Big folders need more time: raise `K.clickBudget`" | The budget is how long the whole Mac's input waits. The order in net 17 is pinned; the value is the owner's call. |
| "Swallow the click now, the selection will be set in a moment" | Fail safe: only after it was set. Net 9. |
| "`waitUntilExit()` is fine here, the tool is quick" | It runs the caller's run loop and has no deadline. Net 13. |
| "My feature needs its own tap, or an `NSEvent` global monitor" | A new tap is a new way to hold up input. Listening goes through the sentinel, swallowing through the click tap, both under `TapLifecycle`. Design it with the owner first. |
| "Post a synthetic click (`CGEvent.post`) to replay it" | ShiftPick posts no event. A posted event goes through every tap on the Mac, this one included. Design it with the owner first. |
| "Let ⇧ Shift clicks work in other apps too" | The process check is what keeps ShiftPick out of everybody else's controls (`docs/functional.md` §4). |
| "This test is in the way of the refactor; loosen it" | Move it with the code; loosening it is the owner's call. |
| "I will check the revocation myself with `tccutil` or the switch" | **Never.** The owner walks the drill, behind the dead-man's switch. |
| "An ad-hoc build is quicker to try this" | It changes the code identity and loses the owner's grant. Ask first (`CLAUDE.md`, Rules). |

## Changing code near a net

1. **Find the layer.** When a tap may be enabled, created or destroyed is `Core/TapLifecycle.swift` and
   nowhere else: a new way for its state to move is a new `Event`, its scenario in `TapLifecycleTests`, and a
   line in `TapLifecycleInvariantTests`' generator. `ClickGuard` executes effects and decides nothing.
2. **A new net gets a check.** Something that must stay true and that no test can run goes in
   `SafetyNetTests`, with a failure message naming the rule and the document. **Prove the check fails**: in a
   copy of the repository under the scratchpad (never in the tree you commit), make the smallest change that
   compiles and removes the net, and run `swift test --filter SafetyNetTests` there.
3. **Update `docs/functional.md` §0** when a guarantee changes, in the same commit, after the owner said so.
4. **Verify**: `swift build`, then `swift test`, and count **two** summary lines. `SafetyNetTests`,
   `TapLifecycleTests` and `TapLifecycleInvariantTests` among them.
5. **On a real Mac**, with the owner: `make install` reads the launch back from the log and fails on a tap
   taken away, a refusal, an open breaker or a second copy. Then `docs/manual-test-checklist.md` §9: the
   watching steps first, then the drill, which **the owner** walks behind `sh scripts/drill.sh`.
6. **A release** (`make release`) refuses while a file of `SAFETY_FILES` (`scripts/safety-gates.sh`) differs
   from the last release, until the owner says `DRILL=walked` or `DRILL=waived`. Never set either yourself.

## Reading it on the Mac

```sh
/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug
```

| A line | Means |
|---|---|
| `listening for ⇧ Shift clicks` | the taps exist, the click tap disabled |
| `armed` / `disarmed` (debug) | ⇧ Shift went down and up; every press and release pairs up. The app's own disable, heard back as "user input", logs nothing |
| `disarmed: macOS disabled the click tap for user input` | macOS turned the armed tap off itself; disarmed, and never counted |
| `macOS took the click tap away (timeout), n of 3` | a click the window server waited on. **Worth a look every time**; never followed by an enable |
| `macOS took the … tap away … 3 times …; both taps destroyed` | the breaker is open, until the switch is turned off and on |
| `the Accessibility grant is gone (…); both taps destroyed` | the loss was heard and acted on |
| `stopped listening; no event tap exists` | `engine.shutDown()` ran: quit, uninstall |

## What an agent never does

- Takes the Accessibility grant away, runs `tccutil`, or creates an event tap from a shell, a script or a
  test, on this Mac or any other.
- Reproduces the wedge, or walks the drill: the drill is the owner's, behind the switch.
- Builds ad hoc, installs, or publishes without the owner asking (`CLAUDE.md`, Rules), or sets `DRILL`.
- Removes, loosens or skips a net, a check that pins one, or a gate in the scripts, without the owner's
  words for that net.
