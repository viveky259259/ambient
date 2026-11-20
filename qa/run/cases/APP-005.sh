#!/bin/zsh
# APP-005 · Only one Ambient runs at a time.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: that the second copy shows no window or menu-bar item before it quits.
# The second copy is the QA app's own binary, started again with the same AMBIENT_HOME.
source "$QA_REPO/qa/run/lib.sh"

gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
trap '[[ -n ${SECOND_PID:-} ]] && kill $SECOND_PID 2>/dev/null' EXIT

ambient emit working --session qa-first --agent Build --tool make >/dev/null || fail "emit failed"
wait_for 5 grep -q qa-first "$AMBIENT_HOME/state.json"
sleep 1.5
saved=$(<"$AMBIENT_HOME/state.json")

start=$EPOCHREALTIME
"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
SECOND_PID=$!
wait_for 10 gone $SECOND_PID
ms=$(( (EPOCHREALTIME - start) * 1000 ))
note "the second copy quit after ${ms%.*} ms"
(( ms <= 1000 )) || fail "the second copy took ${ms%.*} ms to quit (want within a second)"

gone $QA_APP_PID && fail "the first Ambient stopped"
assert_contains "$(ambient status --json)" '"sessionId" : "qa-first"' "the first Ambient's sessions"

msg=$(/usr/bin/log show --last 2m --style compact --predicate "processID == $SECOND_PID" 2>/dev/null)
assert_contains "$msg" "Another Ambient is already running; quitting." "the log"

# Not in the case's Expected, but worth knowing: whether the quitting copy rewrote the first one's state file.
sleep 1.5
[[ $(<"$AMBIENT_HOME/state.json") == "$saved" ]] || note "state.json changed while the second copy quit: $(<"$AMBIENT_HOME/state.json")"
