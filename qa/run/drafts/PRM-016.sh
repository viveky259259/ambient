#!/bin/zsh
# PRM-016 · A session that ends withdraws its prompts.
# needs-app: yes
# checks: part
# Left to a person: the card and the session leaving the island on screen.
# Answering on, wait 20 s. A recorded prompt waits in the --answer hook of a stand-in agent process; the script kills
# that process (the one it started), as when a Claude Code session's terminal tab is closed.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
P='{"session_id":"prm-016","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
ask_detached "$QA_ROOT/ask" "$P" hook claude --answer
wait_for 3 sess_is prm-016 .activity.waiting.reason command
hook_pid=$(<"$QA_ROOT/ask.pid") agent_pid=$(<"$QA_ROOT/ask.agent")
sleep 1
kill -0 $hook_pid 2>/dev/null || fail "the prompt was handed back before the session ended"

start=$EPOCHREALTIME
kill $agent_pid
while kill -0 $hook_pid 2>/dev/null; do
  (( $(ms_since $start) > 15000 )) && fail "the card stayed 15 s after the session's process ended (countdown is 20 s)"
  sleep 0.1
done
ms=$(ms_since $start)
assert_eq "$(<"$QA_ROOT/ask")" "" "hook output (nothing answered)"
wait_for 3 sess_is prm-016 .sessionId ""
(( ms < 7000 )) || fail "withdrawn $ms ms after the session ended (the app checks every 5 s; want well before the countdown)"
note "withdrawn $ms ms after the agent process ended"
