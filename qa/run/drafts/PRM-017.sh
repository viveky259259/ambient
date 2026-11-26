#!/bin/zsh
# PRM-017 · Several prompts queue in order, each with its own time.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: the card showing A with 1 of 3, then B with 1 of 2 and its remaining time; answering A by a click.
# Answering on, wait 20 s. Prompts from sessions A, B and C arrive 3 s apart and nobody answers: each must go back to
# its agent 20 s after it arrived, whatever is ahead of it (a reset would make B wait 37 s).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
for s in a b c; do
  ask_detached "$QA_ROOT/ask-$s" '{"session_id":"prm-017-'$s'","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/'$s'","tool_name":"Bash","tool_input":{"command":"make '$s'"}}' hook claude --answer
  [[ $s != c ]] && sleep 3
done
for s in a b c; do
  ask_wait "$QA_ROOT/ask-$s" 40
  assert_eq "$(<"$QA_ROOT/ask-$s")" "" "$s: hook output"
  note "$s: handed back after $ASK_MS ms"
  (( ASK_MS >= 19500 && ASK_MS <= 21000 )) || fail "prompt $s went back after $ASK_MS ms (want its own 20 s)"
done
