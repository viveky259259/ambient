#!/bin/zsh
# APP-011 · A crash or force quit loses at most the last second, and relaunching recovers.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: that Ambient shows no error after the corrupt state file (here: it starts, answers and shows no
# sessions). A recorded Claude Code hook stands in for the agent while Ambient is down.
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
board() { ambient tasks --json | jq -c '[.[] | {id, title, status}] | sort_by(.id)'; }
relaunch() {
  "$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
  APP_PID=$!
  wait_for 15 up
  sleep 1
}

# Step 1: agents change state, 2 s pass, then kill -9.
emit_detached working --session qa-a --agent Build --tool make
emit_detached working --session qa-b --agent Build --tool make
emit_detached waiting --session qa-b --agent Build --reason command --message "rm -rf build"
sleep 2
before=$(sessions)
tasks_before=$(board)
assert_eq "$(jq length <<< $before)" 2 "sessions before the kill"
kill -9 $QA_APP_PID
wait_for 10 gone $QA_APP_PID

# The agents keep working: their hooks drop the event silently while Ambient is down.
out=$(print -r -- '{"session_id":"qa-c","hook_event_name":"UserPromptSubmit","cwd":"/tmp","prompt":"hi"}' | ambient hook claude 2>&1)
assert_eq "$?" 0 "a hook's exit code while Ambient is down"
assert_eq "$out" "" "a hook's output while Ambient is down"

# Step 2: relaunch.
relaunch
assert_eq "$(sessions)" "$before" "sessions after relaunching from a kill -9"
assert_eq "$(board)" "$tasks_before" "the board after relaunching from a kill -9"

# Step 3: a corrupt state file.
kill $APP_PID
wait_for 10 gone $APP_PID
print garbage > "$AMBIENT_HOME/state.json"
relaunch
status=$(ambient status)
assert_eq "$?" 0 "ambient status after a corrupt state file"
assert_contains "$status" "0 sessions" "ambient status after a corrupt state file"
emit_detached working --session qa-new --agent Build --tool make
has_new() { [[ $(ambient status --json) == *'"qa-new"'* ]]; }
wait_for 5 has_new
