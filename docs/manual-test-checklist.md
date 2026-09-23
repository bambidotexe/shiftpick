# ShiftPick — what only a person can see

`ShiftPickApp` has no automated tests. This is its verification. Work down it after any change to the click
path, and note anything that surprises you in `docs/pitfalls.md`.

**§9 is owed after any change to a file of the safety layer** (`SAFETY_FILES` in `scripts/safety-gates.sh`),
on an installed build of that tree and before it is published: `make release` refuses until the owner says
`DRILL=walked` or `DRILL=waived`. Its watching steps are anybody's; **its drill is the owner's alone.**

Two things make it quicker:

```sh
swift run axdump views             # every icon view on screen, its items in reading order, and how it was classified
swift run axdump range <x> <y>     # what a ⇧ Shift click there WOULD select, printed rather than done
swift run axdump range <x> <y> <ax> <ay>   # the same, measured from the icon at ax ay
/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug
```

`axdump range` is the one to reach for first when a selection is not what you expected: it says whether the
layout was read as arranged or hand-placed and how many grids and scatters it holds, what the click is
measured from and whether that was the anchor or a stand-in, whether the range is a slice of the reading
order or the rubber band, and the selection the click would leave, with the icons it keeps marked — all
without touching anything.

---

## 1. The gesture

- [ ] A folder in icon view. Click a file, ⇧ Shift click another **further on**: everything between the two
      is selected, both ends included.
- [ ] ⇧ Shift click a file **before** the first one: the range runs the other way, from the same first file.
- [ ] ⇧ Shift click again, nearer: the range **shrinks**, still measured from the same first file.
- [ ] ⌘ Command click a file elsewhere, then ⇧ Shift click further on: the first range stays, and the new one
      runs from the ⌘ Command clicked file. ⇧ Shift click back inside the new range: it narrows and the first
      range still stays. ⌘ Command ⇧ Shift click: Finder toggles the one file, as in a list view.
- [ ] ⌘ Command click a file inside a range to deselect it, then ⇧ Shift click further on: the range runs
      from the first selected file after the deselected one, which stays deselected.
- [ ] Nothing selected, view at the top: ⇧ Shift click selects from the first file. Scroll down first: the
      click goes to Finder and `log stream --level debug` says `nothing selected, and the first icon may be
      off screen`.
- [ ] ⌘ Command click **empty space** in an icon view: write down whether Finder deselects everything, which
      is not measured. Either way the anchor is cleared, so the next ⇧ Shift click is measured from what is
      selected then and never from the file clicked before it.

## 2. Where it works

- [ ] **Sort By Name, Kind, Date Added, Date Modified, Size, Tags.** In each: a range across a row, a range
      spanning several rows. `axdump views` should say `arranged(rowsFromLeft)` for all of them.
- [ ] **View › Use Groups on.** A range **inside** one group. A range that **crosses** two groups: it holds
      the end of the first, all of the second up to the target, and nothing from a group above or below.
- [ ] **View › Sort By › None**, icons dragged into a rough grid by hand: `axdump views` says
      `handPlaced(grids: 1, scatters: 0)`, and a range reads along the rows, the first icon of one row
      following the last of the row above. Drag two groups apart, an empty column between them: two grids,
      and a ⇧ Shift click from one into the other draws the **rubber band** between the two icons — the
      rectangle they span, icons inside it selected and icons outside it not, whatever their name.
- [ ] The same folder with **one icon dragged well off every line** of its group: `scatters: 1`, and every
      range in that group is the rubber band. Icons dragged into no pattern at all: the same, with no grid
      anywhere.
- [ ] A hand-placed view with **nothing selected**: the ⇧ Shift click is measured from the **first cluster's
      first icon**, so a target in another cluster gets the rubber band from there rather than a run of any
      row. `axdump range <x> <y>` says which it was before you commit to it.
- [ ] A **search result** window, **Recents**, a **tag**, **iCloud Drive**. Each in icon view.
- [ ] A window in **list, column and gallery** view: ⇧ Shift does what it always did, and the `click` log
      says nothing at all.

## 3. The Desktop

- [ ] Desktop **sorted** (View › Sort By › Name, with the Desktop frontmost). A range down one column. A
      range that **runs off the bottom of one column and into the next one to its left**: that is the order
      the Desktop fills, and it is what the range must follow.
- [ ] Desktop **hand-placed** (Sort By None), icons tidied into rough rows: `axdump views` says
      `handPlaced(grids: 1, scatters: 0)` and a range reads along the rows. Drag a group off on its own: two
      grids, and a range from one into the other is the **rubber band**. Scatter a group with no pattern at
      all: `scatters: 1`, and every range in it is the rubber band.
- [ ] Desktop with **Use Stacks on**. ⇧ Shift click a stack: nothing happens and the click reaches Finder
      (the stack toggles as it always did). A range **across** a stack: the files are selected and the
      stack is not.
- [ ] **⇧ Shift click a Desktop icon while another app is frontmost.** The range is selected **and Finder
      comes forward**, which is what the click would have done.

## 4. Windows and focus

- [ ] Two Finder windows. Set an anchor in one, ⇧ Shift click in the **other**: the second window's own
      selection is what the range is measured from, not the first window's anchor. Each window keeps its
      own anchor: go back to the first and ⇧ Shift click; the original anchor is still the one used.
- [ ] A **background** Finder window, another app in front. ⇧ Shift click a file in it: the range is
      selected, **Finder comes forward and that window is raised**.
- [ ] A Finder window **behind another app's window**. ⇧ Shift click a point where the other app covers
      Finder: the other app gets the click. What is under the cursor decides, not which app is frontmost.

## 5. Open and Save panels

- [ ] In any app, **File › Open** (or ⌘O), switch the panel to **icons** with the view button in its
      toolbar, and go to a folder with several files. Click one, ⇧ Shift click another: the range is
      selected, exactly as in Finder.
- [ ] A **Save** panel shown as icons, with its name field focused as it always is: a ⇧ Shift click still
      selects a range. (The rename check is deliberately not made for panels.)
- [ ] The **application that owns the panel stays frontmost**. Finder must not come forward.
- [ ] A panel that asks for **one** file: ⇧ Shift does whatever that panel does. ShiftPick sets a range and
      the panel keeps one of it; nothing breaks.
- [ ] A collection view in **any other application** (a photo grid, a file browser that is not a panel):
      ShiftPick must do nothing at all. Only `open-panel` and `save-panel` get past the process check.

## 6. The clicks it must not take

- [ ] ⇧ Shift click the **gap between two icons**, a **group's header**, the **space under the last row**:
      Finder deselects, as it always did.
- [ ] ⇧ Shift click during an **inline rename** (select a file, press Return, then ⇧ Shift click its icon):
      the click belongs to the text field. Press ⎋ Escape.
- [ ] **⌥ Option ⇧ Shift** and **⌃ Control ⇧ Shift** clicks: Finder's.
- [ ] ⇧ Shift click in the **sidebar**, the **toolbar**, the **path bar**, another **application**.
- [ ] A plain click on empty space, then ⇧ Shift click a file: the empty click cleared the selection and the
      anchor, so with the window at the top the range runs **from the first file in the view**, and with the
      window scrolled the click goes to Finder (§1).

## 7. The edges

- [ ] A **2,000+ item folder**. Two files both on screen: the range is right. Now click one, **scroll three
      screens**, ⇧ Shift click another: **the click goes to Finder untouched** and only that one file is
      added. `log stream --level debug` says `let through: nothing selected, and the first icon may be off
      screen` — the file clicked first is still selected, but Finder no longer names it among the icons on
      screen. That is the known limit, not a bug (`docs/pitfalls.md` 1).
- [ ] A folder with **one file**. ⇧ Shift click it: it is selected, nothing else happens.
- [ ] A folder with **one row** of files, and one with **one column**.
- [ ] Files whose names wrap to **two lines** beside files whose names do not: the range does not skip or
      include a row it should not.
- [ ] A window **resized** so the columns re-flow, mid-session: the next range follows the new layout.

## 8. The permission and the onboarding wizard

The wizard has no automated test at all. Walk the whole of it, and `~/.claude/skills/macos-building-onboarding`'s own
checklist with it.

**What it looks like**

- [ ] **First launch.** Four pages, each stepped by the one button at the bottom right: the pitch with the
      icon, the blue accent on one word and the three capsules; **Permission**; **Where it lives**;
      **All set**. Nothing is cut off, nothing is truncated, every sentence wraps.
- [ ] The height follows the page around its **top-left** corner: the title bar does not move, the bottom
      edge does. No page is stretched or crowded.
- [ ] The button reads **Skip** on page 2 until the permission is granted, and on page 3 until either row is
      on. It turns to **Continue** without the page being redrawn: the header and the other row do not move.
- [ ] **Press it after a row has changed.** On page 2, press **Skip** before granting: it advances. Come back,
      grant the permission, and press **Continue** **without closing the window**: it advances on the **first**
      click. Same on page 3 after turning a row on. A button that does nothing here is `docs/pitfalls.md` 11,
      whatever it looks like: `swift run axdump at <x> <y>` over it finds the window rather than the button,
      and the `onboarding` log category at `--level debug` says `DOES NOT CONTAIN`.
- [ ] Return presses the button on every page.
- [ ] The whole wizard in **French** and in **English**, and the two quoted names word for word against
      System Settings: *Device Control and Data Access* in Privacy & Security, *Open at Login* in Login Items
      & Extensions.

**The permission**

- [ ] **No prompt appears by itself, ever.** Launch with the permission missing and leave the wizard open for
      a minute: no dialog. Reach *All set* having granted nothing, Finish, quit, and launch twice more: still
      none. Every prompt in the whole walk followed a click of yours.
- [ ] Press **Allow…**: **only** the system's dialog, never System Settings alongside it. Refuse it, then
      press again: nothing new opens, and the button does not change its name.
- [ ] Grant Accessibility in System Settings **without touching the app**: within about two seconds the row
      reads *Granted*, the button turns to *Continue*, **the wizard stays open**, the menu's status line reads
      *Watching for ⇧ Shift clicks*, and the very next ⇧ Shift click is a range. **No relaunch.**
- [ ] **Taking the grant away while the app runs is §9, and only §9.** It is the one thing that has ever
      cost this Mac its mouse and keyboard, so it is never tried without the dead-man's switch that section
      starts first.
- [ ] Settings › System while all of that happens: the row follows within two seconds, and the button and the
      warning appear and disappear with it. Settings › Health too: *Accessibility permission* turns green, and
      *Watching for ⇧ Shift clicks* appears under it, green.

**Where it lives**

- [ ] **Turn On** beside *Open at Login*: the row reads *Enabled* and offers *Turn Off*, and the app is in
      System Settings › General › Login Items under *Open at Login*. Turn it off again: both agree.
- [ ] **Show in menu bar**: *Turn Off* takes the icon away and the row offers *Turn On*; Settings › General
      agrees with it.

**Who is in front**

- [ ] The wizard opens in front. Click another app's window: it goes behind and **stays** there. Switch to
      another Space and back: still in front of what it was in front of.
- [ ] Press **Allow…**, then use the system dialog's own button to open System Settings: the pane comes
      forward and **stays**. Grant it with the pane still open: the row ticks over with the wizard still
      behind.
- [ ] **Close the System Settings window**: the wizard comes back in front of what it was in front of. Leave
      it open and click another app instead: the wizard does not move.
- [ ] `open -b dev.rubens.ShiftPick` brings the wizard forward, not Settings. Open Settings as well
      (⌘, from the menu-bar item), then activate the app: **Settings** comes forward, not the wizard.
- [ ] Closing the wizard gives the front back to whoever had it, and keystrokes go to that app. Closing it
      with Settings still open leaves the app active.

**When it opens**

- [ ] Finish it once, quit, launch again by hand: **no wizard**, the Settings window instead. Open the app
      again while it runs: the Settings window, not the wizard.
- [ ] Close it with the × **before** *All set*, quit, launch again: the wizard is back, at page one. Close it
      again and open the app from the Applications folder while it still runs: the wizard, not Settings.
- [ ] **Settings › System › Start over**: a fresh wizard at page one, with every row re-read.
- [ ] **Launch at login** on, wizard never finished, log out and in: the app starts and **opens no window**.
- [ ] `make install` over a running copy: no window, wizard included.

## 9. The taps, and the safety drill

**Watching it work** costs nothing and risks nothing. With the log streaming at `debug`:

- [ ] Press and release ⇧ Shift in any app, hands off the mouse: `armed`, then `disarmed`, and **no `macOS
      took the click tap away` line at all**: the disarm's own disable comes back as "user input" and is not
      one. **Nothing is armed while the key is up**, which is the whole of the safety model's first layer.
      Write down whether `the click tap did not take the enable` appears after `armed`, and whether the
      ⇧ Shift click that follows still selects a range: together they say whether `tapIsEnabled` answers
      for an enable made a moment before, which is measured nowhere else.
- [ ] Hold ⇧ Shift with ⌥ Option or ⌃ Control: nothing is armed. Hold ⇧ Shift alone, then add ⌥ Option:
      `disarmed`. Let go of ⌥ Option with ⇧ Shift still down: `armed`.
- [ ] **Breaker open**, after the drill's three timeouts: Settings › System shows the *Click listener* row
      red *Stopped* with the warning under it and **Start Listening Again** beneath that. Press it: the log
      says `another try was asked for` and then `listening for ⇧ Shift`, the button and the warning go, and
      the row turns green.
- [ ] Hold ⇧ Shift for more than a minute without clicking: `disarmed: ⇧ Shift held with nothing clicked`.
      Press it again: `armed`.
- [ ] ⇧ Shift click a file, let go of ⇧ Shift **before** the mouse button, then let go of the button: the
      range stays exactly as it was set, and `disarmed` comes after the release.
- [ ] Close the lid for a minute and open it, lock the screen and unlock it: an `away (asleep)` and an
      `away (locked)` line when the lid closes, in either order, and **one line ending `nothing is away any
      more`** once the screen is unlocked, never before. **Walk the way back in both orders**: unlock the
      moment the lock screen shows (the unlock notice arrives first and one `back (locked)` line clears
      both), and open the lid, wait five seconds on the lock screen, then unlock (`back (asleep); still away:
      locked`, then `back (locked); nothing is away any more`). The second order once left ShiftPick
      suspended for good with every window saying it was listening (`docs/pitfalls.md` 17). With the lid
      closed and the Mac kept awake by KoffeeLid, quitting and reopening KoffeeLid walks the second order
      without touching the lid. The first ⇧ Shift click after either is a range, and no `macOS took the …
      tap away` line appears.
- [ ] Open a second copy (`open -n /Applications/ShiftPick.app`): it leaves at once with `already running as
      pid …; this copy leaves and asks it for its window`, the first copy logs `a second copy asked for the
      window`, and its Settings window comes forward.
- [ ] Hold a ⇧ Shift click while the Mac is busy: the click is either a range or Finder's, never nothing, and
      never late by more than a quarter of a second.
- [ ] Leave the app running for a day. A `macOS took the click tap away` line is worth a look whenever it
      appears; what matters is that **no line ever says a tap was enabled again because of one**, and that a
      range still works at the next ⇧ Shift press.

### The drill

**Read `docs/pitfalls.md` 13 first.** This takes the Accessibility grant away from a running ShiftPick on
purpose. **Never without the switch**:

```sh
sh scripts/drill.sh        # kills ShiftPick 30 s from now, whatever happens, then follows its log
```

A process that dies takes its event taps with it, so the worst any step below can cost is thirty seconds of a
Mac that ignores you. If that happens: **hands off, wait for the switch, and write down which step it was and
what the log said last.** The switch always fires, so open the app again between steps, check that a
⇧ Shift click selects a range, and start the switch again.

**Start the switch last, right before the step.** It is aimed at the copy running when it starts, and fires
once: a copy opened after it has none, and the switch in the first walk ran out while the app was being
reopened, so two steps were walked unguarded. A step that needs Touch ID or a password may need longer:
`sh scripts/drill.sh 60`.

- [ ] **A. The switch turned off, hands off ⇧ Shift.** System Settings › Privacy & Security › *Device Control
      and Data Access*, turn ShiftPick off. **Every click and every key keeps working the whole time.** Within
      about three seconds the log says `the Accessibility grant is gone (…); both taps destroyed`, the wizard
      comes back, and the menu says it is waiting for the permission.
- [ ] **B. The minus button**, same place, with the grant back and the app reopened: select ShiftPick and
      remove it from the list. The same as A. macOS may post no notification for this one: then nothing is
      logged until the next press of ⇧ Shift, which says `a live Accessibility request was refused` and takes
      both taps down. Either is a pass; a Mac that stops answering is not. **The wizard's row reads the grant
      as missing from the moment the log says it is gone**, whatever macOS's own answer still claims, and ticks
      back to *Granted* only once `listening for ⇧ Shift clicks` is logged again. **Then leave the wizard open for
      half a minute and watch the log**: it polls every two seconds, and none of these may appear, because
      nothing is created under a grant that is gone: `would not create the event taps` more than once, a
      status that flaps between listening and not, or a macOS prompt about Input Monitoring.
- [ ] **C. The switch turned off with ⇧ Shift held.** This is the only moment the dangerous tap is enabled.
      Hold ⇧ Shift with one hand, turn ShiftPick off with the other, keep the key down, and ⇧ Shift click a
      file. The worst allowed is **one** click that takes a moment, with `macOS took the click tap away
      (timeout), 1 of 3` in the log and nothing enabled after it. Let go of the key: everything works.
      **It is hard to reach by hand**: turning the switch off takes a click and Touch ID, and in the first walk
      the live question asked at the ⇧ Shift press found the grant gone before anything was enabled. The walk
      has reached the case only when `armed` is logged before the loss line.
- [ ] **D. Uninstall**, with the grant in place: Settings › General › Uninstall, and confirm. `stopped
      listening; no event tap exists` is logged **before** anything else happens, and the last alert's button
      takes your click.
- [ ] **E. Grant it again** after any of them: within about three seconds `listening for ⇧ Shift clicks`, and
      the very next ⇧ Shift click is a range. No relaunch.

What each step did on this Mac goes into `docs/macOS.md`, *The event taps* and *The permission*, as a
measurement: which of the four ways noticed the loss first, how long it took, and whether `tccutil` in step D
reached the running process.

## 10. Updates

Walk the whole thing offline, with a stand-in for GitHub:

```sh
# a release JSON and a disk image on this Mac
cat > /tmp/latest.json <<JSON
{"tag_name": "9.9.9",
 "assets": [{"name": "ShiftPick-9.9.9.dmg",
             "browser_download_url": "file:///tmp/ShiftPick-9.9.9.dmg",
             "size": 0}]}
JSON
SHIFTPICK_UPDATE_FEED=file:///tmp/latest.json /Applications/ShiftPick.app/Contents/MacOS/ShiftPick
```

- [ ] Settings › General › Updates: *Check for Updates* → the row reads **Version 9.9.9 is available** and
      the button becomes **Update**, prominent and blue.
- [ ] The automatic check, twenty seconds after launch, posts **one notification**. Clicking it, or its
      **Update** button, opens the update window.
- [ ] The window: the bytes count up, then *Preparing the update*, then *Ready to install*, and **Install
      and Relaunch** is enabled only then. Cancel closes it and leaves nothing behind in
      `~/Library/Application Support/ShiftPick/updates`.
- [ ] **Install and Relaunch**: the app quits, the new version starts, and the window that opens says *The
      update is installed*. Nothing else opens behind it.
- [ ] With no feed set and no release published: the row says **No release published yet** on a press, and
      an automatic check says nothing at all.

## 11. Uninstall

- [ ] Settings › General › Uninstall → the alert says what will go → Uninstall. **The window never shows a
      spinning wheel**, the button greys out, and the last alert comes within about a second. The log has
      `stopped listening; no event tap exists` first, then one `uninstall: …` line per step with what came back
      and how long it took.
- [ ] Afterwards: no **ShiftPick** in System Settings › Privacy & Security › Accessibility; none in
      General › Login Items; `ls ~/Library/Application\ Support/ShiftPick` and
      `defaults read dev.rubens.ShiftPick` both say nothing is there; the app is **in the Trash**, not
      deleted.

## 12. The rest of the window

- [ ] The toolbar carries **four** pages and no more: General, System, Health, Tip. Every page: nothing is
      cut off, nothing is truncated, and the window's height follows the page around its top-left corner.
      Nothing anywhere in the window is a setting about what ShiftPick does.
- [ ] **Settings › System**, the *Click listener* group, in each state it can reach. Everything in place:
      one green row, *Enabled*, with no warning and no button. macOS having refused the listener: red
      *Failed*, the Health page's refused fix sentence as the warning, and **no** button, because the fix is
      the Accessibility group's own button above. The breaker open: red *Stopped*, the stopped warning, and
      the **Start Listening Again** button (§9). The permission missing: no group at all, the Accessibility
      row saying it instead.
- [ ] **Launch at login** on, log out and in: the app starts and **opens no window**.
- [ ] **Show in menu bar** off: the icon goes and the app keeps working. Open the app again from the
      Applications folder: the Settings window comes back.
- [ ] `make install` over a running copy: the app is replaced and **opens no window** (the quiet-launch
      marker), and the Accessibility grant survives.
- [ ] **Settings › Health**, the stethoscope between System and Tip, with everything in place: two tables and
      nothing else. **Health**: *Accessibility permission* *Granted* and *Watching for ⇧ Shift clicks*
      *Enabled* (its tooltip `watching`), both green, then **Check Again**; no warning under it. **Information**:
      *Running for* and *Memory used*, blue. No preference, no version, no update, no macOS version anywhere on
      the page. **Check Again**: a spinner beside the button for about half a second, the button disabled
      meanwhile. Turn *Launch at login* off on General: the page does not change, because a preference is
      never a check. **The red line** (the stop sign, *Accessibility permission* red *Denied* with the switch named
      under the table, and no listener line) is seen on a Mac where the grant has not been given yet, or with
      the window open during §9's step A. **Never take the grant away to see it outside §9**: here, the shared
      checklist's *break a required one* is that grant, and it reads one red line, because the listener says
      nothing while it waits for it. ShiftPick has no optional permission, so the shared *break one optional
      thing* has nothing to break.
- [ ] **Settings › Tip**: the toolbar's mug, the app icon beside the sentence, the Ko-fi cup on its red
      wash, and *Tip €5*. The button opens `ko-fi.com/bambidotexe` in the browser and the window stays put.
- [ ] The whole window in **French** and in **English** (System Settings › General › Language & Region, the
      per-app list).
