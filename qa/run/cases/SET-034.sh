#!/bin/zsh
# SET-034 · ambient status lists sessions or says the app isn't running.
# needs-app: yes
# Two recorded Claude Code sessions stand in for real ones. Step 1 points the CLI at an empty AMBIENT_HOME, where
# no app listens.
source "$QA_REPO/qa/run/lib.sh"

mkdir -p "$QA_ROOT/none"
err=$(AMBIENT_HOME="$QA_ROOT/none" ambient status 2>&1 >/dev/null); code=$?
assert_eq "$err" "✗ Ambient isn't running. Open Ambient.app, then try again." "status with no app"
assert_eq "$code" 1 "exit code with no app"

long=a-project-folder-with-a-very-long-name
mkdir -p "$QA_ROOT/$long" "$QA_ROOT/api"
for s in one:$QA_ROOT/$long two:$QA_ROOT/api; do
  S='{"session_id":"st-'${s%%:*}'","cwd":"'${s#*:}'"'
  hook claude "$S"',"hook_event_name":"SessionStart","source":"startup"}'
  hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"tidy the tests"}'
done
wait_for 5 sh -c "[ \"\$('$QA_APP/Contents/Helpers/ambient' status --json | jq length)\" = 2 ]"

out=$(ambient status | cat); code=$?
assert_eq "$code" 0 "status exit code"
lines=("${(@f)out}")
[[ ${lines[1]} == "Ambient · 2 sessions · "?* ]] || fail "header: [${lines[1]}]"
assert_eq "${#lines}" 3 "lines (header + two sessions)"
for l in ${lines[2,3]}; do [[ $l == "  ● claude "* ]] || fail "session line: [$l]"; done
assert_not_contains "$out" $'\e[' "piped output"
# Each title is at most 28 characters (Describe.title, cut with an ellipsis).
json=$(ambient status --json)
# A session without a title shows its project, the cwd's folder (Session.project).
titles=("${(@f)$(print -r -- "$json" | jq -r '.[] | .title // (.cwd | split("/") | last)')}")
(( ${titles[(I)$long]} )) || fail "no session shows the long project name: ${titles}"
for t in $titles; do
  shown=$t; (( ${#t} > 28 )) && shown="${t[1,27]}…"
  assert_contains "$out" "$shown" "title column"
  (( ${#t} > 28 )) && assert_not_contains "$out" "$t" "an over-long title"
done

# --json: pretty, key-sorted, ISO 8601 dates.
print -r -- "$json" | jq -e 'length == 2' >/dev/null || fail "--json is not a list of two sessions"
assert_eq "$(print -r -- "$json" | jq '[.. | objects | keys_unsorted == keys] | all')" true "every object in --json has sorted keys"
(( $(print -r -- "$json" | wc -l) > 10 )) && [[ $json == *$'\n    "'* ]] || fail "--json is not pretty-printed"
[[ $json =~ '"20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' ]] || fail "--json has no ISO 8601 date"

# Colour on a terminal; none with NO_COLOR.
tty=$(script -q /dev/null "$QA_APP/Contents/Helpers/ambient" status </dev/null)
assert_contains "$tty" $'\e[' "status on a terminal"
tty=$(NO_COLOR=1 script -q /dev/null "$QA_APP/Contents/Helpers/ambient" status </dev/null)
assert_not_contains "$tty" $'\e[' "status on a terminal with NO_COLOR=1"
note "${lines[1]}"
