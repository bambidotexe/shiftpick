# ShiftPick — the platform boundary

What this app relies on macOS to do, and what was measured rather than assumed. **Read this before
designing on a platform assumption.**

Everything below was read on **macOS 27.0 (build 26A428)**, on a 1512 × 982 display, with `swift run
axdump` and with the throwaway probes that became it.

---

## Finder's icon views, as Accessibility describes them

**None of this is documented, and none of it was guessed.** `Sources/ShiftPickPlatform/FinderAX.swift` is
the only file allowed to know it. `swift run axdump views` prints it again at any time.

### A window

```
AXWindow / AXStandardWindow   id=FinderWindow
 └ AXSplitGroup … AXSplitGroup
     └ AXScrollArea                              id=_NS:23
         └ AXList / AXCollectionList             id=IconView       ← the container
             └ AXList / AXSectionList                              ← one per group
                 ├ AXStaticText  or  AXGroup                       ← the group's header
                 └ AXGroup       id=<file name>, AXIndex           ← an item
                     └ AXImage   AXURL, AXFilename, AXTitle, AXSelected
```

A real dump, of a folder of fourteen files with *Use Groups* off:

```
AXScrollArea/- id=_NS:23 (511,229 705x348)
  AXList/AXCollectionList desc=présentation par icônes id=IconView (511,229 705x366)
    AXList/AXSectionList (518,249 228x344)
      AXGroup/- id=a-folder (542,253 64x64)
      AXGroup/- id=a-file-with-a-rather-long-name-that-wraps.txt (658,253 64x64)
      AXGroup/- id=file-01.txt (773,253 64x64)
      …
```

And the same folder with *Use Groups* on, which is the only thing that changes the shape:

```
  section[0] AXList/AXSectionList (511,229 705x154)
     child[0] AXStaticText/-                        (511,229 705x32)   ← the header
     child[1] AXGroup/- id=sub2                     (539,275 64x64)
     child[2] AXGroup/- id=sub1                     (653,275 64x64)
  section[1] AXList/AXSectionList (511,385 705x154)
     child[0] AXGroup/-                             (511,385 705x32)   ← a header can be an AXGroup too
     child[1] AXGroup/- id=file-05.txt              (539,431 64x64)
```

### The Desktop

Not a window. A **direct child of the application**, and its items are the images themselves:

```
AXApplication (Finder)
 └ AXScrollArea / AXDesktop          desc=bureau
     └ AXGroup / AXDesktop           AXIsDesktop, AXSelectedChildren   ← the container
         └ AXImage                   AXURL, AXFilename, AXTitle, AXSelected
```

### The five facts the code leans on

1. **An item's frame is the icon's own box, never the cell and never the label.** A file called
   `file-01.txt` and one called `a-file-with-a-rather-long-name-that-wraps.txt`, side by side, both report
   `64 × 64` at the same `y`, although the second one's name wraps to two lines. That is what makes the
   centre of the frame a stable reference point. The Desktop's icons report `72 × 72` at the icon size the
   Desktop was set to.
2. **A hit test over an item's label still answers with the item's `AXImage`.** Finder's hit region covers
   the label; only its *frame* does not. So the point ShiftPick decides from is exactly the point Finder
   would have acted on. A gap between two icons answers with the `AXSectionList`; the space under the last
   row answers with the `AXCollectionList`.
3. **Selection is one attribute on the container.** `AXSelectedChildren` on the `AXCollectionList`, set
   with the **`AXGroup`** items; on the Desktop's `AXGroup / AXDesktop`, set with the **`AXImage`** items.
   One call sets a range of any size. Elements compare across reads with `CFEqual`, and `CFHash` is
   distinct per element, which is how a selection read back is mapped to items and how the anchor is found
   again.
4. **A collapsed Desktop stack is an `AXImage` with no `AXURL`.** It has an `AXFilename` and an
   `AXTitle` (the group's name) and its `AXRoleDescription` says "Stack", but that sentence is translated.
   The missing URL is not.
5. **`AXIndex` on an item is its position inside its section**, and it is the order the view draws them in;
   a group's header takes index 0 when there is one. It is used as evidence about the fill direction and
   never as the answer, because a view with one row of icons has an `AXIndex` and no direction at all.

### An Open or Save panel is the same shape

An AppKit file panel shown as icons answers with Finder's hierarchy, identifier for identifier, although it
belongs to whichever application put it up:

```
AXWindow / AXDialog    AXIdentifier=open-panel        ← what recognises it
 └ AXSplitGroup … AXScrollArea                 id=_NS:23
     └ AXList / AXCollectionList  desc="icon view"  id=IconView
         └ AXList / AXSectionList  desc="Folders"
             ├ AXStaticText                         ← the group's header
             └ AXGroup  id=<file name>
                 └ AXImage
```

`AXSelectedChildren` on that collection list is settable and takes a range of any size, exactly as
Finder's does. **And the panel has the same gap**: measured, its own ⇧ Shift click selected the first and
the third icon of a row and left the second alone.

The two identifiers are `open-panel` and `save-panel`. They are AppKit's and are not translated, unlike the
role descriptions beside them.

### What Finder does **not** give you

- **Only the icons that are on screen exist.** A folder of 2,500 files answers with 24 to 30. See
  `pitfalls.md`.
- `AXRowCount` and `AXColumnCount` on the `AXCollectionList` both answer **1**, whatever is in it. They
  describe the list of sections, not the grid.
- `AXEnhancedUserInterface` cannot be set on Finder (`-25208`). It is not a way to make the whole list
  appear.
- A window element's `AXRole` can read as `AXApplication` for a moment after Finder relaunches. Walk **up**
  from a hit test; never index into the application's children.

## The event taps

- **A listening tap and a tap that can swallow are different animals.** `CGEvent.tapCreate(… options:
  .listenOnly …)` is handed a copy of each event and the window server does not wait for it. `options:
  .defaultTap` puts the tap **in the path of the event**: the window server waits for the callback's answer,
  and nothing behind that event is delivered until it has it, the keyboard included. Swallowing a click needs
  the second kind. Nothing else in the app does.
- **An enabled `.defaultTap` whose owner loses the Accessibility grant stalls the Mac.** Measured here, and
  reported the same way by others on macOS 15, 26 and 27: the callback is no longer run, the clicks are still
  routed into the tap, and each one holds the whole session's input until the system's own timeout disables
  the tap and sends `tapDisabledByTimeout`. **That pseudo-event still reaches the callback.** Enable the tap
  again from there and the next click stalls the same way, for ever; `pitfalls.md` 13 has the log. A
  `.listenOnly` tap under the same revocation holds nothing up.
- So ShiftPick holds **two taps, both `.cgSessionEventTap`, `.headInsertEventTap`**: a `.listenOnly` sentinel
  on `flagsChanged` and `leftMouseDown`, always on; and a `.defaultTap` on `leftMouseDown` and `leftMouseUp`
  that is **created disabled and enabled only while ⇧ Shift is held**. A tap is born enabled, so the click
  tap is disabled in the line after it is created, before its source is on any run loop.
- **A listening tap on `flagsChanged` needs no second permission**: the Accessibility grant covers it, which
  is how `snappy-snap` has always run the same tap. A tap that listens to the keyboard, asked for without the
  grant, is reported to make macOS offer Input Monitoring instead, and that is a prompt this app never wants
  on screen. **So both taps are only created on a live answer**, the launch apart: the cached answer is the
  one that goes on saying yes after the grant has gone, which is exactly when a tap would be asked for
  without it.
- **Blocks handed to a run loop from inside a Mach-port callback run before the next port message is
  served.** Measured on macOS 27 with plain Mach ports, both messages already queued: 600 rounds on one port
  and on two, no exception, blocks queued by blocks included. It is what lets a tap's callback answer the
  event in hand first and change the tap's state afterwards, with nothing heard in between.
- **An accessory app with no window on screen is one macOS may nap, and a napped process has its timers put
  off.** `ClickGuard` holds a `latencyCritical` activity for exactly as long as the click tap is enabled,
  which is the one stretch in which a timer of this app matters to anybody else.
- Creating them needs the Accessibility grant. When it is missing, `tapCreate` returns nil, which is the
  only signal there is; the app says so on the System page rather than going quiet.
- The callbacks run on **a thread of their own** (`TapThread`), because a tap is answered by whichever run
  loop its source was added to, and on the main run loop every stall of the interface is a stall of the mouse.
- The callback is told a tap was disabled for one of two reasons, and **neither is ever answered by enabling
  the tap**. `tapDisabledByTimeout`: the callback was not answered in time, a bug here or a grant that has
  gone. `tapDisabledByUserInput`: **also what a tap is told when its own app disables it.** The SDK's
  `CGEventTapEnable` says so ("if … a user requests taps be disabled, an appropriate `kCGEventTapDisabled…`
  event is passed to the registered `CGEventTapCallBack`"), the user there being the program calling it, and
  the first install measured it: one is delivered for **every** `CGEventTapEnable(tap, false)`, even on a tap
  that is already disabled. So only timeouts are counted (`pitfalls.md` 15).
- **Whether `CGEvent.tapIsEnabled` answers for an enable made a moment before is not known.** It is asked
  once after every enable of the click tap and a `false` is only logged (`the click tap did not take the
  enable`), never acted on: the live question about the grant already covers the one case where it would
  matter.
- **`CGEventSource.flagsState(.hidSystemState)` is the keyboard as the hardware sees it**, and it goes on
  being right while the event stream is stalled, which is exactly when a key's release would never be heard.
  `.combinedSessionState` also counts keys pressed by another Mac through a sharing tool, which never reach
  the hardware state. The watch kept while armed believes either.
- **A press and its release carry the same `mouseEventNumber`**, which is how the release of a swallowed
  press is recognised and nobody else's is.
- **The callbacks recover `self` from an unretained pointer**, so a tap left running would outlive the
  object and call into freed memory. `ClickGuard` disables and invalidates both in `deinit`, and
  `CGEvent.tapEnable` and `CFMachPortInvalidate` are honoured from any thread.
- **A process that dies takes its taps with it**, however it dies: the ports are the kernel's to clean up.
  Nothing ShiftPick does to the event stream outlives its process, and it changes nothing persistent that a
  crash could leave behind.

## Coordinates

There is only one space in this app. `CGEvent.location`, `AXPosition`, `AXSize` and `AXFrame` are all
**screen points with the origin at the top-left of the primary display and y downwards**. Nothing is
converted anywhere, and no Cocoa rectangle ever reaches the click path.

## The permission

- **`AXIsProcessTrusted()` is an answer the system keeps for the process, not a live one.** Measured on
  macOS 27: the first call in a process is a 13.7 ms round trip to `tccd` with no timeout, and the next 2,000
  average 0.68 µs, a read of something already in the process. **So it is never called on the thread that
  serves the taps**: the call that refills that cache comes around a change to the privacy database, which is
  exactly when the grant is moving. It is right at launch. It lags the notification that says the grant moved, and it has been reported to go on saying yes
  after the grant was taken away, above all when the app is removed from the list with the minus button
  rather than switched off. Windows may show it; **nothing that enables an event tap relies on it alone.**
- **A real request is refused the moment the grant is gone**: any Accessibility call comes back
  `kAXErrorAPIDisabled`. That is the live question (`Permissions.liveVerdict`): one attribute asked of the
  Dock, which is always running and answers in well under a millisecond, with a 50 ms timeout. A timeout says
  nothing either way and is never read as a revocation. Every call the click path makes is a witness as
  well: `AX.refusalCount` moves when one is refused.
- `AXIsProcessTrusted()` answers whether this process may ask anything, and shows nothing, which is why it
  may run behind a poll. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` shows the
  system's own dialog. **They are two calls and they are never swapped**: the second returns the current
  state too, which makes it tempting as the reader, and behind a two second poll that is a permission prompt
  every two seconds. Only the onboarding wizard's button calls it, never the start-up path.
- **The pane no longer calls it Accessibility.** `SecurityPrivacyExtension.appex`'s own
  `Localizable.loctable` answers `ACCESSIBILITY` with **Device Control and Data Access** (fr: *Contrôle de
  l’appareil et accès aux données*) on macOS 27, and no key in that table answers "Accessibility" any more,
  although the API, the system's own dialog and everything written about it still do. Read it again after a
  macOS release, because the wizard's row and the System page's warning quote it word for word:

  ```bash
  F=/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable
  plutil -extract en xml1 -o - "$F" | grep -A1 '<key>ACCESSIBILITY</key>'
  plutil -extract fr xml1 -o - "$F" | grep -A1 '<key>ACCESSIBILITY</key>'
  ```
- **The grant is per code identity.** A stable Developer ID signature keeps it across reinstalls; an ad-hoc
  signature gives the app a new identity on every build and loses it every time. That is why an ad-hoc
  build is never installed.
- **`com.apple.accessibility.api`** is posted on the *distributed* notification centre when the privacy
  database changes. It is how a grant given or taken away reaches a running app with no timer at all, **and
  it is a hint, never an answer**: it is posted for any application's grant, it can arrive before
  `AXIsProcessTrusted()` changes, and removing an application with the minus button has been reported to
  post nothing. So hearing it disarms the click tap first, asks the live question, and looks again
  `K.trustRecheckDelays` later; a handler that reads the grant once and leaves is how a revocation goes
  unnoticed. The onboarding wizard also polls every `K.onboardingPollInterval` while it is up, and only while
  it is up: its tick refreshes the wizard's rows **and** tells the app.
- **`tccutil reset Accessibility <bundle id>` is a revocation this app performs on itself**, in its
  uninstall. Whether it reaches the running process at once or only the next launch has **not been measured
  here**, and others report both; the uninstall does not find out, because it destroys both taps first.
- A **command-line tool inherits the Accessibility grant of the terminal that starts it**, which is why
  `Tools/axdump` can read Finder long before the app is allowed to.

## Windows

- An accessory app (`LSUIElement`) **is not brought forward by the cooperative `NSApp.activate()`**:
  measured on macOS 27, it left the window behind the one it opened over with the process not frontmost.
  Every window this app shows uses `activate(ignoringOtherApps: true)` **to open**, and nothing but that:
  once a window is up, coming back to the front is `makeKeyAndOrderFront` alone. Activating after a button
  has handed the user over to System Settings is what drops a window on top of the pane it just opened.
- **macOS gives an ordinary app the front back when the app it handed over to quits, and skips `LSUIElement`
  apps doing so.** There is no flag for it. The onboarding wizard therefore watches for System Settings
  quitting itself (`FocusReturnWatch`), and the wait is bounded so that an unrelated visit there an hour
  later does not pull the window forward out of nowhere.
- An accessory app with **no window left is still the active application**, which sends the user's
  keystrokes nowhere. Every window hands activation back on close *and* on miniaturise, which never fires
  `windowWillClose`.
- ⌘Q and ⌘W reach a window only through `NSApplication.mainMenu`, so the app installs a main menu nobody
  ever sees.
- A `MenuBarExtra` scene cannot be added and removed as a setting changes: it re-reads `isInserted` only
  when SwiftUI re-evaluates the scene. The status item is `NSStatusItem`, released back to
  `NSStatusBar.system` to hide it, because an item merely hidden keeps its slot.

## Launch, login and reinstall

- **Launch at login** is `SMAppService.mainApp`. Its state lives there and nowhere else: the user can remove
  the app in System Settings without opening it, so a copy kept in the settings file could only disagree.
- **A login-item launch** is told from a person's by the open-application Apple event: it carries
  `keyAELaunchedAsLogInItem` under `keyAEPropData`. An event that cannot be recognised reads as a person,
  which is the safe way round.
- **A reinstall is not a person asking for a window.** `scripts/install.sh` writes a marker before anything
  can start the app, and the first launch that finds it opens nothing (`Core/QuietLaunch`). It lapses after
  two minutes, so one left behind by an install that died cannot silence a launch by hand.

## The uninstall

- `tccutil reset Accessibility <bundle id>` gives the grant back, and it has to run **while the bundle it
  names still exists**. It exits non-zero when it had nothing to reset as well as when it failed, so the
  sentence the user reads names where to look either way.
- **`cfprefsd` writes a preferences domain back out as the process exits, whatever happens.** Removing the
  plist from inside the app leaves an empty one where a Mac that never had the app has no file at all. The
  removal goes to a detached helper that waits for the pid.
- Notification authorization lives in `group.com.apple.usernoted`'s preferences, and no public API puts it
  back to "not asked yet". **ShiftPick leaves it there.** The way around is to rewrite that file, which
  belongs to a system daemon and holds every app's answer, and to kill `usernoted` and `NotificationCenter`
  so that they read it again: a risk to the whole Mac's notification settings taken for the sake of one
  prompt. A reinstall inherits the old answer.
