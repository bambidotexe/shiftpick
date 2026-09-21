#!/bin/sh
# **Install locally.** One of the two ways a build of this app ever reaches a Mac.
#
#   scripts/install.sh
#
# Builds the same signed, notarized, stapled production bundle a release ships, at the version the rule in
# scripts/version.sh gives and only from a tree whose tests pass, puts it in /Applications, opens it, and
# reads its launch back from its log: a launch on which macOS took a tap away, would not create them, or
# the breaker opened fails the install (scripts/safety-gates.sh). Leaves nothing behind: when this script
# returns there is no .app and no .dmg anywhere under the repository, so nothing but /Applications can be
# launched by Spotlight, opened by the Finder, or started at login.
#
# The other way is scripts/publish.sh, which does all of this and puts the disk image on GitHub as well.
#
# There is no third way. An ad-hoc, unsigned build (SIGN_IDENTITY="-") is for reading something a signed
# build will not show; it is never installed, and scripts/make-app.sh refuses to make one without
# DEBUG_OK=1 — that is the owner's call, not a way to skip this script.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/signing.env"
. "$ROOT/scripts/version.sh"
. "$ROOT/scripts/no-leftovers.sh"
. "$ROOT/scripts/safety-gates.sh"

DEST="/Applications/$APP_NAME.app"
MOUNT=""

# A reinstall is not a person asking for the Settings window. The marker is written **before anything can
# start the app**, and the first launch that finds it opens nothing; the copy that stays removes it
# (Sources/ShiftPickCore/QuietLaunch.swift). It lapses on its own after two minutes.
QUIET_DIR="$HOME/Library/Application Support/$APP_NAME"

# Whatever happens — a failed build, a failed verify, an interrupt — the repository is left with nothing
# launchable in it. This runs on the way out of every path through the script.
cleanup() {
  if [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
    /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  fi
  no_leftovers "$ROOT"
}
trap cleanup EXIT INT TERM

VERSION="$(version_tree)"
echo "installing $APP_NAME $VERSION" >&2

DMG="$("$ROOT/scripts/release.sh")"

# --------------------------------------------------------------------------------------------------------
# The bundle that goes to /Applications is the one inside the disk image, so what is installed is exactly
# what a release would hand a stranger — stapled ticket and all.
# --------------------------------------------------------------------------------------------------------
MOUNT="$(mktemp -d)"
/usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" >/dev/null

# The running copy goes before its bundle is replaced: two instances would each hold an event tap on the
# same clicks, and a process running from a path that no longer exists keeps the old behaviour with nothing
# on screen to say so. A signal and not an Apple event — `tell application … to quit` needs an Automation
# grant this script cannot be sure of, shows a dialog when it is missing, and *launches* the app when it is
# not running. ShiftPick has no state to flush on the way out: the tap dies with the process.
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
i=0
while [ $i -lt 50 ]; do
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
  sleep 0.1
  i=$((i + 1))
done
if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "$APP_NAME is still running after 5 s. Quit it, then run this again." >&2
  exit 1
fi

/bin/mkdir -p "$QUIET_DIR"
: > "$QUIET_DIR/quiet-launch"

rm -rf "$DEST"
/usr/bin/ditto "$MOUNT/$APP_NAME.app" "$DEST"
/usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
MOUNT=""

# What was installed says for itself what it is. A bundle that fails this must not be left in /Applications.
codesign --verify --deep --strict "$DEST" 2>/dev/null || { echo "the installed bundle does not verify" >&2; rm -rf "$DEST"; exit 1; }
INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
[ "$INSTALLED" = "$VERSION" ] || { echo "installed $INSTALLED, expected $VERSION" >&2; exit 1; }
xcrun stapler validate "$DEST" >/dev/null 2>&1 || echo "warning: the installed bundle carries no stapled ticket" >&2

# A stable Developer ID identity keeps the same code signature across installs, so the Accessibility grant
# in System Settings survives this reinstall; an ad-hoc build would lose it every time.
SINCE="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
open "$DEST"
echo "installed $DEST ($INSTALLED)" >&2

# What the installed app did when it met this Mac, read back from its own log (scripts/safety-gates.sh).
launch_is_sound "$APP_NAME" "$BUNDLE_ID" "$SINCE" "$INSTALLED" || exit 1
OWED="$(drill_owed "$ROOT")"
[ -z "$OWED" ] || echo "the safety layer differs from the last release: docs/manual-test-checklist.md §9 is owed on this build before it is published" >&2

echo "$DEST"
