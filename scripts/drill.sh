#!/bin/sh
# **The dead-man's switch for the safety drill** (docs/manual-test-checklist.md §9). Start it BEFORE touching the grant.
#
#   sh scripts/drill.sh          # the app is killed 30 s from now, whatever happens
#   sh scripts/drill.sh 45       # or some other number of seconds
#
# The drill takes the Accessibility grant away from a running ShiftPick on purpose, which is the one thing
# that has ever cost this Mac its mouse and keyboard (docs/pitfalls.md 13). This script is what makes doing
# that again safe: before anything is touched it starts a process of its own that sleeps and then sends the
# app SIGKILL. A process that dies takes its event taps with it, however wedged the input is and whatever
# state this terminal is in, so **the worst a drill can cost is that many seconds of a Mac that ignores
# you, never the power button.**
#
# The switch always fires, drill passed or not: a switch that could be called off is a switch that can be
# called off by mistake. Open the app again afterwards.
#
# Then it follows the app's log, which is where a drill is read. ^C stops the log and not the switch.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The two names, read and not sourced: signing.env looks a certificate up in the keychain when it is run.
name="$(/usr/bin/sed -n 's/^APP_NAME=//p' "$ROOT/scripts/signing.env" | /usr/bin/head -1)"
bundle="$(/usr/bin/sed -n 's/^BUNDLE_ID=//p' "$ROOT/scripts/signing.env" | /usr/bin/head -1)"
seconds="${1:-30}"

case "$seconds" in
  ''|*[!0-9]*) echo "usage: sh scripts/drill.sh [seconds]" >&2; exit 2 ;;
esac
[ -n "$name" ] && [ -n "$bundle" ] || { echo "scripts/signing.env names no app" >&2; exit 1; }

pid="$(/usr/bin/pgrep -x "$name" | /usr/bin/head -1)"
[ -n "$pid" ] || { echo "$name is not running: open it, check that a ⇧ Shift click selects a range, then run this again." >&2; exit 1; }

# In a session of its own and tied to nothing: it has to fire even if this terminal is closed, and it needs
# no click and no key to do so. By pid, and then by name as well: a copy opened again during the drill has
# another pid, and the switch is for whichever copy is holding the Mac up.
/usr/bin/nohup /bin/sh -c '/bin/sleep "$1"; /bin/kill -9 "$2"; /usr/bin/pkill -9 -x "$3"' \
  drill "$seconds" "$pid" "$name" >/dev/null 2>&1 &

echo "dead-man's switch armed: $name (pid $pid) is killed in $seconds s, whatever happens." >&2
echo "do the drill now. If the Mac stops answering, take your hands off and wait for the switch." >&2
echo "--- $bundle, at debug. ^C stops this log and not the switch ---" >&2
exec /usr/bin/log stream --predicate "subsystem == \"$bundle\"" --level debug --style compact
