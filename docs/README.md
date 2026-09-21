# ShiftPick documentation

Shift-click range selection for Finder's icon views and the Desktop, as a menu-bar accessory. Swift,
SwiftPM, no Xcode project. Accessibility is the only permission it needs.

## Where to look

| Document | Read it when |
|---|---|
| [`functional.md`](functional.md) | You need to know what the app does: every rule of the click, the range, the anchor, the window, with the numbers. **The authority on behaviour.** |
| [`architecture.md`](architecture.md) | You need to know how it is built: the three targets, the click path end to end, threading, the update, the build. |
| [`macOS.md`](macOS.md) | You are about to rely on a platform assumption. **Finder's Accessibility hierarchy as it was actually read**, the event tap, the permission, the coordinate space. |
| [`pitfalls.md`](pitfalls.md) | Something looks like it should work and does not. The only place that records approaches that failed. |
| [`../MANUAL_TESTS.md`](../MANUAL_TESTS.md) | You changed something and want to see it work. The app target has no automated tests. |
| [`../CLAUDE.md`](../CLAUDE.md) | You are an agent working in this tree: commands, rules, traps, status. |
| [`../CONVENTIONS.md`](../CONVENTIONS.md) | You want to know why this app is shaped the way it is. What the three reference projects agreed on. |
| [`../DECISIONS.md`](../DECISIONS.md) | You want to know why a particular call was made. |
| [`../README.md`](../README.md) | You are a user: what it does, requirements, install, settings. |

## How to start

```sh
swift build                                     # three targets and the probe
swift test                                      # two bundles; count two summary lines
swift run axdump trust                          # can this terminal ask Finder anything
swift run axdump views                          # every icon view on screen, and its items in flow order
make install                                    # production build, notarized, into /Applications
/usr/bin/log stream --predicate 'subsystem == "dev.rubens.ShiftPick"' --level debug
```

The first launch asks for Accessibility and waits for it. Signing comes from `scripts/signing.env`
(tracked, no secret in it): it looks the Wooflab team's Developer ID Application certificate up in the
keychain by team id. An ad-hoc signature gives the app a new code identity, so the owner loses the
Accessibility grant.

## The shape in one paragraph

`ShiftPickCore` decides everything that can be decided from rectangles: where the rows and columns are,
whether a layout is arranged or hand-placed, which way it is filled, and which icons lie between two
others. It imports Foundation and CoreGraphics and nothing else, so every rule in it is testable without a
Mac in the state it describes. `ShiftPickPlatform` is the only code that talks to the system: one event
tap, one file that knows the shape of Finder's icon views, and the update's I/O. `ShiftPickApp` wires the
two into one behaviour, `ShiftPickEngine`, and puts three windows and a menu around it. `Tools/axdump` is
how Finder was read in the first place, and how it is read again.
