# Changelog

Every released version, newest first. `scripts/version.sh` holds the tree's version; a local install always
builds exactly that version. `scripts/publish.sh <patch|minor|major>` is the only thing that moves it: it
bumps by that level, commits and pushes the bump before it builds anything, then releases exactly that
version, and nothing bumps it again afterward. The version at the top of this file is the one being prepared
unless a release carries its tag.

## 0.0.1

The first build. Nothing is published yet, so every update check answers *No release published yet*.

- ⇧ Shift click selects the range between two icons in **every Finder icon view, on the Desktop, and in
  Open and Save panels shown as icons**, in every Sort By mode, with or without Use Groups, with or
  without Stacks, and in a folder nobody has sorted. A plain click, a ⌘ Command click and a ⌘ Command
  ⇧ Shift click each set where the next range is measured from.
- **What a ⇧ Shift click leaves selected is what a list view would leave**, measured on AppKit's
  `NSTableView`: the range replaces every run of selected files it touches, whole, and leaves every other
  run alone, so a selection built with ⌘ Command clicks survives it. A ⌘ Command ⇧ Shift click is Finder's
  own toggle and passes through. A deselected file where the range was last measured from is stood in by
  the first selected file after it, and with nothing selected at all the range runs from the first file in
  the view while the view is at its top.
- The range is worked out from where the icons are: rows and columns clustered out of their frames, a
  layout read as arranged or hand-placed, the fill direction inferred. **A hand-placed view gets grids
  inferred from where the icons sit**, one per group of icons that hang together, each read along its rows;
  where no one grid holds both ends, the rubber band between the two icons answers, as it does for a group
  with no grid at all. A collapsed Desktop stack is never in a range, and one somebody selected is never
  touched by one.
- **Every other click reaches Finder untouched.** With no finger on ⇧ Shift, no click passes through
  ShiftPick at all, and a ⇧ Shift click it cannot answer within 150 ms goes to Finder. Taking its permission
  away while it runs, putting the Mac to sleep under it or forcing it to quit never costs a click.
- **Accessibility is the only permission**, asked for by the welcome wizard's own button on the first
  launch and picked up the moment it is granted, with no relaunch.
- **No setting about what ShiftPick does.** The feature is always on and does one thing one way. A menu-bar
  item with Launch at Login, what the app is doing right now, Settings and Quit. A four-page Settings
  window: General, System, Health, Tip. The System page says whether ShiftPick is listening and carries
  **Start Listening Again**, the one way to ask for another try after macOS has interrupted the listener
  three times in a minute.
- A **Health** page: whether ShiftPick works, at a glance, in two short tables. *Health*: the permission,
  whether it is watching for ⇧ Shift clicks and why not, and, only while something is wrong, Finder and this
  week's crashes, each green, orange or red with what to do about it, and Check Again. *Information*: how
  long it has run and its memory.
- Updates from GitHub releases: checked at launch and weekly, announced by one notification, fetched and
  installed from a window of their own, and rolled back if the new version does not start.
- A **Tip** page: everything is free and stays free, and a one-time tip on Ko-fi if you want to offer a
  coffee. Nothing is ever asked for and nothing is paid inside the app.
- Uninstall from Settings › General, which gives the Accessibility permission back, removes the Login
  Items entry and the preferences, and moves the app to the Trash. It touches nothing that is not
  ShiftPick's own.
- English and French.
