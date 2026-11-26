#!/bin/zsh
# APP-009 · Quit and relaunch keep running sessions.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: the island and menu showing them, and quitting with ⌘Q (a script can stop the app only by signal,
# so this quits it the hard way, after the state has been saved).
# Two recorded sessions stand in for the two Claude Code sessions; their events are sent from a process detached from
# this script, so no app on screen counts as already looking at them.
source "$QA_REPO/qa/run/lib.sh"

CLI=$QA_APP/Contents/Helpers/ambient
EMITS=0
emit_detached() {
  local mark=$QA_ROOT/.emit.$((++EMITS))
  ( ( sleep 0.2; "$CLI" emit "$@" >/dev/null 2>&1; print $? > $mark ) & )
  wait_for 5 test -s $mark
  [[ $(<$mark) == 0 ]] || fail "ambient emit $* exited $(<$mark)"
}
gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
up() { ambient status >/dev/null 2>&1; }
trap '[[ -n ${APP_PID:-} ]] && kill $APP_PID 2>/dev/null' EXIT
sessions() { ambient status --json | jq -c '[.[] | {id, activity, acknowledged}] | sort_by(.id)'; }

emit_detached working --session qa-busy --agent Build --tool make
emit_detached working --session qa-fin --agent Build --tool make
emit_detached done --session qa-fin --agent Build --message "Release built"
emit_detached working   # a demo session
has_demo() { [[ $(ambient status --json) == *demo-* ]]; }
wait_for 5 has_demo
sleep 2   # state is written about a second after a change
before=$(sessions | jq -c 'map(select(.id | startswith("custom:qa-")))')
assert_eq "$(jq -r 'length' <<< $before)" 2 "sessions before quitting"
assert_contains "$(<"$AMBIENT_HOME/state.json")" '"sessionId":"qa-fin"' "state.json"
assert_not_contains "$(<"$AMBIENT_HOME/state.json")" 'demo-' "state.json holding a demo session"

kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
APP_PID=$!
wait_for 15 up
sleep 1
after=$(sessions)
assert_eq "$after" "$before" "sessions after relaunch"
assert_eq "$(jq -r '.[] | select(.id=="custom:qa-fin") | (.activity | keys[0]) + " " + (.acknowledged|tostring)' <<< $after)" "done false" "the finished session (still green until seen)"
note "back after relaunch: $after"
