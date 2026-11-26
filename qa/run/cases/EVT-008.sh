#!/bin/zsh
# EVT-008 · Subagents are counted and reset when the turn ends.
# needs-app: yes
# Replays Claude Code's SubagentStart/SubagentStop hooks for two parallel Task subagents, then stray stops.
source "$QA_REPO/qa/run/lib.sh"

S='{"session_id":"evt8-run","transcript_path":"'$HOME'/.claude/projects/p/evt8-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'
subagents() { ambient status --json | jq -r '.[] | select(.id=="claude:evt8-run") | .subagents'; }
expect_subagents() { # count what
  local got end=$(( EPOCHREALTIME + 3 ))
  while :; do
    got=$(subagents)
    [[ $got == "$1" ]] && { note "subagents $got ($2)"; return 0; }
    (( EPOCHREALTIME > end )) && fail "subagents $2: expected [$1], got [$got]"
    sleep 0.1
  done
}

hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"two subagents"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"description":"Find callers","prompt":"x","subagent_type":"Explore"}}'
hook claude "$S"',"hook_event_name":"SubagentStart","agent_type":"Explore"}'
hook claude "$S"',"hook_event_name":"SubagentStart","agent_type":"Explore"}'
expect_subagents 2 "while both run"
hook claude "$S"',"hook_event_name":"SubagentStop","agent_type":"Explore"}'
expect_subagents 1 "after one finished"
hook claude "$S"',"hook_event_name":"SubagentStop","agent_type":"Explore"}'
expect_subagents 0 "after both finished"

# A turn that ends with a stop missed.
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"again"}'
hook claude "$S"',"hook_event_name":"SubagentStart","agent_type":"Explore"}'
hook claude "$S"',"hook_event_name":"SubagentStart","agent_type":"Explore"}'
hook claude "$S"',"hook_event_name":"SubagentStop","agent_type":"Explore"}'
expect_subagents 1 "with one stop still to come"
hook claude "$S"',"hook_event_name":"Stop","last_assistant_message":"done"}'
expect_subagents 0 "once the turn is done, a stop missed"

# Extra stops with none running.
hook claude "$S"',"hook_event_name":"SubagentStop"}'
hook claude "$S"',"hook_event_name":"SubagentStop"}'
sleep 0.5
expect_subagents 0 "after two stops with none running"
