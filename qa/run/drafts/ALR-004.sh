#!/bin/zsh
# ALR-004 · No banner or chime while you're in the agent's app, and it counts as seen.
# needs-app: yes
# checks: part
# Left to a person: no banner and no chime, the island blooming amber with Approve a command · rm -rf build, the wings turning back to the agent's colour.
# A needs-you arrives from a session whose host app (__CFBundleIdentifier) is the app in front, as from Claude Code in
# the Terminal you are looking at; it must count as seen about 4 seconds later.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

front=$(front_bundle)
[[ -n $front ]] || { echo "can't tell which app is in front" >&2; exit 2; }
mkdir -p "$QA_ROOT/api"
start=$EPOCHREALTIME
__CFBundleIdentifier=$front ambient emit waiting --session alr-004 --agent Build --reason command --message "rm -rf build" --cwd "$QA_ROOT/api" >/dev/null \
  || fail "ambient emit failed"
wait_for 3 sess_is alr-004 .activity.waiting.reason command
assert_eq "$(sess alr-004 .host.bundleId)" "$front" "the session's host app"
sleep 2
assert_eq "$(sess alr-004 .acknowledged)" false "seen after only $(ms_since $start) ms (want about 4 s)"
wait_for 5 sess_is alr-004 .acknowledged true
ms=$(ms_since $start)
[[ $(front_bundle) == $front ]] || { echo "the app in front changed during the check" >&2; exit 2; }
note "counted as seen after about $ms ms"
(( ms >= 3500 && ms <= 6000 )) || fail "counted as seen after $ms ms (want about 4 s)"
assert_eq "$(sess alr-004 .activity.waiting.message)" "rm -rf build" "the prompt itself is still waiting"
