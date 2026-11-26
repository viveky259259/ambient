#!/bin/zsh
# APP-030 · `ambient status` lists the tracked sessions.
# needs-app: yes
# timeout: 60
# checks: part
# Left to a person: "on <machine>" for a remote session (needs a second machine).
# Two `ambient emit` sessions stand in for the agents; colours are read through a pseudo-terminal (`script`).
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
ESC=$'\e'

long="a-project-folder-name-that-is-far-too-long"
mkdir -p "$QA_ROOT/$long"
emit_detached working --session qa-work --agent Build --tool make --detail "make all" --cwd "$QA_ROOT/$long"
emit_detached waiting --session qa-wait --agent Build --reason command --message "rm -rf build" --cwd "$QA_ROOT/api"
sleep 1

# Step 1, through a terminal.
tty=$(script -q /dev/null "$CLI" status </dev/null | tr -d '\r')
plain=$(ambient status)
lines=("${(@f)plain}")
assert_eq "${lines[1]}" "Ambient · 2 sessions · needs you" "the header"
assert_eq "${#lines}" 3 "lines printed"
[[ ${lines[2]} == "  ● custom      api "*"Approve a command · rm -rf build  "<0-9>s ]] || fail "the waiting session's line: [${lines[2]}]"
title=${long:0:27}…
[[ ${lines[3]} == "  ● custom      $title make · make all  "<0-9>s ]] || fail "the working session's line (title cut to 28): [${lines[3]}]"
assert_contains "$tty" "${ESC}[33m●${ESC}[0m custom" "the waiting session's amber dot"
assert_contains "$tty" "${ESC}[38;5;173m●${ESC}[0m custom" "the working session's dot"

# Step 2: pretty, key-sorted JSON with ISO 8601 dates.
json=$(ambient status --json)
assert_eq "$(jq -r 'length' <<< $json)" 2 "sessions in the JSON"
assert_eq "$json" "$(jq -S --indent 2 . <<< $json | sed 's/\//\\\//g')" "the JSON is pretty-printed with sorted keys"
since=$(jq -r '.[0].activitySince' <<< $json)
[[ $since == <4>-<2>-<2>T<2>:<2>:<2>Z ]] || fail "activitySince is not ISO 8601: [$since]"

# Step 3: with Ambient quit.
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
start=$EPOCHREALTIME
err=$(ambient status 2>&1)
code=$?
ms=$(( (EPOCHREALTIME - start) * 1000 ))
assert_eq "$code" 1 "exit code with Ambient quit"
assert_contains "$err" "Ambient isn't running. Open Ambient.app, then try again." "message with Ambient quit"
(( ms < 3500 )) || fail "took ${ms%.*} ms with Ambient quit (want about 3 s at most)"
