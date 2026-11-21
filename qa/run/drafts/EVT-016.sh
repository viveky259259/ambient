#!/bin/zsh
# EVT-016 · Cursor's hooks never print a reply, so they can never approve anything.
# needs-app: yes
# Runs each agent's hook as the case does, with Ambient running, then with no Ambient (a home whose socket nobody serves).
source "$QA_REPO/qa/run/lib.sh"

typeset -A payloads=(
  cursor   '{"conversation_id":"c1","hook_event_name":"postToolUse","tool_name":"Shell"}'
  claude   '{"session_id":"x1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
  codex    '{"session_id":"x2","transcript_path":"/tmp/r.jsonl","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
  copilot  '{"sessionId":"x3","toolName":"bash","toolArgs":"{\"command\":\"rm -rf build\"}"}'
  opencode '{"session_id":"x4","hook_event_name":"Permission","permission":"bash","patterns":["rm -rf build"],"metadata":{"command":"rm -rf build"}}'
  custom   '{"session_id":"x5","event":"waiting","reason":"command","message":"rm -rf build"}'
)
typeset -A events=(copilot preToolUse cursor postToolUse)

for where in running quit; do
  for agent in cursor claude codex copilot opencode custom; do
    if [[ $where == quit ]]; then
      bytes=$(print -r -- "$payloads[$agent]" | AMBIENT_HOME=$QA_ROOT/no-app ambient hook $agent ${events[$agent]:-} | wc -c)
    else
      bytes=$(print -r -- "$payloads[$agent]" | ambient hook $agent ${events[$agent]:-} | wc -c)
    fi
    assert_eq "${bytes// /}" 0 "bytes $agent's hook printed (Ambient $where)"
  done
  note "Ambient $where: 0 bytes from cursor, claude, codex, copilot, opencode and custom"
done
