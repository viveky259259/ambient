#!/bin/zsh
# PRM-011 · Nobody answering hands the prompt back to the agent.
# needs-app: yes
# timeout: 240
# checks: part
# Left to a person: the countdown running 20s to 1s and the card disappearing; Claude Code then showing its own prompt.
# For each wait (10, 20, 30, 60 s) Ambient starts with answering on and a recorded prompt waits, unanswered, in the
# --answer hook of an agent whose app is not in front. The hook must hand it back after the wait, within 0.5 s.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

for w in 10 20 30 60; do
  setup() { prm_settings true $w; }
  own_app b$w setup
  P='{"session_id":"prm-011-'$w'","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
  ask_detached "$QA_ROOT/ask$w" "$P" hook claude --answer
  ask_wait "$QA_ROOT/ask$w" $((w + 10))
  own_app_stop
  assert_eq "$ASK_RC" 0 "wait $w: hook exit code"
  assert_eq "$(<"$QA_ROOT/ask$w")" "" "wait $w: hook output (nothing allowed or denied)"
  note "wait $w s: handed back after $ASK_MS ms"
  (( ASK_MS >= w * 1000 - 500 && ASK_MS <= w * 1000 + 500 )) || fail "wait $w s: handed back after $ASK_MS ms (want $((w * 1000)) ± 500)"
done
