#!/bin/zsh
# APP-017 · `ambient demo` plays the tour from a terminal.
# needs-app: yes
# timeout: 120
# Run through a pseudo-terminal (`script`) so its colours and line timings are those a terminal sees.
source "$QA_REPO/qa/run/lib.sh"

CLI=$QA_APP/Contents/Helpers/ambient
gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
ESC=$'\e'

start=$EPOCHREALTIME
script -q /dev/null "$CLI" demo </dev/null | while IFS= read -r line; do
  print -r -- "$(( EPOCHREALTIME - start )) ${line%$'\r'}"
done > $QA_ROOT/demo.log
code=${pipestatus[1]}
total=$(( EPOCHREALTIME - start ))
assert_eq "$code" 0 "exit code of ambient demo"
lines=("${(@f)$(<$QA_ROOT/demo.log)}")
assert_eq "${#lines}" 9 "lines printed"
strip() { print -r -- "${1#* }" | sed "s/${ESC}\[[0-9;]*m//g"; }
at() { print -r -- "${1%% *}"; }

assert_eq "$(strip ${lines[1]})" "Ambient demo — watch the notch, the Dock and the menu bar" "first line"
titles=("Claude starts working" "Codex joins" "Claude needs permission" "Claude gets back to work"
        "Gemini hits an error" "Codex finishes" "Claude finishes")
colors=("38;5;173" "38;5;173" "33" "38;5;173" "31" "32" "32")
for i in {1..7}; do
  line=${lines[i+1]}
  assert_eq "$(strip $line)" "  ● ${titles[i]}" "step $i"
  assert_contains "$line" "${ESC}[${colors[i]}m●" "step $i's coloured dot"
  if (( i > 1 )); then
    gap=$(( $(at $line) - $(at ${lines[i]}) ))
    (( gap > 2.7 && gap < 3.6 )) || fail "step $i came ${gap}s after the one before (want 3)"
  fi
done
assert_eq "$(strip ${lines[9]})" "Clearing the demo sessions in 15 seconds…" "last line"
wait_after=$(( total - $(at ${lines[9]}) ))
(( wait_after > 14.5 && wait_after < 16.5 )) || fail "exited ${wait_after}s after the last line (want 15)"
sleep 0.5
assert_not_contains "$(ambient status --json)" '"demo-' "sessions left after the demo"
note "the tour took ${total%.*} s"

# Step 2: with Ambient quit.
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
ambient demo >/dev/null 2>&1
assert_eq "$?" 1 "exit code of ambient demo with Ambient quit"
