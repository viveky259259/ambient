#!/bin/zsh
# MEM-009 · `until_session_ends` entries go when the writing session ends or its agent exits.
# needs-app: yes
# timeout: 90
# Stand-in Claude Code processes: one ends its session with SessionEnd, one is killed with kill -9 (it's this script's own).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
root=$(real "$QA_ROOT/qa-mem")
cd "$QA_ROOT/qa-mem"

agent_start "$QA_ROOT/a1.out" claude mem-009-a "$root" <<EOF
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
{"hook":{"hook_event_name":"UserPromptSubmit","prompt":"keep a scratch note"}}
{"sleep":1}
$(call memory_write '{"key":"scratch","value":"wip","until_session_ends":true}')
{"sleep":3}
{"hook":{"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}}
EOF
wait_reply "$QA_ROOT/a1.out" 1
assert_eq "$(reply "$QA_ROOT/a1.out" 1 | jq -r .isError)" false "step 1 write: $(reply "$QA_ROOT/a1.out" 1)"
json=$(ambient memory get scratch --json)
assert_eq "$(jq -r .until_session_ends <<< $json)" true "step 2 until_session_ends"
assert_eq "$(jq -r .shared_by <<< $json)" "Claude Code (claude:mem-009-a)" "step 2 shared_by"
wait $QA_BG_PIDS[-1] 2>/dev/null
sleep 5
err=$(ambient memory get scratch 2>&1)
assert_contains "$err" "Nothing is shared as scratch" "step 3, 5 s after SessionEnd"

agent_start "$QA_ROOT/a2.out" claude mem-009-b "$root" <<EOF
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
{"hook":{"hook_event_name":"UserPromptSubmit","prompt":"keep a scratch note"}}
{"sleep":1}
$(call memory_write '{"key":"scratch","value":"wip","until_session_ends":true}')
{"sleep":60}
EOF
wait_reply "$QA_ROOT/a2.out" 1
assert_eq "$(ambient memory get scratch)" wip "step 4 written again"
kill -9 $AGENT_PID
sleep 10
err=$(ambient memory get scratch 2>&1)
assert_contains "$err" "Nothing is shared as scratch" "step 4, 10 s after the agent was killed"

# No hooks: Ambient can't tell which session is asking.
r=$(agent_run claude mem-009-c "$root" <<EOF | sed -n 2p
$(call memory_write '{"key":"scratch","value":"wip","until_session_ends":true}')
EOF
)
assert_eq "$(jq -r .isError <<< $r)" true "step 5 isError"
assert_eq "$(jq -r .text <<< $r)" "Ambient can't tell which session is asking, so it can't keep this only until the session ends. Give it ttl_minutes instead." "step 5 message"
