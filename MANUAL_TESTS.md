# ShiftPick — what only a person can see

`ShiftPickApp` has no automated tests. This is its verification. Work down it after any change to the click
path, and note anything that surprises you in `docs/pitfalls.md`.

Two things make it quicker:

```sh
swift run axdump views          # every icon view on screen, its items in flow order, and how it was classified
swift run axdump range <x> <y>  # what a ⇧ Shift click there WOULD select, printed rather than done
/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug
```

`axdump range` is the one to reach for first when a selection is not what you expected: it says whether the
layout was read as arranged or hand-placed, which way it is filled, and which files the range holds, without
touching anything.

---

## 1. The gesture

- [ ] A folder in icon view. Click a file, ⇧ Shift click another **further on**: everything between the two
      is selected, both ends included.
- [ ] ⇧ Shift click a file **before** the first one: the range runs the other way, from the same first file.
- [ ] ⇧ Shift click again, nearer: the range **shrinks**, still measured from the same first file. The
      anchor does not move.
- [ ] ⌘ Command ⇧ Shift click somewhere else: the new range is **added** to what was selected.
- [ ] Turn *⌘ Command with ⇧ Shift adds the range* off in Settings. The same click now adds **one** file:
      Finder's own behaviour.
- [ ] Turn *Enable ShiftPick* off. ⇧ Shift click adds one file. Turn it on: the very next click is a range.
      No relaunch.

## 2. Where it works

- [ ] **Sort By Name, Kind, Date Added, Date Modified, Size, Tags.** In each: a range across a row, a range
      spanning several rows. `axdump views` should say `arranged(rowsFromLeft)` for all of them.
- [ ] **View › Use Groups on.** A range **inside** one group. A range that **crosses** two groups: it holds
      the end of the first, all of the second up to the target, and nothing from a group above or below.
- [ ] **View › Sort By › None**, icons dragged about by hand. `axdump views` should say `handPlaced`. A
      ⇧ Shift click now draws a **rubber band** between the two icons: icons inside the rectangle they span
      are selected, icons outside it are not, whatever their name.
- [ ] A **search result** window, **Recents**, a **tag**, **iCloud Drive**. Each in icon view.
- [ ] A window in **list, column and gallery** view: ⇧ Shift does what it always did, and the `click` log
      says nothing at all.

## 3. The Desktop

- [ ] Desktop **sorted** (View › Sort By › Name, with the Desktop frontmost). A range down one column. A
      range that **runs off the bottom of one column and into the next one to its left**: that is the order
      the Desktop fills, and it is what the range must follow.
- [ ] Desktop **hand-placed** (Sort By None): the rubber band again.
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
- [ ] A plain click on empty space, then ⇧ Shift click a file: **one** file is selected. The empty click
      cleared the anchor along with the selection.

## 7. The edges

- [ ] A **2,000+ item folder**. Two files both on screen: the range is right. Now click one, **scroll three
      screens**, ⇧ Shift click another: **the click goes to Finder untouched** and only that one file is
      added. `log stream --level debug` says `let through: no anchor and nothing selected`. That is the
      known limit, not a bug (`docs/pitfalls.md` 1).
- [ ] A folder with **one file**. ⇧ Shift click it: it is selected, nothing else happens.
- [ ] A folder with **one row** of files, and one with **one column**.
- [ ] Files whose names wrap to **two lines** beside files whose names do not: the range does not skip or
      include a row it should not.
- [ ] A window **resized** so the columns re-flow, mid-session: the next range follows the new layout.

## 8. The permission

- [ ] **First launch with the permission missing.** The system's own dialog appears once, and the
      onboarding window stays. Every sentence in it wraps; nothing is cut off.
- [ ] Grant Accessibility in System Settings **without touching the app**: within a second the onboarding
      window closes by itself, the menu's status line reads *Watching for ⇧ Shift clicks*, and the very
      next ⇧ Shift click is a range. **No relaunch.**
- [ ] **Take the grant away** while the app runs: the onboarding window comes back, the menu says it is
      waiting, and clicks go to Finder. Grant it again: it starts again.
- [ ] Settings › System while all of that happens: the row follows within two seconds, and the button and
      the warning appear and disappear with it.

## 9. The tap

- [ ] Leave the app running for a day with the log open. `the event tap was disabled by …` lines are
      expected occasionally; what matters is that a range still works after one.
- [ ] Hold a ⇧ Shift click while the Mac is busy: the click is either a range or Finder's, never nothing.

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

- [ ] Settings › General › Uninstall → the alert says what will go → Uninstall.
- [ ] Afterwards: no **ShiftPick** in System Settings › Privacy & Security › Accessibility; none in
      General › Login Items; `ls ~/Library/Application\ Support/ShiftPick` and
      `defaults read dev.rubens.ShiftPick` both say nothing is there; the app is **in the Trash**, not
      deleted.

## 12. The rest of the window

- [ ] Every page: nothing is cut off, nothing is truncated, and the window's height follows the page around
      its top-left corner.
- [ ] **Launch at login** on, log out and in: the app starts and **opens no window**.
- [ ] **Show in menu bar** off: the icon goes and the app keeps working. Open the app again from the
      Applications folder: the Settings window comes back.
- [ ] `make install` over a running copy: the app is replaced and **opens no window** (the quiet-launch
      marker), and the Accessibility grant survives.
- [ ] **Settings › Tip**: the toolbar's mug, the app icon beside the sentence, the Ko-fi cup on its red
      wash, and *Tip €5*. The button opens `ko-fi.com/bambidotexe` in the browser and the window stays put.
- [ ] The whole window in **French** and in **English** (System Settings › General › Language & Region, the
      per-app list).
