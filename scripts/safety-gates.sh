#!/bin/sh
# The gates a build of ShiftPick passes on its way to a Mac. It holds an event tap that can swallow a click,
# and the one thing it must never do is break clicking (docs/functional.md §0; the shiftpick-safety-nets
# skill lists every net and what pins it).
#
#   . scripts/safety-gates.sh
#   tests_pass <root>          swift test: both bundles green, and the suites that pin the nets among them
#   drill_owed <root>          the safety files that differ from the last release, one per line
#   drill_gate <root>          refuses when drill_owed names anything, unless the owner said DRILL=walked
#                              (docs/manual-test-checklist.md §9, on an installed build of this tree) or
#                              DRILL=waived (the owner decided this change does not need it)
#   launch_is_sound <app name> <bundle id> <since> <version>
#                              the installed app's first seconds, read back from its own log
#
# scripts/release.sh runs tests_pass before it builds, so neither install.sh nor publish.sh makes anything
# from a tree whose tests say a net is gone. publish.sh runs tests_pass and drill_gate before it bumps the
# version, and install.sh and publish.sh run launch_is_sound after they open the app.
#
# Sourced by scripts running under `set -eu`, so every command that may fail says what happens when it does:
# a bare assignment from a failing command substitution ends the calling script without a word
# (docs/pitfalls.md 3).

# The code a change to which can reach the taps, the grant or the teardown: when the click tap may be
# enabled, the taps and their thread, a click's budget, how the grant is read, sleep and the lock screen, a
# second copy, the quit, the uninstall. SafetyNetTests pins the nets in it; the drill is what shows, on a
# real Mac, that they still hold.
SAFETY_FILES="
Sources/ShiftPickCore/Constants.swift
Sources/ShiftPickCore/TapLifecycle.swift
Sources/ShiftPickCore/TrustVerdict.swift
Sources/ShiftPickPlatform/AX.swift
Sources/ShiftPickPlatform/BoundedWait.swift
Sources/ShiftPickPlatform/ClickGuard.swift
Sources/ShiftPickPlatform/DeadlineGate.swift
Sources/ShiftPickPlatform/LoginItem.swift
Sources/ShiftPickPlatform/Permissions.swift
Sources/ShiftPickPlatform/TapThread.swift
Sources/ShiftPickPlatform/Uninstall.swift
Sources/ShiftPickApp/AppDelegate.swift
Sources/ShiftPickApp/SettingsGeneralPage.swift
Sources/ShiftPickApp/ShiftClickResolver.swift
Sources/ShiftPickApp/ShiftPickEngine.swift
Sources/ShiftPickApp/ShiftPickMain.swift
"

# The suites that pin the nets. A run that did not include one of them has not checked what it pins, however
# green the rest is.
SAFETY_SUITES="SafetyNetTests TapLifecycleTests TapLifecycleInvariantTests DeadlineGateTests TapThreadTests TrustVerdictTests BoundedWaitTests"

tests_pass() {
  root="${1:?tests_pass <root>}"
  log="$(/usr/bin/mktemp -t shiftpick-tests)"
  echo "running the tests…" >&2
  if ! swift test --package-path "$root" >"$log" 2>&1; then
    /usr/bin/grep -E "error:|failed|Fatal" "$log" | /usr/bin/head -40 >&2 || true
    echo "refusing: swift test failed, and nothing is built from a tree whose tests fail. The whole run: $log" >&2
    return 1
  fi
  # One summary line per bundle. A bundle that crashed prints none, which reads as a pass to anything that
  # looks for one green line (docs/pitfalls.md 4).
  bundles="$(/usr/bin/grep -c "Test Suite '.*\.xctest' passed" "$log" || true)"
  if [ "$bundles" != 2 ]; then
    echo "refusing: $bundles of the 2 test bundles reported a pass. The whole run: $log" >&2
    return 1
  fi
  for suite in $SAFETY_SUITES; do
    /usr/bin/grep -q "Test Suite '$suite' passed" "$log" || {
      echo "refusing: $suite did not run, and it pins a safety net. The whole run: $log" >&2
      return 1
    }
  done
  echo "tests: both bundles green, the safety suites among them" >&2
  rm -f "$log"
}

drill_owed() {
  root="${1:?drill_owed <root>}"
  last="$(git -C "$root" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  if [ -z "$last" ]; then
    # Nothing was ever released, so all of it is new.
    for file in $SAFETY_FILES; do echo "$file"; done
  else
    # The working tree against the release, so a change not yet committed counts as well.
    git -C "$root" diff --name-only "$last" -- $SAFETY_FILES || true
  fi
}

drill_gate() {
  root="${1:?drill_gate <root>}"
  owed="$(drill_owed "$root")"
  [ -n "$owed" ] || return 0
  case "${DRILL:-}" in
    walked) echo "the safety layer changed since the last release, and the owner walked the drill on this tree" >&2; return 0 ;;
    waived) echo "the safety layer changed since the last release, and the owner waived the drill for it" >&2; return 0 ;;
  esac
  echo "refusing: the safety layer changed since the last release:" >&2
  echo "$owed" | /usr/bin/sed 's/^/  /' >&2
  echo "This is the owner's call, not an agent's. docs/manual-test-checklist.md §9 is walked by the owner on an" >&2
  echo "installed build of this tree (make install), behind scripts/drill.sh. Then DRILL=walked, or DRILL=waived" >&2
  echo "if the owner decides this change does not need it." >&2
  return 1
}

# A signature says what was built; this says what it did when it met this Mac. Passes when the app said it
# launched at this version and then either that it is listening or that it is waiting for the permission.
# Fails when macOS took a tap away, would not create them, or the breaker opened, which is what the first
# install of the rewritten taps did (docs/pitfalls.md 15), and when a second copy is running.
launch_is_sound() {
  usage="launch_is_sound <app name> <bundle id> <since> <version>"
  name="${1:?$usage}"; bundle="${2:?$usage}"; since="${3:?$usage}"; version="${4:?$usage}"
  said=""
  i=0
  while [ $i -lt 20 ]; do
    /bin/sleep 1
    said="$(/usr/bin/log show --predicate "subsystem == \"$bundle\"" --start "$since" --style compact 2>/dev/null || true)"
    case "$said" in *"not listening:"*|*"listening for "*" clicks"*) break ;; esac
    i=$((i + 1))
  done
  problem=""
  # Every line read here is a notice or an error, which the log keeps. `log show` has still been seen to
  # return nothing where `log stream` did (docs/shared/pitfalls.md T6), and that is not the app's silence.
  case "$said" in
    *"[$bundle:"*) ;;
    *) problem="the log shows nothing from the app since it was opened; watch /usr/bin/log stream by hand (docs/shared/pitfalls.md T6)" ;;
  esac
  [ -n "$problem" ] || case "$said" in
    *"kept taking the click tap away"*|*"times in "*"both taps destroyed"*) problem="the breaker opened while the app was starting" ;;
    *"macOS took the "*" tap away"*) problem="macOS took a tap away while the app was starting" ;;
    *"would not create the event taps"*) problem="macOS would not create the event taps although the grant reads as given" ;;
    *"$version launched"*) ;;
    *) problem="the app never said it launched at $version" ;;
  esac
  copies="$(/usr/bin/pgrep -x "$name" | /usr/bin/wc -l | /usr/bin/tr -d ' ' || true)"
  [ -n "$problem" ] || [ "$copies" -le 1 ] || problem="$copies copies are running, and two copies are two taps on the same clicks"
  # What the app said first about its taps is the launch's answer; anything later is the owner at work.
  first="$(printf '%s\n' "$said" | /usr/bin/grep -m1 -E 'not listening:|listening for .* clicks' || true)"
  if [ -z "$problem" ]; then
    case "$first" in
      *"permission is missing"*)
        echo "launch: $version is running and waiting for the Accessibility permission (the wizard's Allow button)" >&2
        return 0 ;;
      *"not listening:"*) problem="it is not listening: ${first##*not listening: }" ;;
      *"listening for "*)
        echo "launch: $version is running and listening for ⇧ Shift clicks" >&2
        return 0 ;;
      *) problem="the app said nothing about its taps within 20 s" ;;
    esac
  fi
  echo "the launch is not sound: $problem." >&2
  echo "The app stays installed and running, and a tap it does not hold cannot stall a click. What it said:" >&2
  echo "$said" | /usr/bin/tail -30 >&2
  return 1
}
