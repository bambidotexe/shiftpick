---
name: install-locally
description: Use when the owner asks to install ShiftPick on this Mac, to apply a change, to rebuild, to reinstall, to "run the app", to see a change working, or to get the newest build into /Applications. This is one of only two ways a build of this app ever reaches a Mac; the other is publish-release. Also use when about to build the app for any reason, to check first whether a build is even the right action.
---

# Install locally

**This app reaches a Mac in exactly two ways.** This skill is the first: a production build, installed in
`/Applications`, leaving nothing behind. The second is `publish-release`, which does the same and puts the
disk image on GitHub as well.

```bash
make install
# or directly:
sh scripts/install.sh
```

That is the whole action. It takes a few minutes, most of it Apple's notary service.

## What it does, and why each part is not optional

1. **Builds exactly the tree's version** (`scripts/version.sh`): no GitHub check, no requirement to be
   ahead of what is published. A local install always carries the same version as the code in the tree.
2. **Builds the real thing** (`scripts/release.sh`) — signed with the Wooflab team's Developer ID under the
   Hardened Runtime, notarized by Apple, stapled, wrapped in the disk image. Not a shortcut, not an ad-hoc
   build. What lands in `/Applications` is byte-for-byte what a stranger would download.
3. **Stops the running copy with a signal, and waits for it to go.** Two instances would each hold an event
   tap on the same clicks, and a process running from a bundle that has been replaced keeps the old
   behaviour with nothing on screen to say so. It is `pkill`, not `tell application … to quit`: an Apple
   event needs an Automation grant this script cannot be sure of, shows a dialog when it is missing, and
   **launches the app** when it is not running. ShiftPick has no state to flush on the way out.
4. **Writes the quiet-launch marker** before anything can start the app. A reinstall is not a person asking
   for the Settings window, and the launch below would otherwise open one nobody asked for
   (`Sources/ShiftPickCore/QuietLaunch.swift`). It lapses on its own after two minutes.
5. **Installs the bundle from inside the disk image**, so what runs is what a release would hand out,
   stapled ticket and all, and then verifies its signature, its version and its ticket. A bundle that fails
   any of those is removed rather than left in `/Applications`.
6. **Opens it.** A stable Developer ID signature keeps the same code identity across installs, **so the
   owner's Accessibility grant survives the reinstall**. An ad-hoc build would lose it every time.
7. **Leaves nothing behind.** No `.app` and no `.dmg` anywhere under the repository when it returns,
   including when it fails. `scripts/no-leftovers.sh` holds that rule.

## The rule about leftovers, which is the point

A signed bundle sitting in `build/` is a complete, working application. Spotlight indexes it, the Finder
opens it, and it runs **beside** the copy in `/Applications` as a second instance with the same bundle
identifier, the same preferences **and a second event tap on the same clicks**. Two taps both deciding
whether to swallow a ⇧ Shift click is not a state anybody should have to debug.

So: **only `/Applications/ShiftPick.app` exists.** A build is a step on the way there, never a thing left
lying about. If you ever build by another route (`make app`, `make dmg`), delete the bundle yourself before
you finish.

## Never do these

| Never | Instead |
|---|---|
| Build ad-hoc to "try something" | `scripts/install.sh`. An ad-hoc build is refused without `DEBUG_OK=1`, and **you must ask the owner first** — see below |
| `open` a `.app` from `build/` | Install it. Launching a build bundle is what creates a second event tap |
| Leave a built bundle behind "for next time" | There is no next time; the next build makes its own |
| Skip notarizing "because it is only local" | Then the installed copy is not what a release ships, and the release path goes untested until it matters |
| Copy the bundle into `/Applications` by hand | The version and the ticket are not checked, and the running copy is not stopped |

## Ad-hoc builds

An ad-hoc build (`SIGN_IDENTITY="-"`, the fallback when no Developer ID certificate is in the keychain)
exists to read something a signed build will not show. It is **never installed**, and — the reason that
matters most for this app — **it gives the app a new code identity on every build, so the owner loses the
Accessibility grant and has to give it again**, leaving a dead entry in the privacy list each time.
`scripts/make-app.sh` refuses one unless `DEBUG_OK=1`, which is there to make the decision deliberate, not
to be worked around.

If you think an ad-hoc build would help, **ask the owner and say why.** If they agree:

```bash
DEBUG_OK=1 sh scripts/make-app.sh
```

and delete `build/ShiftPick.app` when you are done with it.

## Checking it worked

```bash
codesign -dvv /Applications/ShiftPick.app 2>&1 | grep -E 'Authority=Developer|flags='
pgrep -lx ShiftPick
/usr/bin/log show --predicate 'subsystem == "dev.rubens.ShiftPick"' --last 5m
swift run axdump views          # and then actually Shift-click something
```

The authority is `Developer ID Application: Wooflab (85F6AC5QZF)` and the flags include `runtime`. The log
should carry `ShiftPick <version> launched` and, once the permission is granted, `watching for clicks`. The
version is whatever the tree holds, per `scripts/version.sh`.

**A clean install is not proof that the app works.** ShiftPick's whole behaviour is one gesture, and
nothing in the install path exercises it: ⇧ Shift click two icons in a Finder window, or run
`swift run axdump range <x> <y>` over one, before you say it is installed and working.

## What is at stake if this is skipped

ShiftPick swallows clicks. Two copies running at once, or a copy running from a bundle that has been
replaced under it, both end in clicks that do something nobody asked for and nothing on screen to explain
it. The stop-and-wait in step 3 is what keeps that from happening, and it is why there is no third way in.

## Taking it off again

There is one way, and it is not the Finder. **Settings › General › Uninstall** gives back the Accessibility
permission, removes the entry in Login Items, removes the preferences and the update folder, moves the
bundle to the Trash and quits. Dragging the bundle to the Trash removes the app and nothing else: the login
item goes on offering to start something that is gone, and the Accessibility grant stays in the privacy
list, where a later build signed by the same team inherits a decision nobody remembers making.

The last removals belong to a detached helper that waits for the pid: the preferences taken away while the
app is still up are written back by `cfprefsd` as it exits. Never suggest removing the pieces by hand
instead.
