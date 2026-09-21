#!/bin/sh
# **Publish a release.** The other of the two ways a build of this app ever reaches a Mac.
#
#   scripts/publish.sh <patch|minor|major> [--no-install]
#
# Refuses first: on a dirty tree, on a failing test, and when the safety layer changed since the last
# release without the owner saying DRILL=walked or DRILL=waived (scripts/safety-gates.sh).
#
# Bumps the version by the given level, commits and pushes that alone, then tags the commit, attaches the
# signed and notarized disk image to a GitHub release, and installs the same bundle in /Applications. The
# tree is left exactly at the version just published — nothing bumps it further, so a later local install
# carries the same version until someone next runs this script. It leaves nothing behind: no .app and no
# .dmg anywhere under the repository.
#
# `--no-install` publishes the release and leaves /Applications alone. It is how the update the users get is
# tested: the Mac stays on the version it runs, and that version finds the release and installs it itself.
#
# The other way is scripts/install.sh, which does everything but the publishing.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/signing.env"
. "$ROOT/scripts/version.sh"
. "$ROOT/scripts/no-leftovers.sh"
. "$ROOT/scripts/safety-gates.sh"

LEVEL=""
INSTALL=1
for arg in "$@"; do
  case "$arg" in
    patch|minor|major) LEVEL="$arg" ;;
    --no-install) INSTALL=0 ;;
    *) echo "unknown argument: $arg (patch, minor, major, --no-install)" >&2; exit 1 ;;
  esac
done
[ -n "$LEVEL" ] || { echo "usage: scripts/publish.sh <patch|minor|major> [--no-install]" >&2; exit 1; }

DEST="/Applications/$APP_NAME.app"
QUIET_DIR="$HOME/Library/Application Support/$APP_NAME"
MOUNT=""

cleanup() {
  if [ -n "$MOUNT" ] && [ -d "$MOUNT" ]; then
    /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  fi
  no_leftovers "$ROOT"
}
trap cleanup EXIT INT TERM

# --------------------------------------------------------------------------------------------------------
# A release names a commit, so everything it names has to be committed and pushed — including the version
# bump this script makes itself, below. This refusal comes before the bump and the build: dirty is not this
# script's to resolve, and none of what follows is worth five minutes of notarizing to discover it was.
# --------------------------------------------------------------------------------------------------------
[ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "refusing: the working tree is dirty. Commit first — a release names a commit." >&2; exit 1; }

# Before the bump, which is pushed: a release whose tests fail, or whose safety layer changed without the
# owner's drill, must not leave a version commit on the branch behind it (scripts/safety-gates.sh).
# release.sh runs the tests again on the bumped tree; only the version differs.
tests_pass "$ROOT" || exit 1
drill_gate "$ROOT" || exit 1

VERSION="$(version_bump "$LEVEL" "$(version_tree)")"
TAG="v$VERSION"
git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "refusing: $TAG already exists." >&2; exit 1; }
[ -z "$(gh release view "$TAG" -R "$GITHUB_REPO" --json tagName -q .tagName 2>/dev/null)" ] || { echo "refusing: a release $TAG already exists on GitHub." >&2; exit 1; }

# The bump is its own commit, pushed before anything is built: the commit this script tags is the commit
# that carries the version it releases, so nobody ever sees a tag whose bump is missing from the branch.
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
version_set "$VERSION"
git -C "$ROOT" add scripts/make-app.sh
git -C "$ROOT" commit -q -m "build(version): the tree moves to $VERSION"
git -C "$ROOT" push -q origin "$BRANCH"

echo "releasing $APP_NAME $VERSION" >&2
DMG="$("$ROOT/scripts/release.sh")"

# The tag is made and pushed only once there is an image to attach to it.
git -C "$ROOT" tag -a "$TAG" -m "$APP_NAME $VERSION"
git -C "$ROOT" push -q origin "$TAG"
gh release create "$TAG" "$DMG" -R "$GITHUB_REPO" --title "$APP_NAME $VERSION" \
  --notes "Signed with the Wooflab team's Developer ID and notarized by Apple." >&2

# --------------------------------------------------------------------------------------------------------
# What was just published is what this Mac runs, by the same steps as scripts/install.sh. Unless the release
# was made to be installed by the app itself, from the version already here.
# --------------------------------------------------------------------------------------------------------
if [ "$INSTALL" -eq 1 ]; then
  MOUNT="$(mktemp -d)"
  /usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" >/dev/null

  # A signal, not an Apple event: see scripts/install.sh for why.
  /usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
  i=0
  while [ $i -lt 50 ]; do
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
    i=$((i + 1))
  done
  if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "$APP_NAME is still running after 5 s. Quit it, then run this again — the release already exists." >&2
    exit 1
  fi

  # A reinstall is not a person asking for the Settings window. The marker is written before anything can
  # start the app (Sources/ShiftPickCore/QuietLaunch.swift).
  /bin/mkdir -p "$QUIET_DIR"
  : > "$QUIET_DIR/quiet-launch"

  rm -rf "$DEST"
  /usr/bin/ditto "$MOUNT/$APP_NAME.app" "$DEST"
  /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  MOUNT=""

  codesign --verify --deep --strict "$DEST" 2>/dev/null || { echo "the installed bundle does not verify" >&2; rm -rf "$DEST"; exit 1; }
  INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
  [ "$INSTALLED" = "$VERSION" ] || { echo "installed $INSTALLED, expected $VERSION" >&2; exit 1; }
  xcrun stapler validate "$DEST" >/dev/null 2>&1 || echo "warning: the installed bundle carries no stapled ticket" >&2

  SINCE="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
  open "$DEST"
  echo "installed $DEST ($VERSION)" >&2
  launch_is_sound "$APP_NAME" "$BUNDLE_ID" "$SINCE" "$VERSION" || {
    echo "the release is published; the launch of it on this Mac is what failed." >&2
    exit 1
  }
else
  echo "/Applications is untouched: the copy running there is what this release is offered to." >&2
fi

echo "https://github.com/$GITHUB_REPO/releases/tag/$TAG"
