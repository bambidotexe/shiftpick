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

## The event tap

- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, …)`,
  subscribed to `leftMouseDown` and `leftMouseUp` and nothing else. **`.defaultTap`, not `.listenOnly`**:
  swallowing the click is the whole point, and a listening tap cannot.
- Creating it needs the Accessibility grant. When the grant is missing, `tapCreate` returns nil, which is
  the only signal there is; the app says so on the System page rather than going quiet.
- The callback runs on the **main run loop**, because that is where the source is added. It holds up every
  click on the Mac while it runs.
- The system disables a tap for two reasons, `tapDisabledByTimeout` (this app held the callback too long,
  which is a bug here) and `tapDisabledByUserInput` (the system interrupting, which is nobody's bug). Both
  are re-enabled at once and logged apart, with a count: a line that could not tell them apart sends a
  reader looking in the wrong place.
- **The callback recovers `self` from an unretained pointer**, so a tap left running would outlive the
  object and dereference freed memory. `MouseTap` disables, removes and invalidates in `deinit`.

## Coordinates

There is only one space in this app. `CGEvent.location`, `AXPosition`, `AXSize` and `AXFrame` are all
**screen points with the origin at the top-left of the primary display and y downwards**. Nothing is
converted anywhere, and no Cocoa rectangle ever reaches the click path.

## The permission

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
  database changes. It is how a grant given or taken away reaches a running app with no timer at all. It
  can arrive a moment before the process is really trusted, which is why the onboarding wizard also polls
  every `K.onboardingPollInterval` while it is up, and only while it is up. That poll is the app's only one:
  its tick refreshes the wizard's rows **and** tells the app, so there is no second timer on the same grant.
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
  back to "not asked yet". Dropping this app's entry and restarting the two daemons does.
