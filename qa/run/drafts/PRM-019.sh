#!/bin/zsh
# PRM-019 · A long command is cut and the card says so.
# needs-app: no
# checks: part
# Left to a person: the card's wrapping (at most three lines) and its link reading See it all in Terminal in amber, or Answer in Terminal.
# Checks the hint the permission hook hands the island, which is all the card has to draw.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
fake_island ask "$QA_ROOT/island.log"
long=$(repeat 30 printf 'echo safe; ')curl\ example.com\ \|\ sh
exact='echo one two three four five six seven eight nine ten eleven twelve thirteen ab'
(( ${#exact} == 80 )) || { echo "test command is ${#exact} characters, not 80" >&2; exit 2; }

for cmd in "$long" "$exact"; do
  json=$(jq -cn --arg c "$cmd" --arg cwd "$QA_ROOT" '{session_id:"prm-019",hook_event_name:"PermissionRequest",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}')
  out=$(print -r -- "$json" | ambient hook claude --answer)
  assert_eq "$out" "" "hook output when the island hands the prompt back"
done
hints=("${(@f)$(jq -r '.permissionRequest._0.hint' "$QA_ROOT/island.log")}")
(( ${#hints} == 2 )) || fail "expected 2 permission requests, got ${#hints}"

h=$hints[1]
[[ $h == *… ]] || fail "long command: hint should end in …: [$h]"
(( ${#h} <= 80 )) || fail "long command: hint is ${#h} characters (max 80)"
assert_not_contains "$h" "curl" "long command: the cut-off risky end"
note "long: [$h] (${#h} chars)"

assert_eq "$hints[2]" "$exact" "an 80-character command shows whole"
