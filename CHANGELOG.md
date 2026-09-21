# Changelog

Every released version, newest first. The tree is always one patch ahead of the newest release
(`scripts/version.sh`), so the version at the top of this file is the one being prepared unless a release
carries its tag.

## 0.0.1

The first build. Nothing is published yet, so every update check answers *No release published yet*.

- ⇧ Shift click selects the range between two icons in **every Finder icon view, on the Desktop, and in
  Open and Save panels shown as icons**, in every Sort By mode, with or without Use Groups, with or
  without Stacks, and in a folder nobody has sorted. A plain or ⌘ Command click sets where the next range
  is measured from; ⌘ Command with ⇧ Shift adds the range to the selection.
- The range is worked out from where the icons are: rows and columns clustered out of their frames, a
  layout read as arranged or hand-placed, the fill direction inferred, and either a slice of the reading
  order or a rubber band between the two icons. A collapsed Desktop stack is never in a range.
- Every other click reaches Finder untouched, and so does a ⇧ Shift click ShiftPick cannot answer.
- **Accessibility is the only permission**, asked for at the first launch and picked up the moment it is
  granted, with no relaunch.
- A menu-bar item with the enable switch, Launch at Login, what the app is doing right now, Settings and
  Quit. A four-page Settings window: General, Selection, Tip, System.
- Updates from GitHub releases: checked at launch and weekly, announced by one notification, fetched and
  installed from a window of their own, and rolled back if the new version does not start.
- A **Tip** page: everything is free and stays free, and a one-time tip on Ko-fi if you want to offer a
  coffee. Nothing is ever asked for and nothing is paid inside the app.
- Uninstall from Settings › General, which gives the Accessibility permission back, removes the Login
  Items entry and the preferences, and moves the app to the Trash.
- English and French.
