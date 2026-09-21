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
  without Stacks, and in a folder nobody has sorted. A plain or ⌘ Command click sets where the next range
  is measured from; ⌘ Command with ⇧ Shift adds the range to the selection.
- The range is worked out from where the icons are: rows and columns clustered out of their frames, a
  layout read as arranged or hand-placed, the fill direction inferred, and either a slice of the reading
  order or a rubber band between the two icons. A collapsed Desktop stack is never in a range.
- **Every other click reaches Finder untouched.** With no finger on ⇧ Shift, no click passes through
  ShiftPick at all, and a ⇧ Shift click it cannot answer within 150 ms goes to Finder. Taking its permission
  away while it runs, putting the Mac to sleep under it or forcing it to quit never costs a click.
- **Accessibility is the only permission**, asked for by the welcome wizard's own button on the first
  launch and picked up the moment it is granted, with no relaunch.
- A menu-bar item with the enable switch, Launch at Login, what the app is doing right now, Settings and
  Quit. A four-page Settings window: General, Selection, System, Tip.
- Updates from GitHub releases: checked at launch and weekly, announced by one notification, fetched and
  installed from a window of their own, and rolled back if the new version does not start.
- A **Tip** page: everything is free and stays free, and a one-time tip on Ko-fi if you want to offer a
  coffee. Nothing is ever asked for and nothing is paid inside the app.
- Uninstall from Settings › General, which gives the Accessibility permission back, removes the Login
  Items entry and the preferences, and moves the app to the Trash. It touches nothing that is not
  ShiftPick's own.
- English and French.
